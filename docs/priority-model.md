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
| Label-band accuracy (0–19/20–39/40–59/60–79/80–100) | 1.0 |
| Feature importance | severity .592, duplicate_count .329, age .057, is_master .022 |

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