import { SeverityBadge } from "../../components/Badges";
import { IconShield } from "../../components/icons";
import { formatPercent } from "../../utils/format";
import { categoryLabel, severityColor } from "../../utils/media";
import type { Issue, SeveritySignal, VisionDetection } from "../../types";

function signalLabel(sig: SeveritySignal): string {
  switch (sig.type) {
    case "category_base":
      return `Category base weight (${categoryLabel(String(sig.value))})`;
    case "keyword":
      return `Description keyword "${sig.value}"`;
    case "duplicate_reports":
      return `${sig.value} supporting reports escalate severity`;
    default:
      return sig.type.replace(/_/g, " ");
  }
}

export function AIIntelligence({ issue }: { issue: Issue }) {
  const analysis = issue.analysis ?? ({} as Issue["analysis"]);
  const hasAnalysis =
    analysis && Object.keys(analysis).length > 0 && typeof analysis === "object";
  const severityData = analysis?.severity;
  const signals: SeveritySignal[] = Array.isArray(severityData?.signals)
    ? severityData.signals
    : [];

  return (
    <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
      <div className="flex items-center gap-2">
        <span className="rounded-lg bg-slate-900 p-2 text-brand-400">
          <IconShield width={16} height={16} />
        </span>
        <div>
          <h3 className="text-sm font-semibold text-slate-800">AI civic intelligence</h3>
          <p className="text-[11px] text-slate-400">
            {hasAnalysis ? analysis.engine_honest_label : "No analysis breakdown recorded for this report"}
          </p>
        </div>
      </div>

      {/* Classification */}
      <div className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-3">
        <div className="rounded-xl border border-slate-100 bg-slate-50/60 p-3">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">
            Classification
          </p>
          <p className="mt-1 text-sm font-bold capitalize text-slate-900">
            {categoryLabel(issue.category)}
          </p>
          <p className="text-[11px] text-slate-400">citizen-selected category</p>
        </div>
        <div className="rounded-xl border border-slate-100 bg-slate-50/60 p-3">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">
            Cluster confidence
          </p>
          <p className="mt-1 text-sm font-bold text-slate-900">
            {formatPercent(issue.confidence)}
          </p>
          <p className="text-[11px] text-slate-400">similarity to primary report</p>
        </div>
        <div className="rounded-xl border border-slate-100 bg-slate-50/60 p-3">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">
            Severity
          </p>
          <div className="mt-1 flex items-center gap-2">
            <SeverityBadge severity={issue.severity} />
            {severityData?.score != null ? (
              <span
                className="text-sm font-bold"
                style={{ color: severityColor(issue.severity) }}
              >
                {severityData.score}
              </span>
            ) : null}
          </div>
          <p className="text-[11px] text-slate-400">rule-based score · 0–100</p>
        </div>
      </div>

      {/* Vision */}
      <VisionPanel issue={issue} />

      {/* Severity breakdown */}
      {signals.length > 0 ? (
        <div className="mt-3 rounded-xl border border-slate-100 p-3">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">
            How severity was derived
          </p>
          <ul className="mt-2 space-y-1.5">
            {signals.map((sig, i) => (
              <li
                key={`${sig.type}-${i}`}
                className="flex items-center justify-between gap-3 text-sm"
              >
                <span className="text-slate-600">{signalLabel(sig)}</span>
                <span className="flex-none font-semibold text-slate-800">
                  +{sig.points}
                </span>
              </li>
            ))}
          </ul>
        </div>
      ) : null}

      {/* Routing */}
      <div className="mt-3 flex items-center justify-between rounded-xl border border-slate-100 p-3 text-sm">
        <span className="text-slate-600">
          Routed to{" "}
          <strong className="font-semibold text-slate-800">{issue.department}</strong>
        </span>
        <span className="text-[11px] text-slate-400">
          {hasAnalysis ? analysis.department_by.replace(/-/g, " ") : "via category"}
        </span>
      </div>

      <p className="mt-3 text-[11px] leading-relaxed text-slate-400">
        This is an honest, deterministic rule-based engine (not a trained ML
        model). Every value it produces is auditable from the underlying rules.
      </p>
    </div>
  );
}

  /**
   * What the deployment's image analyzer actually reported.
   *
   * The backend is the only source here, and the field names are the ones it
   * actually writes (`detections`, `classifier_labels`, `models`,
   * `vision_notes`). It sends the literal `{status: "not_analyzed", service:
   * null}` when no analyzer is configured and `{status: "unavailable", ...}`
   * when the analyzer did not answer; both are rendered as an honest absence.
   *
   * Nothing here invents a detection, a confidence or a count. If the backend
   * sent no result, the panel says so.
   */
  function VisionPanel({ issue }: { issue: Issue }) {
    const vision = issue.vision;
    const status = typeof vision?.status === "string" ? vision.status : null;
    const service = typeof vision?.service === "string" ? vision.service : null;
    const detections: VisionDetection[] = Array.isArray(vision?.detections)
      ? vision.detections
      : [];
    const classifierLabels: string[] = Array.isArray(vision?.classifier_labels)
      ? vision.classifier_labels.filter(
          (l): l is string => typeof l === "string" && l.length > 0,
        )
      : [];
    const notes: string[] = Array.isArray(vision?.vision_notes)
      ? vision.vision_notes.filter(
          (n): n is string => typeof n === "string" && n.length > 0,
        )
      : [];
    const detectorModel =
      typeof vision?.models?.detection === "string" ? vision.models.detection : null;

    // A result exists only when the backend actually sent detections or labels.
    const hasResult = detections.length > 0 || classifierLabels.length > 0;
    const ranButEmpty = status === "ok" && !hasResult;

    return (
      <div className="mt-3 rounded-xl border border-slate-100 p-3">
        <p className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">
          Image analysis
        </p>

        {hasResult ? (
          <>
            {detections.length > 0 ? (
              <>
                <p className="mt-1.5 text-[11px] font-semibold uppercase tracking-wide text-slate-400">
                  Detected objects
                </p>
                <ul className="mt-1.5 flex flex-wrap gap-1.5">
                  {detections.map((det, i) => (
                    <li
                      key={i}
                      className="rounded-full bg-slate-100 px-2 py-0.5 text-[11px] font-semibold text-slate-700"
                    >
                      {describeObject(det)}
                    </li>
                  ))}
                </ul>
              </>
            ) : null}

            {classifierLabels.length > 0 ? (
              <>
                <p className="mt-2.5 text-[11px] font-semibold uppercase tracking-wide text-slate-400">
                  Scene labels
                </p>
                <ul className="mt-1.5 flex flex-wrap gap-1.5">
                  {classifierLabels.map((label, i) => (
                    <li
                      key={i}
                      className="rounded-full bg-brand-50 px-2 py-0.5 text-[11px] font-semibold text-slate-700"
                    >
                      {label}
                    </li>
                  ))}
                </ul>
              </>
            ) : null}

            {detectorModel || service ? (
              <p className="mt-2 text-[11px] text-slate-400">
                Analyzer: {detectorModel ?? "detector"}
                {service ? ` · ${service}` : ""}
              </p>
            ) : null}

            <p className="mt-2 text-[11px] leading-relaxed text-slate-400">
              The configured detector is a general-purpose COCO object model. It is
              not trained on road defects, so a listed object is a general scene
              label, not a confirmed pothole. Treat it as a hint only.
            </p>
          </>
        ) : (
          <>
            <p className="mt-1.5 text-sm font-semibold text-slate-700">
              {ranButEmpty
                ? "Analyzer ran and reported nothing for this image"
                : "No image analysis for this report"}
            </p>
            <p className="mt-1 text-[11px] leading-relaxed text-slate-400">
              {status
                ? `The backend reported vision status "${status}" for this image.`
                : "This deployment does not report a vision result for the image."}{" "}
              Priority above is computed from the rules, not from an image model.
            </p>
            {notes.length > 0 ? (
              <ul className="mt-1.5 space-y-0.5">
                {notes.map((n, i) => (
                  <li key={i} className="text-[11px] leading-relaxed text-slate-400">
                    {n}
                  </li>
                ))}
              </ul>
            ) : null}
          </>
        )}
      </div>
    );
  }

/** Render one reported object without assuming a particular analyzer shape. */
function describeObject(obj: unknown): string {
  if (typeof obj === "string") return obj;
  if (obj && typeof obj === "object") {
    const o = obj as Record<string, unknown>;
    const label = o.label ?? o.name ?? o.class ?? o.category;
    const score = o.confidence ?? o.score ?? o.probability;
    if (typeof label === "string" && typeof score === "number") {
      return `${label} ${formatPercent(score)}`;
    }
    if (typeof label === "string") return label;
  }
  return "reported object";
}