import { useState } from "react";
import { PriorityBadge } from "../../components/Badges";
import { IconChart, IconChevronRight } from "../../components/icons";
import { formatPercent } from "../../utils/format";
import { categoryLabel, priorityClassLabel, priorityStyles } from "../../utils/media";
import type { IssueDetail, PriorityDetail, PriorityEngineInfo } from "../../types";

/**
 * "Why is this issue ranked here?"
 *
 * Everything rendered here comes from the backend's stored `priority_detail`.
 * The panel performs no scoring of its own: it displays the score, the band, and
 * the per-component contributions the engine actually recorded, plus the
 * human-readable reason text it produced for each one.
 *
 * `engine_honest_label` is shown verbatim. The engine is a transparent weighted
 * rule model, and this UI must never present it as a trained model.
 */
export function PriorityExplanation({
  issue,
  engine,
}: {
  issue: IssueDetail;
  engine?: PriorityEngineInfo | null;
}) {
  const [showModel, setShowModel] = useState(false);
  const detail: PriorityDetail | null =
    issue.priority_explanation ?? issue.priority_detail ?? null;

  // The deployed backend reports the score, the band and a flat list of
  // `priority_reasons` ({note, factor, points}) rather than the nested detail
  // blob. Both shapes are read here so the panel shows the backend's own
  // contribution list either way.
  const detailReasons = Array.isArray(detail?.reasons) ? detail.reasons : [];
  const reasons = detailReasons.length > 0 ? detailReasons : (issue.priority_reasons ?? []);
  const components = detail?.components ?? {};
  const score = detail?.score ?? issue.priority ?? 0;
  const band = detail?.class ?? issue.priority_class;
  const styles = priorityStyles(band);
  const modelScore = issue.priority_model_score ?? null;

  // The component caps let each bar be drawn relative to what it *could* have
  // contributed, which is what makes the bar lengths comparable.
  const caps = new Map<string, number>();
  for (const c of engine?.components ?? []) caps.set(c.code, c.cap);
  const worst = Math.max(1, ...Object.values(components).map((v) => Math.abs(v)));

  return (
    <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="flex items-center gap-2">
          <span className="rounded-lg bg-slate-900 p-2 text-brand-400">
            <IconChart width={16} height={16} />
          </span>
          <div>
            <h3 className="text-sm font-semibold text-slate-800">
              Priority score
            </h3>
            <p className="text-[11px] text-slate-400">
              {detail?.engine_honest_label ??
                "How urgently this should be acted on — separate from severity."}
            </p>
          </div>
        </div>
        <PriorityBadge score={score} priorityClass={band} />
      </div>

      <div className="mt-4 flex items-center gap-4">
        <div className="flex-none">
          <p
            className={`text-4xl font-bold tracking-tight tabular-nums ${styles.badge.split(" ").find((c) => c.startsWith("text-")) ?? "text-slate-800"}`}
          >
            {Math.round(score)}
          </p>
          <p className="text-[11px] font-semibold uppercase tracking-wide text-slate-400">
            out of {engine?.score_range?.[1] ?? 100} · {priorityClassLabel(band)}
          </p>
        </div>
        <div className="min-w-0 flex-1">
          <div className="h-2.5 w-full overflow-hidden rounded-full bg-slate-100">
            <div
              className={`h-full rounded-full ${
                band === "critical"
                  ? "bg-rose-500"
                  : band === "high"
                    ? "bg-violet-500"
                    : band === "medium"
                      ? "bg-sky-500"
                      : "bg-slate-400"
              }`}
              style={{
                width: `${Math.max(2, Math.min(100, score))}%`,
              }}
            />
          </div>
          {engine?.class_thresholds?.length ? (
            <p className="mt-1.5 text-[11px] text-slate-400">
              Bands:{" "}
              {engine.class_thresholds
                .map((t) => `${priorityClassLabel(t.class)} ≥ ${t.min_score}`)
                .join(" · ")}
            </p>
          ) : null}
        </div>
      </div>

      {reasons.length > 0 ? (
        <div className="mt-4">
          <p className="text-[11px] font-bold uppercase tracking-wider text-slate-500">
            What contributed
          </p>
          <ul className="mt-2 space-y-2.5">
            {reasons.map((r) => {
              const points = r.points ?? 0;
              const cap = caps.get(r.code);
              const widthPct = cap
                ? Math.max(3, Math.min(100, (points / cap) * 100))
                : Math.max(3, Math.min(100, (Math.abs(points) / worst) * 100));
              return (
                <li key={r.code}>
                  <div className="flex items-baseline justify-between gap-3 text-xs">
                    <span className="font-semibold text-slate-700">{r.label}</span>
                    <span className="flex-none tabular-nums text-slate-600">
                      +{round1(points)}
                      {cap != null ? (
                        <span className="text-slate-400"> / {cap}</span>
                      ) : null}
                    </span>
                  </div>
                  <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full bg-slate-100">
                    <div
                      className="h-full rounded-full bg-brand-500"
                      style={{ width: `${widthPct}%` }}
                    />
                  </div>
                  {r.detail ? (
                    <p className="mt-1 text-[11px] leading-relaxed text-slate-400">
                      {r.detail}
                    </p>
                  ) : null}
                </li>
              );
            })}
          </ul>
        </div>
      ) : (
        <p className="mt-4 rounded-xl bg-slate-50 px-4 py-3 text-sm text-slate-500">
          The backend reported a priority score of {Math.round(score)} but did not
          record a per-component breakdown for this report, so the individual
          contributions cannot be shown.
        </p>
      )}

      {modelScore != null ? (
        <p className="mt-3 rounded-xl bg-slate-50 px-4 py-3 text-[11px] leading-relaxed text-slate-500">
          Advisory model score: <strong className="font-semibold">{modelScore}</strong>.
          This is a prototype estimate reported alongside the rule score. The
          transparent rule engine above is what determines the ranking.
        </p>
      ) : null}

      {detail?.inputs ? (
        <div className="mt-4 rounded-xl border border-slate-100 p-3">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">
            Inputs the engine saw
          </p>
          <dl className="mt-2 grid grid-cols-2 gap-x-4 gap-y-1.5 text-xs sm:grid-cols-3">
            <Input label="Category" value={categoryLabel(detail.inputs.category)} />
            <Input label="Severity" value={detail.inputs.severity} />
            <Input
              label="Reports in cluster"
              value={String(detail.inputs.cluster_size)}
            />
            <Input
              label="Distinct report days"
              value={String(detail.inputs.distinct_report_days)}
            />
            <Input
              label="Open for (hours)"
              value={String(detail.inputs.open_hours)}
            />
            <Input
              label="Mean image similarity"
              value={
                detail.inputs.mean_similarity == null
                  ? "n/a"
                  : formatPercent(detail.inputs.mean_similarity)
              }
            />
            <Input
              label="Prior reports at location"
              value={String(detail.inputs.prior_reports_at_location)}
            />
          </dl>
        </div>
      ) : null}

      {engine ? (
        <div className="mt-4 border-t border-slate-100 pt-3">
          <button
            type="button"
            onClick={() => setShowModel((v) => !v)}
            aria-expanded={showModel}
            className="flex w-full items-center gap-1.5 text-left text-[11px] font-bold uppercase tracking-wider text-slate-500 hover:text-slate-700"
          >
            <IconChevronRight
              width={12}
              height={12}
              className={`transition-transform ${showModel ? "rotate-90" : ""}`}
            />
            How is priority computed?
          </button>
          {showModel ? (
            <EngineModel engine={engine} />
          ) : null}
        </div>
      ) : (
        <p className="mt-4 border-t border-slate-100 pt-3 text-[11px] leading-relaxed text-slate-400">
          Priority is a transparent weighted rule model, not a trained machine
          learning model: each contribution above is a named factor with a fixed
          point value. This deployment does not publish the component catalogue
          for the engine, so the exact weights are not shown here rather than
          being quoted from a different deployment.
        </p>
      )}
    </div>
  );
}

function Input({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-[11px] text-slate-400">{label}</dt>
      <dd className="font-semibold capitalize text-slate-700">{value}</dd>
    </div>
  );
}

/**
 * The live component catalogue, served by `GET /authority/meta/`.
 *
 * This is read from the backend rather than hardcoded precisely so the
 * documentation cannot drift away from the scoring that actually runs.
 */
function EngineModel({ engine }: { engine: PriorityEngineInfo }) {
  return (
    <div className="mt-3 rounded-xl bg-slate-50 p-3">
      <p className="text-[11px] font-semibold text-slate-600">
        {engine.engine} · {engine.engine_honest_label}
      </p>
      <ul className="mt-2 space-y-1.5">
        {engine.components.map((c) => (
          <li key={c.code} className="text-[11px] leading-relaxed">
            <span className="font-semibold text-slate-700">{c.label}</span>
            <span className="text-slate-400">
              {" "}
              — {c.description} Cap {c.cap}
              {c.half_saturation != null
                ? `, half-saturating at ${c.half_saturation}`
                : ""}
              .
            </span>
          </li>
        ))}
      </ul>
      {engine.duplicate_signals ? (
        <div className="mt-3 border-t border-slate-200 pt-2">
          <p className="text-[11px] font-semibold text-slate-600">
            Duplicate signal weights
          </p>
          <ul className="mt-1 flex flex-wrap gap-x-3 gap-y-0.5">
            {Object.entries(engine.duplicate_signals).map(([k, v]) => (
              <li key={k} className="text-[11px] text-slate-500">
                {k.replace(/_/g, " ")}{" "}
                <span className="font-semibold text-slate-700">{v}</span>
              </li>
            ))}
          </ul>
        </div>
      ) : null}
      <p className="mt-3 text-[11px] leading-relaxed text-slate-500">
        {engine.honest_note}
      </p>
    </div>
  );
}

function round1(n: number): string {
  return Number.isInteger(n) ? String(n) : n.toFixed(1);
}
