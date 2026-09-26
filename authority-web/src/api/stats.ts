import { client } from "./client";
import type {
  HotspotCell,
  HotspotsResponse,
  IssueCategory,
  MetaResponse,
  Stats,
} from "../types";

function toNumber(value: unknown, fallback = 0): number {
  if (typeof value === "number") return value;
  if (value == null || value === "") return fallback;
  const n = Number(value);
  return Number.isNaN(n) ? fallback : n;
}

function statusOf(error: unknown): number | undefined {
  return (error as { response?: { status?: number } })?.response?.status;
}

/**
 * The backend's Stats payload is aggregate-only, but the distribution keys are
 * dynamic (they follow the enum choices), so a missing key is normal rather
 * than a contract violation.
 *
 * If this deployment does not expose the route, the public issue feed is read
 * instead and the aggregates are computed from those real rows. A 401/403 is
 * never retried here — that is an authorization outcome, not a contract gap.
 */
export async function fetchStats(): Promise<Stats> {
  try {
    const { data } = await client.get<Stats>("/api/authority/stats/");
    return data;
  } catch (error) {
    const code = statusOf(error);
    if (code !== 404 && code !== 405) throw error;
    return deriveStatsFromPublicIssues();
  }
}

/**
 * Aggregate the public issue feed into the console's Stats shape.
 *
 * Every number here is a count of real rows the backend returned; nothing is
 * sampled or estimated. `counting_convention` states the basis explicitly so
 * the dashboard cannot imply this is the authority's own aggregation.
 */
async function deriveStatsFromPublicIssues(): Promise<Stats> {
  const { data } = await client.get<unknown>("/api/issues/?collapse=0");
  const rows = (Array.isArray(data) ? data : []) as Record<string, unknown>[];

  const by_status: Record<string, number> = {};
  const by_open_status: Record<string, number> = {};
  const by_severity: Record<string, number> = {};
  const by_priority_class: Record<string, number> = {};
  const by_category: Record<string, number> = {};
  const by_department: Record<string, number> = {};
  const departments = new Set<string>();

  const bump = (m: Record<string, number>, k: unknown) => {
    const key = String(k ?? "unknown");
    m[key] = (m[key] ?? 0) + 1;
  };

  const cutoff = Date.now() - 24 * 3600 * 1000;
  let masters = 0;
  let supporting = 0;
  let openReports = 0;
  let resolved = 0;
  let resolvedLast24h = 0;
  let reportedLast24h = 0;
  let assignedOpen = 0;
  let unassignedOpen = 0;
  let critical = 0;
  let high = 0;
  let highPriority = 0;
  let active = 0;

  for (const row of rows) {
    const status = String(row.status ?? "unknown");
    const id = toNumber(row.id);
    const masterId = toNumber(row.master_id, id);
    const isMaster = masterId === id && row.duplicate_of == null;
    const created = Date.parse(String(row.created_at ?? ""));
    const resolvedAt = Date.parse(String(row.resolved_at ?? ""));
    const assigned = row.assigned_to != null || String(row.department ?? "") !== "";

    bump(by_status, status);
    if (status !== "resolved" && status !== "rejected") bump(by_open_status, status);
    bump(by_severity, row.severity);
    bump(by_category, row.category);
    if (row.department != null) {
      bump(by_department, row.department);
      departments.add(String(row.department));
    }

    const band = String(row.priority_label ?? "").toLowerCase();
    if (band) bump(by_priority_class, band);

    if (isMaster) {
      masters += 1;
      if (status !== "resolved" && status !== "rejected") {
        active += 1;
        if (String(row.severity) === "critical") critical += 1;
        if (String(row.severity) === "high") high += 1;
        if (band === "high" || band === "critical") highPriority += 1;
        if (assigned) assignedOpen += 1;
        else unassignedOpen += 1;
      }
    } else {
      supporting += 1;
    }

    if (status !== "resolved" && status !== "rejected") openReports += 1;
    if (status === "resolved") {
      resolved += 1;
      if (!Number.isNaN(resolvedAt) && resolvedAt >= cutoff) resolvedLast24h += 1;
    }
    if (!Number.isNaN(created) && created >= cutoff) reportedLast24h += 1;
  }

  return {
    active_issues: active,
    critical_issues: critical,
    high_priority_issues: highPriority,
    resolved_issues: resolved,
    reports_consolidated: supporting,
    active_departments: departments.size,
    total_masters: masters,
    total_reports: rows.length,
    total_reports_all_time: rows.length,
    open_reports: openReports,
    supporting_reports: supporting,
    reported_last_24h: reportedLast24h,
    resolved_last_24h: resolvedLast24h,
    assigned_open: assignedOpen,
    unassigned_open: unassignedOpen,
    by_status,
    by_open_status,
    by_severity,
    by_priority_class,
    by_category,
    by_department,
    active_department_names: [...departments].sort(),
    counting_convention:
      "Counted in the console from the public issue feed because this deployment does not expose /api/authority/stats/. One master row represents its whole cluster.",
  };
}

export interface HotspotParams {
  category?: IssueCategory;
  includeResolved?: boolean;
  limit?: number;
}

/**
 * Turn the backend's `{value, count}` pair arrays into a plain record.
 * Already-record values pass through untouched.
 */
function toCountRecord(value: unknown): Record<string, number> {
  if (!value) return {};
  if (Array.isArray(value)) {
    const out: Record<string, number> = {};
    for (const entry of value) {
      if (Array.isArray(entry) && entry.length >= 2) {
        out[String(entry[0])] = toNumber(entry[1]);
      } else if (entry && typeof entry === "object") {
        const e = entry as Record<string, unknown>;
        const k = e.value ?? e.key ?? e.name;
        if (k != null) out[String(k)] = toNumber(e.count ?? e.value_count);
      }
    }
    return out;
  }
  if (typeof value === "object") {
    const out: Record<string, number> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      out[k] = toNumber(v);
    }
    return out;
  }
  return {};
}

/**
 * Geographic hotspot analytics.
 *
 * `method_honest_label` and `spatial_backend` are part of the response on
 * purpose: the map labels the aggregation method and the active spatial
 * backend rather than implying a learned anomaly model that does not exist.
 *
 * This deployment returns a bare array of grid cells using `lat`/`lon` and
 * pair-array distributions, so the envelope and the coordinate names are both
 * reshaped here rather than being assumed.
 */
export async function fetchHotspots(
  params: HotspotParams = {},
): Promise<HotspotsResponse> {
  let data: unknown;
  let sourceNote: string | undefined;
  let url = "/api/authority/hotspots/";

  try {
    ({ data } = await client.get<unknown>(url, {
      params: {
        category: params.category,
        include_resolved: params.includeResolved ? "1" : undefined,
        limit: params.limit,
      },
    }));
  } catch (error) {
    const code = statusOf(error);
    if (code !== 404 && code !== 405) throw error;
    url = "/api/hotspots/";
    sourceNote =
      "Hotspot cells read from the public /api/hotspots/ endpoint because this deployment does not expose /api/authority/hotspots/.";
    ({ data } = await client.get<unknown>(url, {
      params: {
        category: params.category,
        include_resolved: params.includeResolved ? "1" : undefined,
        limit: params.limit,
      },
    }));
  }

  const envelope = (data ?? {}) as Record<string, unknown>;
  const cells = Array.isArray(data)
    ? data
    : ((envelope.hotspots ?? envelope.results ?? []) as unknown[]);

  const hotspots = cells.map(normalizeCell);
  const totalMasters =
    envelope.total_masters != null
      ? toNumber(envelope.total_masters)
      : hotspots.reduce((sum, c) => sum + c.issue_count, 0);

  return {
    hotspots,
    total_masters: totalMasters,
    method: String(envelope.method ?? "grid_aggregation"),
    method_honest_label: String(
      envelope.method_honest_label ??
        "Counts of real reports grouped into a fixed geographic grid. This is an aggregation, not a learned anomaly model.",
    ),
    spatial_backend: (envelope.spatial_backend ?? {
      backend: "grid",
      engine: "grid_aggregation",
      distance_function: "grid_bins",
      spatial_index: "none",
      note: "This deployment reports hotspot cells as fixed grid bins without a spatial index.",
      hotspot_cell_degrees: toNumber(envelope.grid),
    }) as HotspotsResponse["spatial_backend"],
    returned: envelope.returned != null ? toNumber(envelope.returned) : hotspots.length,
    limit: toNumber(envelope.limit, params.limit ?? hotspots.length),
    data_source_note: sourceNote,
  };
}

function normalizeCell(raw: unknown): HotspotCell {
  const r = (raw ?? {}) as Record<string, unknown>;
  const categories = toCountRecord(r.categories);
  const severities = toCountRecord(r.severities);
  const dominant = Object.entries(categories).sort((a, b) => b[1] - a[1])[0];

  return {
    ...(r as unknown as HotspotCell),
    latitude: toNumber(r.latitude ?? r.lat),
    longitude: toNumber(r.longitude ?? r.lon ?? r.lng),
    issue_count: toNumber(r.issue_count),
    master_count: toNumber(r.master_count, toNumber(r.issue_count)),
    report_count: toNumber(r.report_count, toNumber(r.issue_count)),
    categories,
    severities,
    departments: toCountRecord(r.departments),
    statuses: toCountRecord(r.statuses),
    grid: r.grid == null ? undefined : toNumber(r.grid),
    top_issue_id: r.top_issue_id == null ? null : toNumber(r.top_issue_id),
    top_priority: r.top_priority == null ? null : toNumber(r.top_priority),
    // Derived from the backend's own category tally when present, and left
    // undefined when the cell reports no categories at all.
    dominant_category: dominant ? (dominant[0] as IssueCategory) : undefined,
    dominant_category_count: dominant ? dominant[1] : undefined,
    worst_severity: undefined,
    radius_m: r.radius_m == null ? undefined : toNumber(r.radius_m),
  };
}

/**
 * Enums, assignable departments, staff officers, the lifecycle table and the
 * live capability probes. The dashboard reads all of its option lists from
 * here so a backend change shows up in the UI without a redeploy.
 *
 * This deployment does not expose `/api/authority/meta/` (404). Rather than
 * inventing officers, capabilities or lifecycle claims, the caller receives
 * `null` and is expected to fall back to the compiled constants and to say in
 * the UI that the metadata is not reported.
 */
export async function fetchMeta(): Promise<MetaResponse | null> {
  try {
    const { data } = await client.get<MetaResponse>("/api/authority/meta/");
    return data;
  } catch (error) {
    const code = statusOf(error);
    // Only a missing route degrades. An auth failure must still surface, and a
    // transient 5xx must not be silently downgraded to "no metadata".
    if (code === 404 || code === 405) return null;
    throw error;
  }
}
