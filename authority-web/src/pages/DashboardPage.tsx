import { Link } from "react-router-dom";
import { fetchIssues } from "../api/issues";
import { fetchStats } from "../api/stats";
import { CardSkeleton } from "../components/Skeleton";
import { ErrorState } from "../components/States";
import { formatDateShort } from "../utils/format";
import {
  DepartmentDistributionChart,
  SeverityDistributionChart,
  StatusDistributionChart,
} from "../features/dashboard/charts";
import { KpiCards } from "../features/dashboard/KpiCards";
import { RecentReports } from "../features/dashboard/RecentReports";
import { useAsync } from "../hooks/useAsync";

export default function DashboardPage() {
  const statsQuery = useAsync(() => fetchStats(), []);
  // The most urgent open work, which is what a dashboard should surface. The
  // backend already defaults to priority-descending, so no client sort.
  const issuesQuery = useAsync(
    () =>
      fetchIssues({ scope: "masters", ordering: "priority" }).then(
        (r) => r.issues,
      ),
    [],
  );

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-xl font-bold tracking-tight text-slate-900">
          Command overview
        </h2>
        <p className="mt-1 text-sm text-slate-500">
          Live aggregate data from the civic intelligence backend ·{" "}
          {formatDateShort(new Date().toISOString())}
        </p>
      </div>

      {statsQuery.error ? (
        <ErrorState
          message={statsQuery.error}
          onRetry={statsQuery.reload}
        />
      ) : !statsQuery.data ? (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-5">
          {Array.from({ length: 5 }).map((_, i) => (
            <CardSkeleton key={i} />
          ))}
        </div>
      ) : (
        <>
          <KpiCards stats={statsQuery.data} />

          <div className="grid grid-cols-1 gap-4 xl:grid-cols-3">
            <StatusDistributionChart
              stats={statsQuery.data}
            />
            <SeverityDistributionChart
              stats={statsQuery.data}
            />
            <DepartmentDistributionChart
              stats={statsQuery.data}
            />
          </div>
        </>
      )}

      <RecentReports
        issues={issuesQuery.data}
        loading={issuesQuery.loading}
      />

      <div className="flex items-center justify-end gap-3 text-xs text-slate-400">
        <span>Status and severity distribution reflect recorded issue counts.</span>
        <Link to="/analytics" className="font-semibold text-brand-600 hover:text-brand-700">
          Open analytics →
        </Link>
      </div>
    </div>
  );
}