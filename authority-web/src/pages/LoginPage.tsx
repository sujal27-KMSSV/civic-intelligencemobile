import { useState, type FormEvent } from "react";
import { Navigate, useLocation, useNavigate } from "react-router-dom";
import { useAuth } from "../features/auth/AuthContext";
import { getErrorMessage } from "../api/client";
import { SpinnerInline } from "../components/Spinner";
import { IconIssues, IconMap, IconChart, IconShield } from "../components/icons";

export default function LoginPage() {
  const { user, login } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const from = (location.state as { from?: { pathname?: string } } | null)?.from;

  if (user) {
    return <Navigate to={from?.pathname ?? "/dashboard"} replace />;
  }

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    if (!email.trim() || !password) {
      setError("Please enter your email and password.");
      return;
    }
    setLoading(true);
    try {
      await login(email.trim(), password);
      navigate(from?.pathname ?? "/dashboard", { replace: true });
    } catch (err) {
      setError(getErrorMessage(err));
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="flex min-h-screen bg-slate-50">
      {/* Brand panel */}
      <div className="relative hidden w-1/2 flex-col justify-between overflow-hidden bg-slate-950 p-10 text-white lg:flex">
        <div className="absolute -left-24 -top-24 h-96 w-96 rounded-full bg-brand-600/20 blur-3xl" />
        <div className="absolute -bottom-32 -right-24 h-96 w-96 rounded-full bg-sky-700/20 blur-3xl" />
        <div className="relative z-10 flex items-center gap-3">
          <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-500/20 text-brand-400">
            <IconShield width={22} height={22} />
          </span>
          <div>
            <p className="text-lg font-bold tracking-tight">Civic Intelligence</p>
            <p className="text-xs text-slate-400">Authority Command Center</p>
          </div>
        </div>

        <div className="relative z-10">
          <h1 className="max-w-md text-4xl font-bold leading-tight tracking-tight">
            Every citizen report, routed, prioritized and resolved.
          </h1>
          <p className="mt-4 max-w-md text-sm leading-relaxed text-slate-400">
            A live command center over the civic issue pipeline — AI-assisted
            classification, duplicate clustering, department routing and
            resolution verification.
          </p>
          <div className="mt-8 grid max-w-md grid-cols-3 gap-3">
            {[
              { icon: <IconIssues />, label: "Live issues" },
              { icon: <IconMap />, label: "Geo command" },
              { icon: <IconChart />, label: "Analytics" },
            ].map((f) => (
              <div
                key={f.label}
                className="rounded-xl border border-white/10 bg-white/5 p-3"
              >
                <div className="text-brand-400">{f.icon}</div>
                <p className="mt-2 text-xs font-medium text-slate-300">{f.label}</p>
              </div>
            ))}
          </div>
        </div>

        <p className="relative z-10 text-xs text-slate-500">
          Authorized staff only · DRF token authentication
        </p>
      </div>

      {/* Form panel */}
      <div className="flex w-full items-center justify-center px-6 py-12 lg:w-1/2">
        <div className="w-full max-w-sm">
          <div className="mb-8 flex items-center gap-3 lg:hidden">
            <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-600 text-white">
              <IconShield width={22} height={22} />
            </span>
            <div>
              <p className="text-lg font-bold tracking-tight text-slate-900">
                Civic Intelligence
              </p>
              <p className="text-xs text-slate-500">Authority Command Center</p>
            </div>
          </div>

          <h2 className="text-2xl font-bold tracking-tight text-slate-900">
            Authority sign in
          </h2>
          <p className="mt-1 text-sm text-slate-500">
            Use your staff account to access the command center.
          </p>

          <form onSubmit={handleSubmit} className="mt-8 space-y-4">
            <div>
              <label htmlFor="email" className="mb-1.5 block text-sm font-medium text-slate-700">
                Email address
              </label>
              <input
                id="email"
                type="email"
                autoComplete="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="authority@civic.gov"
                className="w-full rounded-xl border border-slate-300 bg-white px-3.5 py-2.5 text-sm text-slate-900 placeholder:text-slate-400 focus:border-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-600/20"
              />
            </div>
            <div>
              <label htmlFor="password" className="mb-1.5 block text-sm font-medium text-slate-700">
                Password
              </label>
              <input
                id="password"
                type="password"
                autoComplete="current-password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••••"
                className="w-full rounded-xl border border-slate-300 bg-white px-3.5 py-2.5 text-sm text-slate-900 placeholder:text-slate-400 focus:border-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-600/20"
              />
            </div>

            {error ? (
              <div className="rounded-xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700">
                {error}
              </div>
            ) : null}

            <button
              type="submit"
              disabled={loading}
              className="flex w-full items-center justify-center gap-2 rounded-xl bg-brand-600 px-4 py-2.5 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-brand-700 disabled:opacity-60"
            >
              {loading ? <SpinnerInline /> : null}
              {loading ? "Signing in…" : "Sign in"}
            </button>
          </form>

          <p className="mt-6 text-center text-xs text-slate-400">
            The mobile app remains the citizen channel. This console is staff-only.
          </p>
        </div>
      </div>
    </div>
  );
}