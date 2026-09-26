import { IconClose, IconFilter, IconSearch } from "../../components/icons";
import {
  CATEGORIES,
  DEPARTMENTS,
  PRIORITY_CLASSES,
  PRIORITY_CLASS_LABELS,
  SEVERITIES,
  STATUSES,
  STATUS_LABELS,
  type MetaResponse,
} from "../../types";
import { categoryLabel, severityLabel } from "../../utils/media";

export interface IssueFiltersState {
  status: string;
  severity: string;
  /** Priority is a separate axis from severity. */
  priorityClass: string;
  department: string;
  category: string;
  search: string;
  scope: string;
  assigned: string;
}

export const EMPTY_FILTERS: IssueFiltersState = {
  status: "",
  severity: "",
  priorityClass: "",
  department: "",
  category: "",
  search: "",
  scope: "masters",
  assigned: "",
};

/** The backend defaults to `masters`; keeping it explicit documents that. */
export const SCOPE_OPTIONS = [
  {
    value: "masters",
    label: "Physical problems (masters)",
  },
  {
    value: "supporting",
    label: "Supporting reports only",
  },
  { value: "all", label: "All reports" },
];

const ASSIGNED_OPTIONS = [
  { value: "", label: "Anyone" },
  { value: "unassigned", label: "Unassigned" },
  { value: "assigned", label: "Assigned" },
];

function Select({
  label,
  value,
  onChange,
  options,
  placeholder,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  options: { value: string; label: string }[];
  placeholder: string;
}) {
  const active = value !== "";
  return (
    <label className="flex flex-col gap-1">
      <span className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">
        {label}
      </span>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className={`h-10 rounded-xl border px-3 text-sm focus:outline-none focus:ring-2 focus:ring-brand-600/20 ${
          active
            ? "border-brand-300 bg-brand-50 text-slate-900"
            : "border-slate-300 bg-white text-slate-600"
        }`}
      >
        <option value="">{placeholder}</option>
        {options.map((o) => (
          <option key={o.value} value={o.value}>
            {o.label}
          </option>
        ))}
      </select>
    </label>
  );
}

/**
 * All filters here are applied **server-side**. The previous implementation
 * fetched once and filtered in the browser, which silently truncated results
 * behind whatever page size the list endpoint returned.
 */
export function IssueFilters({
  filters,
  onChange,
  resultCount,
  totalCount,
  meta,
}: {
  filters: IssueFiltersState;
  onChange: (next: IssueFiltersState) => void;
  /** Rows on the current page. */
  resultCount: number;
  /** Total rows matching, across all pages. */
  totalCount?: number;
  meta?: MetaResponse | null;
}) {
  const hasActive =
    filters.status !== "" ||
    filters.severity !== "" ||
    filters.priorityClass !== "" ||
    filters.department !== "" ||
    filters.category !== "" ||
    filters.search !== "" ||
    filters.assigned !== "" ||
    filters.scope !== "masters";

  const set = (patch: Partial<IssueFiltersState>) =>
    onChange({ ...filters, ...patch });

  // Prefer the backend's own lists; fall back only while /meta/ is in flight so
  // the panel is never empty.
  const departments = meta?.departments.assignable ?? DEPARTMENTS;
  const categoryOptions = meta?.categories ?? CATEGORIES.map((c) => ({ value: c, label: categoryLabel(c) }));
  const severityOptions = meta?.severities ?? SEVERITIES.map((s) => ({ value: s, label: severityLabel(s) }));
  const statusOptions = meta?.statuses ?? STATUSES.map((s) => ({ value: s, label: STATUS_LABELS[s] }));
  const priorityOptions = meta?.priority_classes ?? PRIORITY_CLASSES.map((p) => ({ value: p, label: PRIORITY_CLASS_LABELS[p] }));

  const shown = totalCount ?? resultCount;

  return (
    <div className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
      <div className="flex items-center gap-2 text-sm font-semibold text-slate-700">
        <IconFilter width={15} height={15} className="text-slate-400" />
        Filter issues
        {hasActive ? (
          <button
            type="button"
            onClick={() => onChange(EMPTY_FILTERS)}
            className="ml-auto flex items-center gap-1 rounded-lg px-2.5 py-1 text-xs font-medium text-slate-500 hover:bg-slate-100"
          >
            <IconClose width={12} height={12} />
            Clear
          </button>
        ) : null}
      </div>

      <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <div className="relative">
          <label className="mb-1 flex text-[11px] font-semibold uppercase tracking-wide text-slate-500">
            Search
          </label>
          <div className="relative">
            <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-slate-400">
              <IconSearch width={15} height={15} />
            </span>
            <input
              type="text"
              value={filters.search}
              onChange={(e) => set({ search: e.target.value })}
              placeholder="ID, description, address…"
              className="h-10 w-full rounded-xl border border-slate-300 bg-white pl-9 pr-3 text-sm text-slate-900 placeholder:text-slate-400 focus:border-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-600/20"
            />
          </div>
        </div>

        <Select
          label="Scope"
          value={filters.scope}
          onChange={(v) => set({ scope: v })}
          placeholder=""
          options={SCOPE_OPTIONS}
        />
        <Select
          label="Category"
          value={filters.category}
          onChange={(v) => set({ category: v })}
          placeholder="All categories"
          options={categoryOptions}
        />
        <Select
          label="Severity"
          value={filters.severity}
          onChange={(v) => set({ severity: v })}
          placeholder="All severities"
          options={severityOptions}
        />
        <Select
          label="Priority"
          value={filters.priorityClass}
          onChange={(v) => set({ priorityClass: v })}
          placeholder="All priorities"
          options={priorityOptions}
        />
        <Select
          label="Status"
          value={filters.status}
          onChange={(v) => set({ status: v })}
          placeholder="All statuses"
          options={statusOptions}
        />
        <Select
          label="Department"
          value={filters.department}
          onChange={(v) => set({ department: v })}
          placeholder="All departments"
          options={departments.map((d) => ({ value: d, label: d }))}
        />
        <Select
          label="Assignment"
          value={filters.assigned}
          onChange={(v) => set({ assigned: v })}
          placeholder="Anyone"
          options={ASSIGNED_OPTIONS}
        />
      </div>

      <p className="mt-3 text-xs text-slate-400">
        {totalCount == null
          ? `${shown} result${shown === 1 ? "" : "s"}`
          : `${formatTotal(shown)} matching issue${shown === 1 ? "" : "s"} · showing ${resultCount} on this page`}
        {" · all filters are applied server-side."}
      </p>
    </div>
  );
}

function formatTotal(n: number): string {
  return n.toLocaleString();
}
