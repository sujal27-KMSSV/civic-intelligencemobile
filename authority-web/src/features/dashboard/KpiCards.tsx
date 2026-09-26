import { StatCard } from "../../components/StatCard";
import {
  IconCheck,
  IconClock,
  IconDuplicate,
  IconIssues,
  IconShield,
} from "../../components/icons";
import type { Stats } from "../../types";

/**
 * Headline KPIs.
 *
 * Counts are master issues (one row per physical problem) unless the card says
 * otherwise, which is why the labels avoid saying "issues" for the report-level
 * numbers. `counting_convention` comes from the backend and is rendered as the
 * footnote so the convention is never left implicit.
 */
export function KpiCards({ stats }: { stats: Stats }) {
  return (
    <>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-5">
        <StatCard
          label="Active issues"
          value={stats.active_issues}
          sub="Open physical problems, duplicates merged"
          icon={<IconIssues />}
          accent="bg-sky-100 text-sky-600"
        />
        <StatCard
          label="Critical severity"
          value={stats.critical_issues}
          sub="Active issues classified critical"
          icon={<IconCheck />}
          accent="bg-rose-100 text-rose-600"
        />
        <StatCard
          label="High priority"
          value={stats.high_priority_issues}
          sub="Priority band high or critical"
          icon={<IconClock />}
          accent="bg-amber-100 text-amber-600"
        />
        <StatCard
          label="Reports consolidated"
          value={stats.reports_consolidated}
          sub="Citizen reports merged into a master"
          icon={<IconDuplicate />}
          accent="bg-violet-100 text-violet-600"
        />
        <StatCard
          label="Unassigned"
          value={stats.unassigned_open}
          sub={`of ${stats.active_issues} active, ${stats.assigned_open} assigned`}
          icon={<IconShield />}
          accent="bg-emerald-100 text-emerald-600"
        />
      </div>
      <p className="mt-3 text-xs leading-relaxed text-slate-500">
        {stats.counting_convention}
      </p>
    </>
  );
}
