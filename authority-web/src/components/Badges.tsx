import {
  priorityClassLabel,
  priorityStyles,
  severityLabel,
  severityStyles,
  statusStyles,
} from "../utils/media";

export function SeverityBadge({
  severity,
  showLabel = true,
}: {
  severity: string;
  showLabel?: boolean;
}) {
  const s = severityStyles(severity);
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-semibold ${s.badge}`}
    >
      <span className={`h-1.5 w-1.5 rounded-full ${s.dot}`} />
      {showLabel ? severityLabel(severity) : ""}
    </span>
  );
}

/**
 * Priority score + band.
 *
 * The score is shown because the band alone hides *how* urgent something is:
 * two critical issues can sit at 74 and 96, and that difference drives the
 * queue order. See the priority panel on the detail page for the reasoning.
 */
export function PriorityBadge({
  score,
  priorityClass,
  showLabel = true,
}: {
  score: number;
  priorityClass: string;
  showLabel?: boolean;
}) {
  const s = priorityStyles(priorityClass);
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-semibold tabular-nums ${s.badge}`}
      title={`Priority ${score}/100 (${priorityClassLabel(priorityClass)})`}
    >
      <span className={`h-1.5 w-1.5 rounded-full ${s.dot}`} />
      {Math.round(score)}
      {showLabel ? (
        <span className="font-medium opacity-80">
          {priorityClassLabel(priorityClass)}
        </span>
      ) : null}
    </span>
  );
}

export function StatusBadge({ status }: { status: string }) {
  const s = statusStyles(status);
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-semibold ${s.badge}`}
    >
      <span className={`h-1.5 w-1.5 rounded-full ${s.dot}`} />
      {status
        .replace(/_/g, " ")
        .replace(/\b\w/g, (c) => c.toUpperCase())}
    </span>
  );
}