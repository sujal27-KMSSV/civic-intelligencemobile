import { Link } from "react-router-dom";
import { SeverityBadge, StatusBadge } from "../../components/Badges";
import { IconDuplicate, IconLink } from "../../components/icons";
import { formatCount, formatDateShort } from "../../utils/format";
import { categoryLabel } from "../../utils/media";
import type { ClusterMember, IssueDetail } from "../../types";

/**
 * Consolidates the cluster view around the backend's master/supporting model.
 *
 * One physical problem = one **master** issue plus N **supporting** reports.
 * `is_master`/`master_id`/`cluster_size` come from the API (derived server-side
 * from the real `duplicate_of` graph), so this panel never counts or decides
 * anything itself — it only renders what the backend reported.
 */
export function DuplicateIntelligence({ issue }: { issue: IssueDetail }) {
  const cluster: ClusterMember[] = issue.cluster ?? [];
  // `cluster_size` is the backend's own count of citizen reports; trust it over
  // the length of `cluster`, which the detail endpoint populates fully but which
  // may be empty on a list-sourced payload.
  const total = issue.cluster_size > 0 ? issue.cluster_size : cluster.length;
  const supporting = Math.max(0, total - 1);
  const hasCluster = supporting > 0 || cluster.length > 1;

  if (!hasCluster) {
    return (
      <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
        <PanelHeader />
        <p className="mt-2 rounded-xl bg-slate-50 px-4 py-3 text-sm text-slate-500">
          No other report was consolidated into this one. It stands alone as a
          unique physical problem.
        </p>
      </div>
    );
  }

  const masterId = issue.master_id;
  const master = issue.master;
  const members = cluster.filter((m) => m.id !== masterId);

  return (
    <div className="overflow-hidden rounded-2xl border border-amber-200 bg-white shadow-sm">
      <div className="border-b border-amber-100 bg-amber-50/70 px-5 py-4">
        <div className="flex items-center gap-2 text-sm font-semibold text-amber-800">
          <span>
            <IconDuplicate width={16} height={16} />
          </span>
          Consolidated cluster
        </div>
        <div className="mt-3 flex items-end gap-2">
          <span className="text-4xl font-bold tracking-tight text-amber-700">
            {formatCount(total)}
          </span>
          <span className="pb-1 text-sm font-medium text-amber-800">
            citizen report{total === 1 ? "" : "s"} for one physical problem
          </span>
        </div>
        <p className="mt-1 text-xs text-amber-700/80">
          1 master + {formatCount(supporting)} supporting report
          {supporting === 1 ? "" : "s"}
        </p>
      </div>

      <div className="px-5 py-4">
        {!issue.is_master ? (
          <p className="mb-3 rounded-lg bg-amber-50 px-3 py-2 text-xs text-amber-800">
            You are viewing a supporting report. It is grouped under master issue{" "}
            <Link
              to={`/issues/${masterId}`}
              className="font-semibold underline underline-offset-2"
            >
              #{masterId}
            </Link>
            , which is the row an authority acts on.
          </p>
        ) : (
          <p className="mb-3 rounded-lg bg-amber-50 px-3 py-2 text-xs text-amber-800">
            This is the master issue for the cluster. Dispatch and resolution are
            recorded here; the {formatCount(supporting)} supporting report
            {supporting === 1 ? "" : "s"} follow the master&rsquo;s status.
          </p>
        )}

        <SignalBreakdown issue={issue} />

        <p className="mt-4 text-[11px] font-bold uppercase tracking-wider text-slate-500">
          Cluster members
        </p>
        <ul className="mt-2 space-y-2">
          <MasterRow master={master} isCurrent={issue.id === masterId} />
          {members.map((m) => (
            <MemberRow key={m.id} member={m} isCurrent={m.id === issue.id} />
          ))}
        </ul>
      </div>
    </div>
  );
}

function PanelHeader() {
  return (
    <div className="flex items-center gap-2 text-sm font-semibold text-slate-800">
      <span className="text-slate-400">
        <IconDuplicate width={16} height={16} />
      </span>
      Consolidated cluster
    </div>
  );
}

function MasterRow({
  master,
  isCurrent,
}: {
  master: IssueDetail["master"];
  isCurrent: boolean;
}) {
  return (
    <li>
      <Link
        to={`/issues/${master.id}`}
        className="flex items-center gap-3 rounded-xl border border-amber-200 bg-amber-50/50 px-3 py-2 transition-colors hover:border-amber-300"
      >
        <span className="flex h-7 w-7 flex-none items-center justify-center rounded-full bg-amber-500 text-[10px] font-bold text-white">
          M
        </span>
        <div className="min-w-0 flex-1">
          <p className="text-xs font-semibold text-slate-800">
            #{master.id} · {categoryLabel(master.category)}{" "}
            {isCurrent ? (
              <span className="font-normal text-brand-600">(this issue)</span>
            ) : (
              <span className="font-normal text-amber-600">(master)</span>
            )}
          </p>
          <p className="text-[11px] text-slate-400">
            {formatDateShort(master.created_at)} · {master.department}
            {master.assigned_to_name ? ` · ${master.assigned_to_name}` : ""}
          </p>
        </div>
        <SeverityBadge severity={master.severity} />
        <StatusBadge status={master.status} />
        <IconLink width={14} height={14} className="text-slate-300" />
      </Link>
    </li>
  );
}

function MemberRow({
  member,
  isCurrent,
}: {
  member: ClusterMember;
  isCurrent: boolean;
}) {
  return (
    <li>
      <Link
        to={`/issues/${member.id}`}
        className="flex items-center gap-3 rounded-xl border border-slate-100 px-3 py-2 transition-colors hover:border-brand-200 hover:bg-brand-50/40"
      >
        <span className="flex h-7 w-7 flex-none items-center justify-center rounded-full bg-slate-100 text-[10px] font-bold text-slate-500">
          S
        </span>
        <div className="min-w-0 flex-1">
          <p className="text-xs font-semibold text-slate-800">
            #{member.id} · {categoryLabel(member.category)}{" "}
            {isCurrent ? (
              <span className="font-normal text-brand-600">(this report)</span>
            ) : null}
          </p>
          <p className="text-[11px] text-slate-400">
            {formatDateShort(member.created_at)}
            {member.similarity_to_master != null
              ? ` · ${Math.round(member.similarity_to_master * 100)}% image similarity to master`
              : ""}
          </p>
        </div>
        <SeverityBadge severity={member.severity} />
        <StatusBadge status={member.status} />
        <IconLink width={14} height={14} className="text-slate-300" />
      </Link>
    </li>
  );
}

/**
 * Why the reports were consolidated.
 *
 * The five signals and their weights are computed server-side
 * (`issues.civic.SIGNAL_WEIGHTS`); this only displays the values the backend
 * recorded. When no breakdown is present the panel says so plainly — the
 * deployment either does not publish per-signal values, or the report predates
 * duplicate detection. Neither is guessed at.
 */
function SignalBreakdown({ issue }: { issue: IssueDetail }) {
  const signals = issue.duplicate_signals;
  if (!signals) {
    return (
      <p className="rounded-lg bg-slate-50 px-3 py-2 text-xs text-slate-500">
        No per-signal breakdown was recorded for this report. The backend may not
        publish one, or the report may predate duplicate detection. The
        consolidation result itself is shown above either way.
      </p>
    );
  }

  const entries = Object.entries(signals.signals ?? {});
  if (entries.length === 0) return null;

  // `used_weights` is what the engine actually applied for this report (it can
  // differ from the static weights when a signal was unavailable, e.g. the
  // image was missing). Prefer it, fall back to the static weights.
  const weights = signals.used_weights ?? signals.weights ?? {};

  return (
    <div className="rounded-xl border border-slate-200 bg-slate-50/70 p-3">
      <p className="text-[11px] font-bold uppercase tracking-wider text-slate-500">
        Why these were consolidated
      </p>
      <ul className="mt-2 space-y-1.5">
        {entries.map(([name, value]) => {
          const weight = weights[name] ?? 0;
          const contribution = value * weight;
          return (
            <li key={name} className="flex items-center gap-2 text-xs">
              <span className="w-40 flex-none truncate text-slate-600">
                {humanise(name)}
              </span>
              <span
                className="h-1.5 flex-none rounded-full bg-brand-500"
                style={{
                  width: `${Math.max(4, Math.min(100, contribution * 100))}%`,
                }}
              />
              <span className="ml-auto flex-none tabular-nums text-slate-500">
                {value.toFixed(2)} × {weight.toFixed(2)} ={" "}
                <span className="font-semibold text-slate-700">
                  {contribution.toFixed(3)}
                </span>
              </span>
            </li>
          );
        })}
      </ul>
      <p className="mt-2 text-[11px] text-slate-400">
        Overall duplicate similarity{" "}
        <span className="font-semibold text-slate-600">
          {signals.similarity_score != null
            ? signals.similarity_score.toFixed(3)
            : "n/a"}
        </span>
        {signals.matched_report_id ? (
          <> · matched against report #{signals.matched_report_id}</>
        ) : null}
        . Consolidation needs the weighted sum to clear the backend threshold; no
        single signal decides it.
      </p>
    </div>
  );
}

function humanise(name: string): string {
  return name
    .replace(/_/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());
}
