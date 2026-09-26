import {
  CATEGORY_LABELS,
  PRIORITY_CLASS_LABELS,
  SEVERITY_LABELS,
} from "../types";
import { API_BASE_URL } from "../api/client";

/**
 * Django returns relative media URLs such as `/media/issues/...`. In
 * development the SPA is served from a different origin (Vite) than the
 * backend (runserver), so relative media paths must be prefixed with the
 * backend origin. Absolute URLs (e.g. S3/R2 presigned) pass through untouched.
 *
 * The origin comes from the API client so there is exactly one configured
 * backend URL and it can never disagree with the one used for API calls.
 */
export function resolveMediaUrl(url: string | null | undefined): string | undefined {
  if (url == null || url === "") return undefined;
  if (/^https?:\/\//i.test(url)) return url;
  if (url.startsWith("/")) return `${API_BASE_URL}${url}`;
  return url;
}

export function severityColor(severity: string): string {
  switch (severity) {
    case "critical":
      return "#e11d48";
    case "high":
      return "#f97316";
    case "medium":
      return "#eab308";
    default:
      return "#10b981";
  }
}

export function severityStyles(severity: string) {
  switch (severity) {
    case "critical":
      return { badge: "bg-rose-100 text-rose-700", dot: "bg-rose-500" };
    case "high":
      return { badge: "bg-orange-100 text-orange-700", dot: "bg-orange-500" };
    case "medium":
      return { badge: "bg-amber-100 text-amber-700", dot: "bg-amber-500" };
    default:
      return { badge: "bg-emerald-100 text-emerald-700", dot: "bg-emerald-500" };
  }
}

export function severityLabel(severity: string): string {
  return SEVERITY_LABELS[severity as keyof typeof SEVERITY_LABELS] ?? severity;
}

export function categoryLabel(category: string): string {
  return CATEGORY_LABELS[category as keyof typeof CATEGORY_LABELS] ?? category;
}

export function priorityClassLabel(priorityClass: string): string {
  return (
    PRIORITY_CLASS_LABELS[
      priorityClass as keyof typeof PRIORITY_CLASS_LABELS
    ] ?? priorityClass
  );
}

/**
 * Styling for the priority band.
 *
 * Intentionally distinct from `severityStyles` even though the two share the
 * same four band names: priority answers "how soon should we act", severity
 * answers "how bad is the damage", and conflating them in the UI is exactly the
 * confusion the backend separates them to avoid.
 */
export function priorityStyles(priorityClass: string) {
  switch (priorityClass) {
    case "critical":
      return {
        badge: "bg-rose-100 text-rose-800 ring-1 ring-rose-300",
        dot: "bg-rose-600",
      };
    case "high":
      return {
        badge: "bg-violet-100 text-violet-800 ring-1 ring-violet-300",
        dot: "bg-violet-600",
      };
    case "medium":
      return {
        badge: "bg-sky-100 text-sky-800 ring-1 ring-sky-300",
        dot: "bg-sky-600",
      };
    default:
      return {
        badge: "bg-slate-100 text-slate-700 ring-1 ring-slate-300",
        dot: "bg-slate-500",
      };
  }
}

export function statusStyles(status: string) {
  switch (status) {
    case "reported":
      return { badge: "bg-slate-100 text-slate-700", dot: "bg-slate-400" };
    case "verified":
      return { badge: "bg-sky-100 text-sky-700", dot: "bg-sky-500" };
    case "assigned":
      return { badge: "bg-indigo-100 text-indigo-700", dot: "bg-indigo-500" };
    case "in_progress":
      return { badge: "bg-blue-100 text-blue-700", dot: "bg-blue-500" };
    case "resolved":
      return { badge: "bg-emerald-100 text-emerald-700", dot: "bg-emerald-500" };
    case "rejected":
      return { badge: "bg-neutral-200 text-neutral-600", dot: "bg-neutral-500" };
    default:
      return { badge: "bg-slate-100 text-slate-700", dot: "bg-slate-400" };
  }
}

export function isOpenStatus(status: string): boolean {
  return !["resolved", "rejected"].includes(status);
}

export function isValidCoord(
  lat: number | null | undefined,
  lng: number | null | undefined,
): boolean {
  if (lat == null || lng == null) return false;
  if (Number.isNaN(lat) || Number.isNaN(lng)) return false;
  return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
}