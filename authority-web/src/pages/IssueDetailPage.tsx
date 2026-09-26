import { Link, useParams } from "react-router-dom";
import { fetchIssue } from "../api/issues";
import {
  PriorityBadge,
  SeverityBadge,
  StatusBadge,
} from "../components/Badges";
import { Skeleton } from "../components/Skeleton";
import { ErrorState } from "../components/States";
import { IconChevronLeft } from "../components/icons";
import { useAsync } from "../hooks/useAsync";
import { useMeta } from "../hooks/useMeta";
import { AIIntelligence } from "../features/issues/AIIntelligence";
import { DuplicateIntelligence } from "../features/issues/DuplicateIntelligence";
import { IssueMeta } from "../features/issues/IssueMeta";
import { Lifecycle } from "../features/issues/Lifecycle";
import { PriorityExplanation } from "../features/issues/PriorityExplanation";
import { ResolutionPanel } from "../features/issues/ResolutionPanel";
import { categoryLabel, resolveMediaUrl } from "../utils/media";
import { formatDateShort, formatCount } from "../utils/format";

export default function IssueDetailPage() {
  const { id } = useParams<{ id: string }>();
  const query = useAsync(() => fetchIssue(id as string), [id]);
  // The priority engine's live component catalogue, for the "how is this
  // computed?" disclosure. Optional: the panel still renders without it.
  const { meta } = useMeta();

  if (query.loading) {
    return (
      <div className="space-y-4">
        <Skeleton className="h-8 w-40" />
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <div className="space-y-4 lg:col-span-2">
            <Skeleton className="h-40 w-full" />
            <Skeleton className="h-56 w-full" />
            <Skeleton className="h-40 w-full" />
          </div>
          <div className="space-y-4">
            <Skeleton className="h-72 w-full" />
            <Skeleton className="h-40 w-full" />
          </div>
        </div>
      </div>
    );
  }

  if (query.error) {
    return (
      <ErrorState
        title="Issue unavailable"
        message={query.error}
        onRetry={query.reload}
      />
    );
  }

  const issue = query.data;
  if (!issue) return null;

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2">
        <Link
          to="/issues"
          className="flex h-9 w-9 items-center justify-center rounded-xl border border-slate-200 bg-white text-slate-600 shadow-sm hover:bg-slate-50"
          aria-label="Back to issues"
        >
          <IconChevronLeft width={16} height={16} />
        </Link>
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <h2 className="text-xl font-bold tracking-tight text-slate-900">
              Issue #{issue.id}
            </h2>
            <PriorityBadge
              score={issue.priority}
              priorityClass={issue.priority_class}
            />
            <SeverityBadge severity={issue.severity} />
            <StatusBadge status={issue.status} />
            {issue.cluster_size > 1 ? (
              <span
                className="rounded-full bg-amber-50 px-2.5 py-0.5 text-xs font-semibold text-amber-700"
                title={
                  issue.is_master
                    ? "This is the master issue for the cluster"
                    : `Supporting report under master #${issue.master_id}`
                }
              >
                {formatCount(issue.cluster_size)} reports
                {issue.is_master ? "" : ` · under #${issue.master_id}`}
              </span>
            ) : null}
          </div>
          <p className="mt-0.5 text-sm text-slate-500">
            {categoryLabel(issue.category)} · {issue.department} · reported{" "}
            {formatDateShort(issue.created_at)}
            {issue.assigned_to_name
              ? ` · assigned to ${issue.assigned_to_name}`
              : ""}
          </p>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <div className="space-y-4 lg:col-span-2">
          <PriorityExplanation
            issue={issue}
            engine={meta?.capabilities?.priority_engine ?? null}
          />
          <DuplicateIntelligence issue={issue} />
          <AIIntelligence issue={issue} />
          <Lifecycle
            status={issue.status}
            issueId={issue.id}
            allowedTransitions={issue.allowed_transitions}
            onChanged={query.reload}
          />
          <ResolutionPanel issue={issue} onChanged={query.reload} />
        </div>

        <div className="space-y-4">
          <div className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm">
            <div className="border-b border-slate-100 px-5 py-3">
              <h3 className="text-sm font-semibold text-slate-800">
                Original report image
              </h3>
            </div>
            <div className="p-5">
              {issue.image_url ? (
                <img
                  src={resolveMediaUrl(issue.image_url)}
                  alt={`Issue ${issue.id}`}
                  className="max-h-80 w-full rounded-xl border border-slate-100 object-cover"
                />
              ) : (
                <div className="flex h-40 items-center justify-center rounded-xl bg-slate-100 text-sm text-slate-400">
                  No image recorded
                </div>
              )}
            </div>
          </div>

          <IssueMeta
            issue={issue}
            officers={meta?.officers ?? []}
            onChanged={query.reload}
          />
        </div>
      </div>
    </div>
  );
}
