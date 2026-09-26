import type { ReactNode } from "react";
import { formatCount } from "../utils/format";

export function StatCard({
  label,
  value,
  sub,
  icon,
  accent = "bg-brand-50 text-brand-600",
}: {
  label: string;
  value: number | string;
  sub?: ReactNode;
  icon?: ReactNode;
  accent?: string;
}) {
  return (
    <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
      <div className="flex items-start justify-between">
        <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">
          {label}
        </p>
        {icon ? (
          <span className={`flex h-9 w-9 items-center justify-center rounded-xl ${accent}`}>
            {icon}
          </span>
        ) : null}
      </div>
      <p className="mt-2 text-3xl font-bold tracking-tight text-slate-900">
        {typeof value === "number" ? formatCount(value) : value}
      </p>
      {sub ? <div className="mt-1 text-xs text-slate-500">{sub}</div> : null}
    </div>
  );
}