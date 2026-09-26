import { useNavigate } from "react-router-dom";
import type { Issue } from "../../types";
import {
  PriorityBadge,
  SeverityBadge,
  StatusBadge,
} from "../../components/Badges";
import { TableSkeleton } from "../../components/Skeleton";
import { EmptyState, ErrorState } from "../../components/States";
import { IconDuplicate, IconIssues } from "../../components/icons";
import { categoryLabel } from "../../utils/media";
import { formatCount, formatDate } from "../../utils/format";

export function IssueTable({
  issues,
  loading,
  error,
  onRetry,
}: {
  issues: Issue[];
  loading: boolean;
  error: string | null;
  onRetry: () => void;
}) {
  const navigate = useNavigate();

  if (error) {
    return (
      <div className="p-5">
        <ErrorState message={error} onRetry={onRetry} />
      </div>
    );
  }

  if (loading) {
    return <TableSkeleton rows={8} />;
  }

  if (issues.length === 0) {
    return (
      <div className="p-5">
        <EmptyState
          icon={<IconIssues />}
          title="No issues match these filters"
          description="Try widening the filters, or check back once new citizen reports arrive."
        />
      </div>
    );
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[980px] text-left">
        <thead>
          <tr className="border-b border-slate-200 text-[11px] font-semibold uppercase tracking-wide text-slate-500">
            <th className="px-5 py-3">ID</th>
            <th className="px-4 py-3">Category</th>
            <th className="px-4 py-3">Priority</th>
            <th className="px-4 py-3">Severity</th>
            <th className="px-4 py-3">Status</th>
            <th className="px-4 py-3">Department</th>
            <th className="px-4 py-3">Officer</th>
            <th className="px-4 py-3">Reports</th>
            <th className="px-4 py-3">Location</th>
            <th className="px-4 py-3">Created</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-slate-100">
          {issues.map((issue) => (
            <tr
              key={issue.id}
              onClick={() => navigate(`/issues/${issue.id}`)}
              className="cursor-pointer transition-colors hover:bg-slate-50"
            >
              <td className="px-5 py-3 font-semibold text-brand-700">
                #{issue.id}
              </td>
              <td className="px-4 py-3">
                <span className="text-sm font-medium text-slate-800">
                  {categoryLabel(issue.category)}
                </span>
                {!issue.is_master ? (
                  <span className="ml-1.5 text-[11px] font-medium text-slate-400">
                    supporting
                  </span>
                ) : null}
              </td>
              <td className="px-4 py-3">
                <PriorityBadge
                  score={issue.priority}
                  priorityClass={issue.priority_class}
                />
              </td>
              <td className="px-4 py-3">
                <SeverityBadge severity={issue.severity} />
              </td>
              <td className="px-4 py-3">
                <StatusBadge status={issue.status} />
              </td>
              <td className="px-4 py-3">
                <span className="text-sm text-slate-600">{issue.department}</span>
              </td>
              <td className="px-4 py-3">
                {issue.assigned_to_name ? (
                  <span className="text-sm text-slate-600">
                    {issue.assigned_to_name}
                  </span>
                ) : (
                  <span className="text-sm text-amber-600">Unassigned</span>
                )}
              </td>
              <td className="px-4 py-3">
                {/* cluster_size counts citizen reports, so a master with 0
                    supporting reports legitimately shows 1. */}
                {issue.cluster_size > 1 ? (
                  <span
                    className="inline-flex items-center gap-1.5 rounded-full bg-amber-50 px-2.5 py-0.5 text-xs font-semibold text-amber-700"
                    title={`${issue.cluster_size} citizen reports consolidated into this issue`}
                  >
                    <IconDuplicate width={13} height={13} />
                    {formatCount(issue.cluster_size)}
                  </span>
                ) : (
                  <span className="text-sm text-slate-400">1</span>
                )}
              </td>
              <td className="max-w-[200px] px-4 py-3">
                <span className="block truncate text-sm text-slate-500">
                  {issue.address ||
                    `${issue.latitude?.toFixed(4)}, ${issue.longitude?.toFixed(4)}`}
                </span>
              </td>
              <td className="whitespace-nowrap px-4 py-3 text-sm text-slate-500">
                {formatDate(issue.created_at)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
