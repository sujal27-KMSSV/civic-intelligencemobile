import { Link } from "react-router-dom";
import type { Issue } from "../../types";
import { SeverityBadge, StatusBadge } from "../../components/Badges";
import { Skeleton } from "../../components/Skeleton";
import { EmptyState } from "../../components/States";
import { IconIssues, IconLink } from "../../components/icons";
import { categoryLabel, resolveMediaUrl } from "../../utils/media";
import { formatCount, relativeTime } from "../../utils/format";

export function RecentReports({
  issues,
  loading,
}: {
  issues: Issue[] | null;
  loading: boolean;
}) {
  return (
    <div className="rounded-2xl border border-slate-200 bg-white shadow-sm">
      <div className="flex items-center justify-between border-b border-slate-100 px-5 py-4">
        <div>
          <h3 className="text-sm font-semibold text-slate-800">Recent reports</h3>
          <p className="text-xs text-slate-500">
            Latest citizen submissions, newest first
          </p>
        </div>
        <Link
          to="/issues"
          className="flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-semibold text-brand-600 hover:bg-brand-50"
        >
          All issues
          <IconLink width={13} height={13} />
        </Link>
      </div>

      {loading ? (
        <div className="space-y-3 p-5">
          {Array.from({ length: 5 }).map((_, i) => (
            <Skeleton key={i} className="h-14 w-full" />
          ))}
        </div>
      ) : !issues || issues.length === 0 ? (
        <div className="p-5">
          <EmptyState
            icon={<IconIssues />}
            title="No reports yet"
            description="When citizens submit reports they will appear here."
          />
        </div>
      ) : (
        <ul className="divide-y divide-slate-100">
          {issues.slice(0, 6).map((issue) => (
            <li key={issue.id}>
              <Link
                to={`/issues/${issue.id}`}
                className="flex items-center gap-4 px-5 py-3 transition-colors hover:bg-slate-50"
              >
                <div className="h-12 w-12 flex-none overflow-hidden rounded-xl border border-slate-200 bg-slate-100">
                  {issue.image_url ? (
                    <img
                      src={resolveMediaUrl(issue.image_url)}
                      alt=""
                      className="h-full w-full object-cover"
                      loading="lazy"
                    />
                  ) : null}
                </div>
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-semibold text-slate-500">
                      #{issue.id}
                    </span>
                    <span className="truncate text-sm font-medium text-slate-800">
                      {categoryLabel(issue.category)}
                    </span>
                    {issue.duplicate_count > 0 ? (
                      <span className="rounded-full bg-amber-50 px-2 py-0.5 text-[11px] font-medium text-amber-700">
                        {formatCount(issue.duplicate_count)} reports
                      </span>
                    ) : null}
                  </div>
                  <p className="mt-0.5 truncate text-xs text-slate-500">
                    {issue.address || "No address"}
                  </p>
                </div>
                <div className="hidden flex-none items-center gap-2 sm:flex">
                  <SeverityBadge severity={issue.severity} />
                  <StatusBadge status={issue.status} />
                </div>
                <span className="flex-none text-xs text-slate-400">
                  {relativeTime(issue.created_at)}
                </span>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}