import { Link } from "react-router-dom";

export default function NotFoundPage() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-950">
      <div className="text-center">
        <p className="text-6xl font-bold text-white">404</p>
        <p className="mt-2 text-sm text-slate-400">
          This page is not part of the authority console.
        </p>
        <Link
          to="/dashboard"
          className="mt-6 inline-flex rounded-xl bg-brand-600 px-5 py-2.5 text-sm font-semibold text-white hover:bg-brand-700"
        >
          Back to dashboard
        </Link>
      </div>
    </div>
  );
}