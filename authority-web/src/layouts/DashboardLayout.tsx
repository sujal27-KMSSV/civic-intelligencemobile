import { useState } from "react";
import { NavLink, Outlet, useLocation, useNavigate } from "react-router-dom";
import { useAuth } from "../features/auth/AuthContext";
import { useMeta } from "../hooks/useMeta";
import { initials } from "../utils/format";
import {
  IconChart,
  IconClose,
  IconDashboard,
  IconIssues,
  IconLogout,
  IconMap,
  IconMenu,
  IconShield,
} from "../components/icons";

const NAV_ITEMS = [
  { to: "/dashboard", label: "Dashboard", icon: <IconDashboard /> },
  { to: "/issues", label: "Issues", icon: <IconIssues /> },
  { to: "/map", label: "Map", icon: <IconMap /> },
  { to: "/analytics", label: "Analytics", icon: <IconChart /> },
];

const TITLES: Record<string, string> = {
  "/dashboard": "Dashboard",
  "/issues": "Issue Management",
  "/map": "Live Issue Map",
  "/analytics": "Analytics",
};

function Brand({ compact = false }: { compact?: boolean }) {
  return (
    <div className="flex items-center gap-3">
      <span className="flex h-9 w-9 flex-none items-center justify-center rounded-xl bg-brand-500/20 text-brand-400">
        <IconShield width={20} height={20} />
      </span>
      {!compact ? (
        <div className="leading-tight">
          <p className="text-sm font-bold tracking-tight text-white">
            Civic Intelligence
          </p>
          <p className="text-[11px] text-slate-400">Authority Console</p>
        </div>
      ) : null}
    </div>
  );
}

function SidebarContent({
  onNavigate,
}: {
  onNavigate?: () => void;
}) {
  const { user, logout } = useAuth();
  const navigate = useNavigate();

  const handleLogout = () => {
    logout();
    navigate("/login", { replace: true });
  };

  return (
    <div className="flex h-full flex-col">
      <div className="px-5 py-5">
        <Brand />
      </div>
      <nav className="flex-1 space-y-1 px-3">
        {NAV_ITEMS.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            onClick={onNavigate}
            className={({ isActive }) =>
              `flex items-center gap-3 rounded-xl px-3.5 py-2.5 text-sm font-medium transition-colors ${
                isActive
                  ? "bg-brand-600 text-white shadow-sm"
                  : "text-slate-300 hover:bg-white/10 hover:text-white"
              }`
            }
          >
            {item.icon}
            {item.label}
          </NavLink>
        ))}
      </nav>
      <div className="border-t border-white/10 p-3">
        <div className="flex items-center gap-3 rounded-xl px-2 py-2">
          <span className="flex h-9 w-9 flex-none items-center justify-center rounded-full bg-brand-500 text-sm font-bold text-white">
            {initials(user ?? undefined)}
          </span>
          <div className="min-w-0 flex-1 leading-tight">
            <p className="truncate text-sm font-semibold text-white">
              {user?.first_name || user?.email}
            </p>
            <p className="truncate text-[11px] text-slate-400">
              {user?.email}
            </p>
          </div>
          <button
            type="button"
            onClick={handleLogout}
            title="Sign out"
            className="flex h-9 w-9 flex-none items-center justify-center rounded-lg text-slate-400 hover:bg-white/10 hover:text-white"
          >
            <IconLogout width={17} height={17} />
          </button>
        </div>
      </div>
    </div>
  );
}

export default function DashboardLayout() {
  const [mobileOpen, setMobileOpen] = useState(false);
  const { pathname } = useLocation();
  const { user } = useAuth();

  return (
    <div className="min-h-screen bg-slate-100">
      {/* Desktop sidebar */}
      <aside className="fixed inset-y-0 left-0 z-30 hidden w-64 bg-slate-950 lg:block">
        <SidebarContent />
      </aside>

      {/* Mobile slide-over */}
      {mobileOpen ? (
        <div className="fixed inset-0 z-50 lg:hidden">
          <div
            className="absolute inset-0 bg-slate-900/60"
            onClick={() => setMobileOpen(false)}
            aria-hidden
          />
          <aside className="absolute inset-y-0 left-0 w-72 bg-slate-950 shadow-2xl">
            <button
              type="button"
              onClick={() => setMobileOpen(false)}
              className="absolute right-3 top-4 rounded-lg p-1.5 text-slate-400 hover:bg-white/10 hover:text-white"
              aria-label="Close menu"
            >
              <IconClose width={18} height={18} />
            </button>
            <SidebarContent onNavigate={() => setMobileOpen(false)} />
          </aside>
        </div>
      ) : null}

      {/* Main column */}
      <div className="lg:pl-64">
        <header className="sticky top-0 z-20 border-b border-slate-200 bg-white/90 backdrop-blur">
          <div className="flex h-16 items-center gap-4 px-4 sm:px-6">
            <button
              type="button"
              onClick={() => setMobileOpen(true)}
              className="rounded-lg border border-slate-200 p-2 text-slate-600 hover:bg-slate-50 lg:hidden"
              aria-label="Open menu"
            >
              <IconMenu width={18} height={18} />
            </button>
            <h1 className="text-lg font-bold tracking-tight text-slate-900">
              {TITLES[pathname] ?? "Command Center"}
            </h1>
            <div className="ml-auto flex items-center gap-3">
              <span className="hidden items-center gap-2 rounded-full border border-emerald-200 bg-emerald-50 px-3 py-1 text-xs font-medium text-emerald-700 sm:flex">
                <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
                Live
              </span>
              <div className="hidden text-right leading-tight sm:block">
                <p className="text-sm font-semibold text-slate-800">
                  {user?.first_name || user?.email}
                </p>
                <p className="text-[11px] text-slate-500">
                  {user?.is_staff ? "Authority staff" : "Unknown role"}
                </p>
              </div>
              <span className="flex h-9 w-9 items-center justify-center rounded-full bg-slate-800 text-sm font-bold text-white">
                {initials(user ?? undefined)}
              </span>
            </div>
          </div>
        </header>

        <main className="mx-auto max-w-[1400px] px-4 py-6 sm:px-6">
          <DeploymentNotice />
          <Outlet />
        </main>
      </div>
    </div>
  );
}

/**
 * Surfaces a deployment capability gap instead of hiding it.
 *
 * When the backend does not publish `/api/authority/meta/`, the console falls
 * back to compiled-in enum, department and severity lists. Those values are
 * correct but they are not read from the running server, so the console says so
 * rather than presenting them as live configuration. Only a *missing* route
 * triggers this; a transient failure is left to the normal error path.
 */
function DeploymentNotice() {
  const { meta, loading } = useMeta();
  if (loading || meta) return null;
  return (
    <div className="mb-4 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3">
      <p className="text-xs font-semibold text-amber-800">
        This deployment does not publish live configuration
      </p>
      <p className="mt-1 text-[11px] leading-relaxed text-amber-700">
        The backend has no <code className="font-mono">/api/authority/meta/</code>{" "}
        endpoint, so the filter lists, department list and priority component
        catalogue below come from this console&apos;s built-in values rather than
        from the server. Issue data, priority scores and hotspots are still read
        live from the API. The staff directory is unavailable, so officer
        assignment is disabled.
      </p>
    </div>
  );
}