import { fetchStats } from "../api/stats";
import { CardSkeleton } from "../components/Skeleton";
import { ErrorState } from "../components/States";
import { useAsync } from "../hooks/useAsync";
import {
  DepartmentDistributionChart,
  SeverityDistributionChart,
  StatusDistributionChart,
} from "../features/dashboard/charts";
import { IconChart, IconClock, IconShield } from "../components/icons";

export default function AnalyticsPage() {
  const stats = useAsync(() => fetchStats(), []);

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-xl font-bold tracking-tight text-slate-900">
          Analytics
        </h2>
        <p className="mt-1 text-sm text-slate-500">
          Every chart is rendered from live aggregate backend statistics — no
          fabricated figures.
        </p>
      </div>

      {stats.error ? (
        <ErrorState message={stats.error} onRetry={stats.reload} />
      ) : !stats.data ? (
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <CardSkeleton key={i} />
          ))}
        </div>
      ) : (
        <>
          <div className="grid grid-cols-1 gap-4 xl:grid-cols-3">
            <StatusDistributionChart stats={stats.data} />
            <SeverityDistributionChart stats={stats.data} />
            <DepartmentDistributionChart stats={stats.data} />
          </div>

          <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
            <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
              <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-slate-100 text-slate-600">
                <IconShield width={18} height={18} />
              </span>
              <h3 className="mt-3 text-sm font-semibold text-slate-800">
                Analysis engine
              </h3>
              <p className="mt-1 text-sm leading-relaxed text-slate-500">
                Severity, duplicate clustering and department routing run through
                the deterministic rule-based engine. Scores are auditable from
                their underlying rules.
              </p>
            </div>
            <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
              <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-amber-100 text-amber-600">
                <IconClock width={18} height={18} />
              </span>
              <h3 className="mt-3 text-sm font-semibold text-slate-800">
                Time-series trending
              </h3>
              <p className="mt-1 text-sm leading-relaxed text-slate-500">
                Marked as a future capability. The current statistics endpoint
                serves snapshot aggregates only, so a trending chart would be
                fabricated — we do not render one.
              </p>
            </div>
            <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
              <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-emerald-100 text-emerald-600">
                <IconChart width={18} height={18} />
              </span>
              <h3 className="mt-3 text-sm font-semibold text-slate-800">
                Live pipelines
              </h3>
              <p className="mt-1 text-sm leading-relaxed text-slate-500">
                Open issues flow from report → verification → assignment → in
                progress → resolution, with rejection as a supported branch at
                every stage.
              </p>
            </div>
          </div>
        </>
      )}
    </div>
  );
}