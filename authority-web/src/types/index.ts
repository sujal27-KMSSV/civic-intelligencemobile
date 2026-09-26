// Shared API types — mirrored 1:1 from the Django authority serializers.
// Do NOT invent fields here; the backend payload is the source of truth.
//
// Mirrors:
//   backend/authority/serializers.py   (issue + cluster serializers)
//   backend/authority/service.py       (stats, hotspots, priority explanation)
//   backend/authority/api.py           (meta endpoint envelope)
//   backend/issues/priority.py         (priority engine output)
//   backend/issues/spatial.py          (hotspot cells)

export type IssueStatus =
  | "reported"
  | "verified"
  | "assigned"
  | "in_progress"
  | "resolved"
  | "rejected";

export type IssueSeverity = "low" | "medium" | "high" | "critical";

/** Urgency band for the computed priority score. NOT the same as severity. */
export type PriorityClass = "low" | "medium" | "high" | "critical";

/** Mirrors issues.models.Issue.Category (migration 0007). */
export type IssueCategory =
  | "pothole"
  | "road_damage"
  | "footpath"
  | "garbage"
  | "illegal_dumping"
  | "streetlight"
  | "traffic_signal"
  | "drainage"
  | "other";

export type AllowedTransitions = Record<IssueStatus, IssueStatus[]>;

export interface SeveritySignal {
  type: string;
  value?: string | number;
  points: number;
}

/** One component's contribution to the priority score, from the stored detail. */
export interface PriorityReason {
  code: string;
  label: string;
  points: number;
  detail: string;
}

/** One entry of `PRIORITY_COMPONENTS`, served by `GET /authority/meta/`. */
export interface PriorityComponentDoc {
  code: string;
  label: string;
  description: string;
  cap: number;
  /** Present on the saturating count-based components. */
  half_saturation?: number;
}

export interface PriorityClassThreshold {
  min_score: number;
  class: PriorityClass;
  label: string;
}

export interface PriorityEngineInfo {
  engine: string;
  engine_honest_label: string;
  score_range: [number, number];
  class_thresholds: PriorityClassThreshold[];
  components: PriorityComponentDoc[];
  /** Weights of the 5 duplicate signals, for the consolidation explainer. */
  duplicate_signals: Record<string, number>;
  component_total_cap: number;
  honest_note: string;
}

/**
 * The stored `priority_detail` payload (backend/issues/priority.py).
 *
 * `engine_honest_label` is rendered verbatim in the dashboard. The engine is a
 * transparent weighted rule model, NOT a trained ML model, and the UI must not
 * describe it as one.
 */
export interface PriorityDetail {
  score: number;
  class: PriorityClass;
  label: string;
  engine: string;
  engine_honest_label: string;
  reasons: PriorityReason[];
  /** Keyed by component code, e.g. `category`, `severity`, `corroboration`. */
  components: Record<string, number>;
  raw_total: number;
  inputs: {
    category: IssueCategory;
    severity: IssueSeverity;
    cluster_size: number;
    distinct_report_days: number;
    open_hours: number;
    mean_similarity: number;
    prior_reports_at_location: number;
  };
}

export interface IssueAnalysis {
  engine: string;
  engine_honest_label: string;
  duplicate: {
    is_duplicate: boolean;
    similarity_score: number;
    root_id: number | null;
    cluster_members: number[];
    duplicate_count: number;
    root_duplicate_count?: number;
    signals?: Record<string, number> | null;
    weights?: Record<string, number> | null;
    used_weights?: Record<string, number> | null;
    matched_report_id?: number | null;
  };
  severity: {
    score: number;
    signals: SeveritySignal[];
  };
  department: string;
  department_by: string;
}

/**
 * Per-signal breakdown of why a report was consolidated into a cluster.
 * `null` when the issue was never run through duplicate detection.
 */
export interface DuplicateSignals {
  signals: Record<string, number> | null;
  weights: Record<string, number> | null;
  used_weights: Record<string, number> | null;
  similarity_score: number | null;
  matched_report_id: number | null;
  root_id: number | null;
}

/**
 * What a vision-capable deployment reports about one image.
 *
 * The backend returns the literal `{status: "not_analyzed", service: null}`
 * when no analyzer is configured. That is the honest "nothing to show" state
 * and the UI must render it as such — never as a detection result.
 */
export interface VisionReport {
  status?: string;
  service?: string | null;
  objects?: unknown[];
  count?: number;
  summary?: string;
  /** Retains any additional analyzer keys without pretending to model them. */
  [key: string]: unknown;
}

export interface Issue {
  id: number;
  image_url: string;
  image_source: string | null;
  description: string;
  latitude: number;
  longitude: number;
  address: string;
  status: IssueStatus;
  created_at: string;
  updated_at: string;
  category: IssueCategory;
  confidence: number;
  severity: IssueSeverity;
  priority: number;
  /** Derived: the deployment sends `priority_label`, not `priority_class`. */
  priority_class: PriorityClass;
  /** Derived from `priority_reasons` when the deployment sends no detail blob. */
  priority_detail: PriorityDetail | null;
  duplicate: boolean;
  duplicate_count: number;
  duplicate_of: number | null;
  /** Derived from `master_id === id`; the create response's own flag is stale. */
  is_master: boolean;
  /** The master this report belongs to (its own id when it is a master). */
  master_id: number;
  /** Citizen reports represented by this issue's master. */
  cluster_size: number;
  /** `cluster_size - 1`. */
  supporting_count: number;
  /**
   * Populated only on a master row. A supporting report carries an empty list,
   * so cluster membership is resolved through the master's own list.
   */
  cluster_member_ids: number[];
  /**
   * Per-signal consolidation breakdown. Absent unless a deployment reports it —
   * there is no honest way to synthesise these, so the UI must say so.
   */
  duplicate_signals?: DuplicateSignals | null;
  department: string;
  assigned_to?: number | null;
  assigned_to_email?: string | null;
  assigned_to_name?: string | null;
  assigned_at?: string | null;
  /** Legacy nested analysis blob. Not returned by the deployed backend. */
  analysis?: IssueAnalysis;
  /** Not returned by the deployed backend. */
  reporter_email?: string;
  /** Not returned by the deployed backend. */
  resolution_notes?: string;
  /** Reported by the deployed backend. */
  vision?: VisionReport | null;
  /** Human-readable priority band from the deployed backend. */
  priority_label?: string;
  /** Advisory prototype-model score; the rule engine remains authoritative. */
  priority_model_score?: number | null;
  /** Per-component contributions: `{note, factor, points}`. */
  priority_reasons?: PriorityReason[];
  resolution_image_url: string | null;
  resolution_status?: string | null;
  resolution_similarity: number | null;
  resolved_at: string | null;
  /** The viewer may edit/retract this report (ownership + 10-minute window). */
  can_edit?: boolean;
  can_delete?: boolean;
}

/** Compact row for a supporting report inside a master's cluster. */
export interface ClusterMember {
  id: number;
  image_url: string;
  description: string;
  latitude: number;
  longitude: number;
  status: IssueStatus;
  category: IssueCategory;
  severity: IssueSeverity;
  priority: number;
  created_at: string;
  reporter_email: string;
  is_master: boolean;
  similarity_to_master: number | null;
}

export interface IssueDetail extends Issue {
  /** Master first, then supporting reports oldest-first. */
  cluster: ClusterMember[];
  /** The cluster root, as a full issue payload. */
  master: Issue;
  allowed_transitions: IssueStatus[];
  priority_explanation: PriorityDetail;
}

export interface ImageSimilarityResult {
  similarity: number | null;
  brightness_before?: number;
  brightness_after?: number;
  method: string;
  interpretation: "identical" | "similar" | "different" | "unavailable";
  reason?: string;
}

export interface Stats {
  /** Open master issues — the unit an authority actually acts on. */
  active_issues: number;
  critical_issues: number;
  high_priority_issues: number;
  resolved_issues: number;
  /** Citizen reports folded into an existing master. */
  reports_consolidated: number;
  active_departments: number;
  total_masters: number;
  total_reports: number;
  total_reports_all_time: number;
  open_reports: number;
  supporting_reports: number;
  reported_last_24h: number;
  resolved_last_24h: number;
  assigned_open: number;
  unassigned_open: number;
  /** Keyed by the raw enum value, e.g. `critical` (not `Critical`). */
  by_status: Record<string, number>;
  by_open_status: Record<string, number>;
  by_severity: Record<string, number>;
  by_priority_class: Record<string, number>;
  by_category: Record<string, number>;
  by_department: Record<string, number>;
  active_department_names: string[];
  /** Explains that master rows stand in for whole clusters. */
  counting_convention: string;
}

export interface AuthUser {
  id: number;
  email: string;
  first_name: string;
  last_name: string;
  phone: string | null;
  /**
   * The deployed `/api/auth/login/` serializer does not expose this field, so
   * it stays absent for real responses. Authority access is proven by probing a
   * staff-only endpoint instead — see `api/auth.ts`.
   */
  is_staff?: boolean;
}

export interface AuthResponse {
  token: string;
  user: AuthUser;
}

/** One aggregated grid cell from the hotspots endpoint. */
export interface HotspotCell {
  latitude: number;
  longitude: number;
  /** Master issues in this cell. */
  issue_count: number;
  master_count: number;
  /** Citizen reports, i.e. masters + their supporting reports. */
  report_count: number;
  categories: Record<string, number>;
  /** The deployed cell reports distributions as `{value, count}` pairs. */
  departments?: Record<string, number>;
  statuses?: Record<string, number>;
  /**
   * Optional because the deployed grid cell does not report a dominant
   * category, a worst severity or a radius. When absent the UI says the value
   * was not reported rather than showing a stand-in.
   */
  dominant_category?: IssueCategory;
  dominant_category_count?: number;
  worst_severity?: IssueSeverity;
  severities?: Record<string, number>;
  radius_m?: number;
  /** Cell size in degrees, as reported by the aggregation. */
  grid?: number;
  /** The grid key or id the cell is reported under, when present. */
  grid_id?: string | number | null;
  top_issue_id?: number | null;
  top_priority?: number | null;
}

export interface HotspotsResponse {
  hotspots: HotspotCell[];
  total_masters: number;
  method: string;
  /** Rendered verbatim; this is a grid aggregate, not a learned model. */
  method_honest_label: string;
  spatial_backend: SpatialBackendInfo;
  returned: number;
  limit: number;
  /**
   * Set when the payload had to be read from a different endpoint or reshaped
   * to match the console's contract. Rendered so the source of the numbers is
   * never ambiguous.
   */
  data_source_note?: string;
}

/**
 * Honest description of the ACTIVE spatial path (`spatial.describe_spatial_backend`).
 * `backend` is `postgis` or `haversine`; the `note` is written by the backend to
 * state plainly what is and is not indexed on this deployment.
 */
export interface SpatialBackendInfo {
  backend: "postgis" | "haversine" | string;
  engine: string;
  distance_function: string;
  spatial_index: string;
  note?: string;
  hotspot_cell_degrees: number;
}

/** True when real PostGIS spatial queries are serving this deployment. */
export function isPostgisActive(spatial: SpatialBackendInfo | undefined): boolean {
  return spatial?.backend === "postgis";
}

export interface Officer {
  id: number;
  email: string;
  name: string;
}

export interface EnumOption {
  value: string;
  label: string;
}

export interface MetaResponse {
  departments: {
    assignable: string[];
    by_category: Record<string, string>;
  };
  categories: EnumOption[];
  severities: EnumOption[];
  statuses: EnumOption[];
  priority_classes: EnumOption[];
  ordering: string[];
  scopes: string[];
  officers: Officer[];
  officer_count: number;
  lifecycle: {
    valid_transitions: AllowedTransitions;
    note: string;
  };
  capabilities: {
    spatial: SpatialBackendInfo;
    vision: VisionCapabilityReport;
    priority_engine: PriorityEngineInfo;
  };
}

/**
 * What this Django deployment can genuinely claim about vision.
 * The dashboard must never display a capability the deployment lacks, so these
 * flags drive the UI rather than a hardcoded feature list.
 */
export interface VisionCapabilityReport {
  local_reference_path: {
    available: boolean;
    techniques: string[];
    note: string;
    /** Reminds the UI the handcrafted embedding is not CLIP. */
    honest_note: string;
  };
  ai_service: {
    configured: boolean;
    url: string | null;
    reachable: boolean;
    note: string;
  };
  store_embeddings: boolean;
}

/**
 * Pagination envelope. The backend only paginates when `page` is supplied;
 * otherwise the list endpoint returns a plain array. Note this is the backend's
 * own envelope (`authority.api._paginate`), not DRF's default
 * `{count, next, previous, results}`.
 */
export interface Paginated<T> {
  count: number;
  page: number;
  page_size: number;
  total_pages: number;
  results: T[];
}

/** Whether the list shows masters, their supporting reports, or both. */
export type IssueScope = "masters" | "supporting" | "all";

/** Whitelisted sort keys. The backend rejects anything else. */
export type IssueOrdering =
  | "priority"
  | "newest"
  | "oldest"
  | "cluster"
  | "severity"
  | "reports"
  | "status";

export type AssignmentFilter = "assigned" | "unassigned";

export interface IssueListParams {
  /** Defaults to `masters` server-side. */
  scope?: IssueScope;
  status?: IssueStatus;
  severity?: IssueSeverity;
  priority_class?: PriorityClass;
  category?: IssueCategory;
  department?: string;
  assigned?: AssignmentFilter;
  priority_min?: number;
  priority_max?: number;
  created_after?: string;
  created_before?: string;
  lat_min?: number;
  lat_max?: number;
  lon_min?: number;
  lon_max?: number;
  q?: string;
  includeResolved?: boolean;
  ordering?: IssueOrdering;
  /** Supplying this opts into the paginated envelope. */
  page?: number;
  pageSize?: number;
}

export const SEVERITY_LABELS: Record<IssueSeverity, string> = {
  low: "Low",
  medium: "Medium",
  high: "High",
  critical: "Critical",
};

export const PRIORITY_CLASS_LABELS: Record<PriorityClass, string> = {
  low: "Low",
  medium: "Medium",
  high: "High",
  critical: "Critical",
};

export const STATUS_LABELS: Record<IssueStatus, string> = {
  reported: "Reported",
  verified: "Verified",
  assigned: "Assigned",
  in_progress: "In progress",
  resolved: "Resolved",
  rejected: "Rejected",
};

export const CATEGORY_LABELS: Record<IssueCategory, string> = {
  pothole: "Pothole",
  road_damage: "Road damage",
  footpath: "Broken footpath",
  garbage: "Garbage / waste",
  illegal_dumping: "Illegal dumping",
  streetlight: "Streetlight",
  traffic_signal: "Traffic signal",
  drainage: "Drainage",
  other: "Other",
};

/**
 * Fallback used only until `GET /authority/meta/` resolves. The backend's
 * `/meta/` response is the source of truth for assignable departments.
 */
export const DEPARTMENTS = [
  "Road Maintenance",
  "Solid Waste Management",
  "Public Lighting",
  "Drainage & Sewage",
  "General Services",
  "Unassigned",
];

export const CATEGORIES = Object.keys(CATEGORY_LABELS) as IssueCategory[];
export const SEVERITIES = Object.keys(SEVERITY_LABELS) as IssueSeverity[];
export const PRIORITY_CLASSES = Object.keys(
  PRIORITY_CLASS_LABELS,
) as PriorityClass[];
export const STATUSES = Object.keys(STATUS_LABELS) as IssueStatus[];

/**
 * Mirrors issues/lifecycle.py VALID_TRANSITIONS.
 *
 * Note that `in_progress -> resolved` is valid in the lifecycle table, but the
 * generic transition endpoint rejects it: reaching `resolved` requires the
 * dedicated resolution action with BEFORE/AFTER evidence. The per-issue
 * authoritative list comes from the API (`allowed_transitions` /
 * `meta.lifecycle.valid_transitions`); this constant is the offline fallback.
 */
export const ALLOWED_TRANSITIONS: AllowedTransitions = {
  reported: ["verified", "rejected"],
  verified: ["assigned", "in_progress", "rejected"],
  assigned: ["in_progress", "rejected"],
  in_progress: ["resolved", "rejected"],
  resolved: ["in_progress"],
  rejected: ["reported"],
};
