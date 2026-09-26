import type { ReactNode } from "react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { STATUS_LABELS, type Stats } from "../../types";
import { severityColor } from "../../utils/media";

export function ChartCard({
  title,
  subtitle,
  children,
  className = "",
}: {
  title: string;
  subtitle?: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={`rounded-2xl border border-slate-200 bg-white p-5 shadow-sm ${className}`}
    >
      <h3 className="text-sm font-semibold text-slate-800">{title}</h3>
      {subtitle ? <p className="mt-0.5 text-xs text-slate-500">{subtitle}</p> : null}
      <div className="mt-4 h-64">{children}</div>
    </div>
  );
}

const STATUS_COLORS: Record<string, string> = {
  reported: "#94a3b8",
  verified: "#0ea5e9",
  assigned: "#6366f1",
  in_progress: "#3b82f6",
  resolved: "#10b981",
  rejected: "#737373",
};

function tooltipStyle() {
  return {
    borderRadius: 12,
    border: "1px solid #e2e8f0",
    boxShadow: "0 8px 24px rgba(15,23,42,0.08)",
    fontSize: 12,
  } as const;
}

export function StatusDistributionChart({ stats }: { stats: Stats }) {
  // The distribution is keyed by the raw enum value ("reported"), so the lookup
  // must use that key and the label is applied only for display.
  const data = (Object.keys(STATUS_LABELS) as (keyof typeof STATUS_LABELS)[])
    .map((status) => ({
      key: status as string,
      name: STATUS_LABELS[status] as string,
      value: stats.by_status[status as string] ?? 0,
    }))
    .filter((d) => d.value > 0);

  if (data.length === 0) {
    return (
      <div className="flex h-full items-center justify-center text-sm text-slate-400">
        No status data yet
      </div>
    );
  }

  return (
    <ResponsiveContainer width="100%" height="100%">
      <BarChart data={data} margin={{ top: 8, right: 8, left: -16, bottom: 0 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" vertical={false} />
        <XAxis dataKey="name" tick={{ fontSize: 11, fill: "#64748b" }} interval={0} />
        <YAxis allowDecimals={false} tick={{ fontSize: 11, fill: "#64748b" }} />
        <Tooltip
          cursor={{ fill: "#f8fafc" }}
          contentStyle={tooltipStyle()}
        />
        <Bar dataKey="value" radius={[6, 6, 0, 0]}>
          {data.map((entry) => (
            <Cell key={entry.key} fill={STATUS_COLORS[entry.key] ?? "#10b981"} />
          ))}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  );
}

const SEVERITY_ORDER = ["critical", "high", "medium", "low"] as const;

export function SeverityDistributionChart({ stats }: { stats: Stats }) {
  // As above: index by the raw severity key, label for display.
  const data = SEVERITY_ORDER.map((key) => ({
    key,
    name: key.charAt(0).toUpperCase() + key.slice(1),
    value: stats.by_severity[key] ?? 0,
  })).filter((d) => d.value > 0);

  if (data.length === 0) {
    return (
      <div className="flex h-full items-center justify-center text-sm text-slate-400">
        No severity data yet
      </div>
    );
  }

  return (
    <ResponsiveContainer width="100%" height="100%">
      <PieChart>
        <Pie
          data={data}
          dataKey="value"
          nameKey="name"
          cx="50%"
          cy="50%"
          innerRadius={54}
          outerRadius={86}
          paddingAngle={2}
          label={(props) => {
            const { name, value, percent } = props as {
              name: string;
              value: number;
              percent: number;
            };
            if (value === 0) return null;
            return `${name} ${(percent * 100).toFixed(0)}%`;
          }}
          labelLine={false}
        >
          {data.map((entry) => (
            <Cell key={entry.key} fill={severityColor(entry.key)} />
          ))}
        </Pie>
        <Tooltip contentStyle={tooltipStyle()} />
      </PieChart>
    </ResponsiveContainer>
  );
}

export function DepartmentDistributionChart({ stats }: { stats: Stats }) {
  const data = Object.entries(stats.by_department)
    .map(([name, value]) => ({ name, value }))
    .sort((a, b) => b.value - a.value);
  return (
    <ResponsiveContainer width="100%" height="100%">
      <BarChart
        data={data}
        layout="vertical"
        margin={{ top: 4, right: 16, left: 24, bottom: 0 }}
      >
        <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" horizontal={false} />
        <XAxis type="number" allowDecimals={false} tick={{ fontSize: 11, fill: "#64748b" }} />
        <YAxis
          type="category"
          dataKey="name"
          width={130}
          tick={{ fontSize: 11, fill: "#334155" }}
        />
        <Tooltip cursor={{ fill: "#f8fafc" }} contentStyle={tooltipStyle()} />
        <Bar dataKey="value" radius={[0, 6, 6, 0]} fill="#059669" barSize={18} />
      </BarChart>
    </ResponsiveContainer>
  );
}