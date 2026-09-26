import { useState } from "react";
import { fetchIssues } from "../api/issues";
import { Pagination } from "../components/Pagination";
import { useAsync, useDebouncedValue } from "../hooks/useAsync";
import { useMeta } from "../hooks/useMeta";
import type {
  IssueCategory,
  IssueOrdering,
  IssueScope,
  IssueSeverity,
  IssueStatus,
  PriorityClass,
} from "../types";
import {
  EMPTY_FILTERS,
  IssueFilters,
  type IssueFiltersState,
} from "../features/issues/IssueFilters";
import { IssueTable } from "../features/issues/IssueTable";
import { SortSelect } from "../features/issues/SortSelect";

const PAGE_SIZE = 10;

const ORDERINGS: IssueOrdering[] = [
  "priority",
  "newest",
  "oldest",
  "cluster",
  "severity",
  "reports",
  "status",
];

/**
 * The operations queue.
 *
 * Filtering, searching, sorting and pagination all happen server-side: the
 * backend rejects unknown filter values outright, so the client cannot drift out
 * of sync with the contract. The list defaults to master issues (one row per
 * physical problem), which is the unit an authority actually acts on.
 */
export default function IssuesPage() {
  const [filters, setFilters] = useState<IssueFiltersState>(EMPTY_FILTERS);
  const [ordering, setOrdering] = useState<IssueOrdering>("priority");
  const [page, setPage] = useState(1);

  const { meta } = useMeta();
  // Debounced so typing in the search box does not fire a request per keystroke.
  const debouncedSearch = useDebouncedValue(filters.search, 350);

  const query = useAsync(
    () =>
      fetchIssues({
        scope: (filters.scope || "masters") as IssueScope,
        status: (filters.status || undefined) as IssueStatus | undefined,
        severity: (filters.severity || undefined) as IssueSeverity | undefined,
        priority_class: (filters.priorityClass ||
          undefined) as PriorityClass | undefined,
        category: (filters.category || undefined) as IssueCategory | undefined,
        department: filters.department || undefined,
        assigned: (filters.assigned || undefined) as
          | "assigned"
          | "unassigned"
          | undefined,
        q: debouncedSearch.trim() || undefined,
        includeResolved: true,
        ordering,
        page,
        pageSize: PAGE_SIZE,
      }),
    [
      filters.scope,
      filters.status,
      filters.severity,
      filters.priorityClass,
      filters.category,
      filters.department,
      filters.assigned,
      debouncedSearch,
      ordering,
      page,
    ],
  );

  const handleFiltersChange = (next: IssueFiltersState) => {
    setFilters(next);
    // Any filter change invalidates the current page offset.
    setPage(1);
  };

  const issues = query.data?.issues ?? [];
  const total = query.data?.page?.count;
  const pageCount = query.data?.page?.total_pages ?? 1;
  const safePage = Math.min(page, pageCount);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-xl font-bold tracking-tight text-slate-900">
            Issue management
          </h2>
          <p className="mt-1 text-sm text-slate-500">
            Full pipeline view — search, filter and dispatch every citizen
            report.
          </p>
        </div>
        <SortSelect
          value={ordering}
          onChange={(v) => {
            setOrdering(v);
            setPage(1);
          }}
          options={ORDERINGS}
        />
      </div>

      <IssueFilters
        filters={filters}
        onChange={handleFiltersChange}
        resultCount={issues.length}
        totalCount={total}
        meta={meta}
      />

      <div className="rounded-2xl border border-slate-200 bg-white shadow-sm">
        <IssueTable
          issues={issues}
          loading={query.loading}
          error={query.error}
          onRetry={query.reload}
        />
        {total != null ? (
          <Pagination
            page={safePage}
            pageSize={PAGE_SIZE}
            total={total}
            onPageChange={setPage}
          />
        ) : null}
      </div>
    </div>
  );
}
