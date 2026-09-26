import type { IssueOrdering } from "../../types";

const LABELS: Record<IssueOrdering, string> = {
  priority: "Priority (highest first)",
  newest: "Newest first",
  oldest: "Oldest first",
  cluster: "Largest cluster first",
  severity: "Severity",
  reports: "Most supporting reports",
  status: "Status",
};

/**
 * Sort control.
 *
 * The backend whitelists ordering keys and returns a 400 listing the valid ones
 * for anything else, so this sends only the known keys rather than passing
 * through a field name.
 */
export function SortSelect({
  value,
  onChange,
  options,
}: {
  value: IssueOrdering;
  onChange: (next: IssueOrdering) => void;
  options: IssueOrdering[];
}) {
  return (
    <label className="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-slate-500">
      Sort
      <select
        value={value}
        onChange={(e) => onChange(e.target.value as IssueOrdering)}
        className="h-9 rounded-xl border border-slate-300 bg-white px-3 text-sm font-normal normal-case tracking-normal text-slate-700 focus:border-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-600/20"
      >
        {options.map((o) => (
          <option key={o} value={o}>
            {LABELS[o]}
          </option>
        ))}
      </select>
    </label>
  );
}
