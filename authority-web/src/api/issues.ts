import { client } from "./client";
import type {
  ClusterMember,
  ImageSimilarityResult,
  Issue,
  IssueDetail,
  IssueListParams,
  IssueStatus,
  Paginated,
  PriorityClass,
  PriorityReason,
  VisionReport,
} from "../types";

/**
 * DRF serializes `Decimal` coordinates and `FloatField` scores as JSON numbers,
 * but depending on the Django/DRF version a `DecimalField` can arrive as a
 * string. Coercing at the boundary keeps map math and score comparisons from
 * silently producing NaN.
 */
function toNumber(value: unknown, fallback = 0): number {
  if (typeof value === "number") return value;
  if (value == null || value === "") return fallback;
  const n = Number(value);
  return Number.isNaN(n) ? fallback : n;
}

function toNumberArray(value: unknown): number[] {
  if (!Array.isArray(value)) return [];
  return value.map((v) => toNumber(v)).filter((n) => Number.isFinite(n));
}

const PRIORITY_CLASSES: readonly PriorityClass[] = [
  "low",
  "medium",
  "high",
  "critical",
];

function isPriorityClass(value: unknown): value is PriorityClass {
  return (
    typeof value === "string" &&
    (PRIORITY_CLASSES as readonly string[]).includes(value.toLowerCase())
  );
}

/**
 * Resolve the urgency band.
 *
 * The deployed backend sends `priority_label` ("medium"); the local source
 * sends `priority_class`. Accept both, and never guess a band the backend did
 * not report.
 */
function resolvePriorityClass(r: Record<string, unknown>): PriorityClass {
  if (isPriorityClass(r.priority_class)) {
    return r.priority_class.toLowerCase() as PriorityClass;
  }
  if (isPriorityClass(r.priority_label)) {
    return r.priority_label.toLowerCase() as PriorityClass;
  }
  const detail = r.priority_detail as { class?: unknown } | undefined;
  if (isPriorityClass(detail?.class)) {
    return detail.class.toLowerCase() as PriorityClass;
  }
  // A reported numeric score is real data, so banding it is a derived view of
  // the backend's own thresholds rather than an invented value.
  if (r.priority != null) {
    const score = toNumber(r.priority, -1);
    if (score >= 70) return "critical";
    if (score >= 40) return "high";
    if (score >= 15) return "medium";
    return "low";
  }
  return "low";
}

/**
 * Map the deployed `priority_reasons` shape `{note, factor, points}` onto the
 * console's component shape. `label` stays the machine code and `detail` the
 * human sentence, so the UI can show the backend's own wording.
 */
function toPriorityReasons(value: unknown): PriorityReason[] {
  if (!Array.isArray(value)) return [];
  const out: PriorityReason[] = [];
  for (const entry of value) {
    if (!entry || typeof entry !== "object") continue;
    const e = entry as Record<string, unknown>;
    const code = typeof e.factor === "string" ? e.factor : typeof e.code === "string" ? e.code : "";
    if (!code) continue;
    out.push({
      code,
      label: code,
      points: toNumber(e.points),
      detail:
        typeof e.note === "string" && e.note
          ? e.note
          : typeof e.detail === "string"
            ? e.detail
            : typeof e.label === "string"
              ? e.label
              : code,
    });
  }
  return out;
}

function normalizeIssue(raw: unknown): Issue {
  const r = (raw ?? {}) as Record<string, unknown>;
  const id = toNumber(r.id);
  const clusterSize = toNumber(r.cluster_size, 1);
  const masterId = toNumber(r.master_id, id);
  return {
    ...(raw as Issue),
    latitude: toNumber(r.latitude),
    longitude: toNumber(r.longitude),
    confidence: toNumber(r.confidence),
    priority: toNumber(r.priority),
    cluster_size: clusterSize,
    supporting_count: Math.max(clusterSize - 1, 0),
    duplicate_count: toNumber(r.duplicate_count),
    // `master_id` is the reliable signal. The create response's own `is_master`
    // is serialized before the clustering pass runs, so a brand-new master is
    // briefly reported as `false` and only self-heals on refetch.
    is_master: masterId === id && r.duplicate_of == null,
    master_id: masterId,
    cluster_member_ids: toNumberArray(r.cluster_member_ids),
    priority_class: resolvePriorityClass(r),
    // The deployed backend reports the score, band and per-component reasons
    // but not the legacy nested detail blob. Leaving this null is what lets the
    // UI state that the full breakdown was not reported.
    priority_detail: (r.priority_detail as Issue["priority_detail"]) ?? null,
    priority_reasons: toPriorityReasons(r.priority_reasons),
    priority_label: typeof r.priority_label === "string" ? r.priority_label : undefined,
    priority_model_score:
      r.priority_model_score == null ? null : toNumber(r.priority_model_score),
    vision: (r.vision as VisionReport | undefined) ?? null,
    resolution_similarity:
      r.resolution_similarity == null ? null : toNumber(r.resolution_similarity),
  };
}

function normalizeMember(raw: unknown): ClusterMember {
  const r = (raw ?? {}) as Record<string, unknown>;
  return {
    ...(raw as ClusterMember),
    latitude: toNumber(r.latitude),
    longitude: toNumber(r.longitude),
    priority: toNumber(r.priority),
    is_master: toNumber(r.master_id, toNumber(r.id)) === toNumber(r.id),
    similarity_to_master:
      r.similarity_to_master == null ? null : toNumber(r.similarity_to_master),
  };
}

/** Cap on members fetched to hydrate a supporting report's cluster. */
const MAX_CLUSTER_FETCH = 50;

/**
 * Resolve the full cluster for a supporting report.
 *
 * A supporting row carries an empty `cluster_member_ids`; membership only
 * exists on the master. The public issue endpoints are used because they are the
 * verified read path for citizen-visible issues, and the values returned are
 * the backend's own — nothing is inferred.
 */
async function resolveClusterFromMaster(issue: Issue): Promise<ClusterMember[]> {
  const masterId = issue.master_id;
  if (!masterId || masterId === issue.id) return [];

  let memberIds: number[] = [];
  try {
    const { data } = await client.get<Record<string, unknown>>(
      `/api/issues/${masterId}/`,
    );
    memberIds = toNumberArray(data.cluster_member_ids);
  } catch {
    return [];
  }

  if (memberIds.length === 0) return [];
  const targets = memberIds.slice(0, MAX_CLUSTER_FETCH);

  const settled = await Promise.allSettled(
    targets.map((mid) =>
      client.get<Record<string, unknown>>(`/api/issues/${mid}/`).then((r) => r.data),
    ),
  );
  return settled
    .filter(
      (s): s is PromiseFulfilledResult<Record<string, unknown>> => s.status === "fulfilled",
    )
    .map((s) => normalizeMember(s.value));
}

/**
 * The list endpoint returns a bare array unless `page` is supplied, in which
 * case it returns the paginated envelope. Both are handled here so callers
 * always receive a plain array.
 */
export interface IssueListResult {
  issues: Issue[];
  /** Absent when the caller did not request pagination. */
  page: Paginated<Issue> | null;
  /** Set when a fallback endpoint supplied the rows. */
  data_source_note?: string;
}

/**
 * True when a response status means "this deployment does not expose that
 * route" — the only condition under which falling back is honest. A 401/403 is
 * an authorization outcome and must surface, never be retried elsewhere.
 */
function isMissingRoute(error: unknown): boolean {
  const status = (error as { response?: { status?: number } })?.response?.status;
  return status === 404 || status === 405;
}

export async function fetchIssues(
  params: IssueListParams = {},
): Promise<IssueListResult> {
  try {
    return await fetchIssuesFrom("/api/authority/issues/", params, undefined);
  } catch (error) {
    if (!isMissingRoute(error)) throw error;
    // The authority list route is absent on this deployment; the public issue
    // feed is the real citizen-visible dataset, so read from there instead of
    // inventing rows.
    return fetchIssuesFrom("/api/issues/", params, {
      scope: params.scope === "supporting" ? "all" : params.scope,
    });
  }
}

async function fetchIssuesFrom(
  url: string,
  params: IssueListParams,
  overrides: Record<string, unknown> | undefined,
): Promise<IssueListResult> {
  const { data } = await client.get<unknown>(url, {
    params: {
      ...overrides,
      scope: params.scope,
      status: params.status,
      severity: params.severity,
      category: params.category,
      priority_class: params.priority_class,
      department: params.department,
      assigned: params.assigned,
      priority_min: params.priority_min,
      priority_max: params.priority_max,
      created_after: params.created_after,
      created_before: params.created_before,
      lat_min: params.lat_min,
      lat_max: params.lat_max,
      lon_min: params.lon_min,
      lon_max: params.lon_max,
      q: params.q?.trim() || undefined,
      include_resolved: params.includeResolved ? "1" : undefined,
      ordering: params.ordering,
      page: params.page,
      page_size: params.pageSize,
    },
  });

  if (Array.isArray(data)) {
    return { issues: data.map(normalizeIssue), page: null };
  }

  const envelope = data as Paginated<unknown>;
  const issues = (envelope?.results ?? []).map(normalizeIssue);
  return {
    issues,
    // Re-shape the envelope so `results` holds the already-normalized issues
    // rather than the raw, un-coerced payload.
    page: envelope ? { ...envelope, results: issues } : null,
  };
}

export async function fetchIssue(id: number | string): Promise<IssueDetail> {
  const { data } = await client.get<Record<string, unknown>>(
    `/api/authority/issues/${id}/`,
  );
  const issue = normalizeIssue(data);

  let cluster: ClusterMember[] = Array.isArray(data.cluster)
    ? (data.cluster as unknown[]).map(normalizeMember)
    : [];

  if (cluster.length === 0 && issue.cluster_member_ids.length === 0) {
    cluster = await resolveClusterFromMaster(issue);
  }

  return {
    ...issue,
    cluster,
    master: data.master ? normalizeIssue(data.master) : issue,
    allowed_transitions: Array.isArray(data.allowed_transitions)
      ? (data.allowed_transitions as IssueStatus[])
      : [],
    priority_explanation:
      (data.priority_explanation as IssueDetail["priority_explanation"]) ??
      issue.priority_detail ??
      ({} as IssueDetail["priority_explanation"]),
  };
}

export async function transitionIssue(
  id: number | string,
  newStatus: IssueStatus,
): Promise<Issue> {
  const { data } = await client.post<unknown>(
    `/api/authority/issues/${id}/transition/`,
    { new_status: newStatus },
  );
  return normalizeIssue(data);
}

export type ResolveResult = Issue & { image_similarity?: ImageSimilarityResult };

export async function resolveIssue(
  id: number | string,
  formData: FormData,
): Promise<ResolveResult> {
  const { data } = await client.post<Record<string, unknown>>(
    `/api/authority/issues/${id}/resolve/`,
    formData,
  );
  const { image_similarity, ...rest } = data;
  return {
    ...normalizeIssue(rest),
    image_similarity: image_similarity as ImageSimilarityResult | undefined,
  };
}

export interface AssignmentPayload {
  department?: string;
  /** `null` unassigns the officer. */
  officer_id?: number | null;
}

/**
 * Staff-only assignment (PATCH on the authority endpoint).
 *
 * A 400 response carries `{detail, allowed}` for an unknown department, which
 * `client.ts` surfaces as an `ApiError`.
 */
export async function updateAssignment(
  id: number | string,
  payload: AssignmentPayload,
): Promise<Issue> {
  const { data } = await client.patch<unknown>(
    `/api/authority/issues/${id}/`,
    payload,
  );
  return normalizeIssue(data);
}

/** Kept for callers that only reassign the department. */
export async function updateDepartment(
  id: number | string,
  department: string,
): Promise<Issue> {
  return updateAssignment(id, { department });
}
