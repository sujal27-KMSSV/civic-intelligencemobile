"""Train the FixMyGrid priority model (prototype).

This trains sklearn GradientBoosting to APPROXIMATE the audited, explainable
rule-based priority policy (backend/issues/civic.py::score_priority). Labels
are the rule's own deterministic score, so the model genuinely learns the rule;
it is NOT trained on real field triage data (none exists yet), and that
limitation is recorded in the model's metadata.

Outputs (into ai_service/artifacts/):
  priority_model_v1.joblib   - fitted GradientBoostingRegressor
  priority_model_v1_meta.json- features, importances, eval metrics, honest label

Usage:  python -m scripts.train_priority_model
"""

from __future__ import annotations

import json
from pathlib import Path

import joblib
import numpy as np
from sklearn.ensemble import GradientBoostingRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import train_test_split

ROOT = Path(__file__).resolve().parent.parent
ARTIFACTS = ROOT / "artifacts"

SEVERITY_LEVELS = ("low", "medium", "high", "critical")
SEVERITY_BASE = {"low": 10.0, "medium": 20.0, "high": 30.0, "critical": 40.0}
DUP_PER_REPORT = 4.0
DUP_MAX = 20.0
FRESH_24H = 10.0
WARM_72H = 5.0
MASTER_UPLIFT = 5.0
BANDS = (("low", 0, 30), ("medium", 30, 55), ("high", 55, 80), ("critical", 80, 101))

rng = np.random.default_rng(20260926)


def rule_score(sev_code: int, dup_count: int, age_hours: float, is_master: int) -> float:
    score = list(SEVERITY_BASE.values())[sev_code]
    if dup_count > 1:
        score += min((dup_count - 1) * DUP_PER_REPORT, DUP_MAX)
    if age_hours <= 24.0:
        score += FRESH_24H
    elif age_hours <= 72.0:
        score += WARM_72H
    if is_master:
        score += MASTER_UPLIFT
    return float(min(100.0, max(0.0, score)))


def label_for(score: float) -> str:
    for name, lo, _hi in BANDS:
        if score >= lo:
            return name
    return "low"


def make_dataset(n: int = 8000) -> tuple[np.ndarray, np.ndarray]:
    """Engineered-but-diverse samples spanning the rule's feature space."""
    rows = []
    targets = []
    for _ in range(n):
        sev = int(rng.integers(0, 4))
        dup = int(rng.choice([1, 1, 1, 2, 3, 4, 5, 6, 9, 14, 20]))
        age = float(rng.uniform(0.0, 200.0))
        master = int(rng.random() < 0.25)
        features = [float(sev), float(dup), min(age, 72.0), float(master)]
        y = rule_score(sev, dup, age, master)
        y = min(100.0, max(0.0, y + rng.normal(0.0, 1.0)))
        rows.append(features)
        targets.append(y)
    return np.asarray(rows, dtype=float), np.asarray(targets, dtype=float)


def main() -> None:
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    X, y = make_dataset()
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )

    model = GradientBoostingRegressor(
        n_estimators=300,
        max_depth=3,
        learning_rate=0.1,
        subsample=0.9,
        random_state=42,
    )
    model.fit(X_train, y_train)

    preds = model.predict(X_test)
    mae = float(mean_absolute_error(y_test, preds))
    rmse = float(np.sqrt(mean_squared_error(y_test, preds)))
    r2 = float(r2_score(y_test, preds))

    # Label-band agreement (how often the learned score selects the same
    # priority band as the rule it approximates).
    y_labels = [label_for(v) for v in y_test]
    p_labels = [label_for(v) for v in preds]
    band_acc = sum(a == b for a, b in zip(y_labels, p_labels)) / len(y_labels)

    features = ["severity_code", "duplicate_count", "age_hours_capped72", "is_master"]
    meta = {
        "model": "GradientBoostingRegressor",
        "version": "v1",
        "features": features,
        "feature_importances": {
            name: round(float(v), 4)
            for name, v in zip(features, model.feature_importances_)
        },
        "metrics": {
            "mae_points": round(mae, 3),
            "rmse_points": round(rmse, 3),
            "r2": round(r2, 4),
            "label_band_accuracy": round(band_acc, 4),
            "n_train": int(len(y_train)),
            "n_test": int(len(y_test)),
        },
        "baseline_score": float(np.mean(y_train)),
        "target": "rule_priority_score_0_100",
        "honest_label": (
            "Prototype model trained on the audited rule-based priority policy's "
            "own scores. It approximates the rule; it was NOT trained or "
            "calibrated on real-world field triage data."
        ),
    }

    model_path = ARTIFACTS / "priority_model_v1.joblib"
    meta_path = ARTIFACTS / "priority_model_v1_meta.json"
    joblib.dump(model, model_path)
    with open(meta_path, "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2)

    print(f"wrote {model_path}")
    print(f"wrote {meta_path}")
    print("metrics:", json.dumps(meta["metrics"], indent=2))
    print("importances:", json.dumps(meta["feature_importances"], indent=2))


if __name__ == "__main__":
    main()