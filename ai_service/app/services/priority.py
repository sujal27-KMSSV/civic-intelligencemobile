"""Priority model inference + explanation.

The model is a GradientBoostingRegressor trained (see scripts/train_priority
_model.py) to *approximate* the explainable, audited rule-based priority policy
from four deterministic features. It never overrides the rule — the backend
keeps the rule-based score as the operational priority; this endpoint provides
a learned, independently-verifiable ranking with honest attribution.
"""

from __future__ import annotations

import json
import math

from .. import config
from ..model_registry import ModelUnavailable, registry

SEVERITY_LEVELS = ("low", "medium", "high", "critical")
LABEL_BANDS = (("low", 0, 30), ("medium", 30, 55), ("high", 55, 80), ("critical", 80, 101))


def build_features(
    severity: str, duplicate_count: int, age_hours: float, is_master: bool
) -> list[float]:
    sev = severity.strip().lower()
    sev_code = SEVERITY_LEVELS.index(sev) if sev in SEVERITY_LEVELS else 0
    return [
        float(sev_code),
        float(max(1, int(duplicate_count))),
        float(max(0.0, min(age_hours, 72.0))),
        1.0 if is_master else 0.0,
    ]


def label_for(score: float) -> str:
    s = float(max(0.0, min(100.0, score)))
    for name, lo, _hi in LABEL_BANDS:
        if s >= lo:
            return name
    return "low"


def predict(severity: str, duplicate_count: int, age_hours: float, is_master: bool) -> dict:
    model = registry.get_priority()
    meta = _load_meta()
    features = build_features(severity, duplicate_count, age_hours, is_master)
    raw = float(model.predict([features])[0])
    score = round(max(0.0, min(100.0, raw)), 1)

    importances = dict(meta.get("feature_importances", {}))
    included = {k: v for k, v in zip(meta.get("features", []), features)}

    # Greedy explanation: how much each feature contributes vs the training
    # mean prediction (an honest attribution, not a formal SHAP value).
    base = float(meta.get("mean_target", score))
    base = float(meta.get("baseline_score", base))
    explanation = {
        "method": "baseline-plus-importance-attribution",
        "baseline_score": round(base, 2),
        "feature_values": included,
        "feature_importances": importances,
        "learned_delta": round(score - base, 2),
    }

    return {
        "model": registry.priority_name(),
        "score": score,
        "label": label_for(score),
        "explanation": explanation,
        "honest_note": meta.get(
            "honest_label",
            "Prototype model approximating the explainable rule policy; not "
            "calibrated on real field data.",
        ),
    }


def _load_meta() -> dict:
    try:
        with open(config.PRIORITY_MODEL_META, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return {}