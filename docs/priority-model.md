# Priority model (advisory ML)

## Model

`GradientBoostingRegressor(n_estimators=300, max_depth=3, learning_rate=0.1,
subsample=0.9)` — `scripts/train_priority_model.py`.

Features: `{severity_code: 0..3, duplicate_count: capped 20, age_hours: capped
72, is_master: 0/1}`. Label: the **audited rule-based priority score 0..100**
(`civic.score_priority` values) plus additive σ=1.0 noise; 8 000 synthetic
samples labeled entirely by the rule, so the learner approximates the
explanations we already publish.

## Real, measured metrics (local run, artifacts committed)

| Metric | Value |
| --- | --- |
| n_train / n_test | 6 400 / 1 600 |
| MAE | 0.827 |
| RMSE | 1.041 |
| R² | 0.9946 |
| Label-band accuracy (bands 0–30 / 30–55 / 55–80 / 80–100) | 0.9381 |
| Feature importance | severity .592, duplicate_count .329, age .057, is_master .022 |

### Correction (2026-09-26) — label-band accuracy was previously reported as 1.0

`label_for()` iterated the band table in ascending order and returned the first
band whose lower bound the score cleared. Because the first band is
`("low", 0, 30)`, **every** score ≥ 0 returned `"low"`. Two consequences:

- the `/v1/priority` endpoint reported `label="low"` for every issue;
- the recorded label-band accuracy of `1.0` was a **tautology** — it compared
  `"low"` against `"low"`.

The band tables are stored low→high for readability, so the fix scans them with
`reversed()` rather than reordering the constants
(`ai_service/app/services/priority.py`, and the same fix in
`ai_service/scripts/train_priority_model.py`).

The honest metric was then recomputed against the **already-trained**
checkpoint on the identical evaluation split (seed `20260926`, `test_size=0.2`,
`random_state=42`). The model was **not** retrained or overwritten; only the
scoring was corrected. Full confusion matrix (rows = rule, cols = model):

| rule ↓ / model → | low | medium | high | critical |
| --- | --- | --- | --- | --- |
| **low** | 418 | 7 | 0 | 0 |
| **medium** | 59 | 839 | 18 | 0 |
| **high** | 0 | 15 | 244 | 0 |
| **critical** | 0 | 0 | 0 | 0 |

Result: **0.9381** (was `1.0`). Marginals — rule: low 425 / medium 916 /
high 259; model: low 477 / medium 861 / high 262. The confusion is now real
and confined to adjacent bands, which is what a healthy approximation looks
like. The `critical` band is empty because the rule policy never produces a
score ≥ 80.

Regression metrics (MAE / RMSE / R²) were always correct and are unchanged.

**Production impact: none.** The `priority_label` that the Citizen app and the
Authority Admin read comes from the deterministic rule in
`backend/issues/civic.py::score_priority`, which bands correctly using
`lo <= score < hi`. The bug only affected the sidecar's diagnostic
`vision["priority_model"]["label"]`, and the sidecar is not deployed.

Two regression tests were added (AI suite 9 → 11) covering the band
boundaries, out-of-range clamping, and endpoint label/score agreement.

Artifacts: `ai_service/artifacts/priority_model_v1.joblib` (git-ignored binary)
+ `priority_model_v1_meta.json` (committed; includes the honest-label fields).

## Role in the product — advisory only

- The **rule-based priority** remains authoritative for the priority chip and
  ordering (it stays fully explainable: `reasons[]`).
- `priority_model_score` is stored read-only on the issue and surfaced under
  `vision.priority_model` with a `honest_note: prototype` — a learnable
  estimate for dashboards, never presented as ground truth.

## Why this is honest

- The model is trained on the *labels of the very rule it complements* — good
  for a demo of MLOps plumbing (train script, versioned artifact + meta,
  serving, graceful degradation) but it does **not** prove "real-world
  accuracy". All metrics above are reprodu-cible, none are field accuracy.
- `priority_predict()` returns `None` on any failure (service down, bad
  payload) and the engine silently keeps the explainable score.

## Reproduce

```
cd ai_service
.\.venv\Scripts\python.exe scripts/train_priority_model.py
.\.venv\Scripts\python.exe -m pytest -q
```