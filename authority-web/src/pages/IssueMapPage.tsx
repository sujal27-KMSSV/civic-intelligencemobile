import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import L from "leaflet";
import {
  Circle,
  MapContainer,
  Marker,
  Popup,
  TileLayer,
  useMap,
} from "react-leaflet";
import "leaflet/dist/leaflet.css";
import { fetchIssues } from "../api/issues";
import { fetchHotspots } from "../api/stats";
import { EmptyState, ErrorState } from "../components/States";
import { CardSkeleton } from "../components/Skeleton";
import { PriorityBadge, SeverityBadge, StatusBadge } from "../components/Badges";
import { useAsync } from "../hooks/useAsync";
import { useMeta } from "../hooks/useMeta";
import {
  categoryLabel,
  isValidCoord,
  severityColor,
} from "../utils/media";
import { formatCount, relativeTime } from "../utils/format";
import {
  CATEGORIES,
  isPostgisActive,
  type HotspotCell,
  type Issue,
  type IssueCategory,
  type IssueSeverity,
} from "../types";

const DEFAULT_CENTER: [number, number] = [28.6139, 77.209];

type LayerMode = "issues" | "hotspots";

function makeIcon(severity: IssueSeverity, reports: number): L.DivIcon {
  const color = severityColor(severity);
  const html = `
    <div class="map-pin" style="background:${color}">
      <span class="map-pin__count">${reports > 1 ? String(reports) : ""}</span>
    </div>
  `;
  return L.divIcon({
    className: "issue-marker",
    html,
    iconSize: [34, 40],
    iconAnchor: [17, 38],
    popupAnchor: [0, -34],
  });
}

function FitBounds({ points }: { points: [number, number][] }) {
  const map = useMap();
  useEffect(() => {
    if (points.length === 0) return;
    map.fitBounds(L.latLngBounds(points), { padding: [48, 48], maxZoom: 15 });
  }, [map, points]);
  return null;
}

function Legend({ mode }: { mode: LayerMode }) {
  if (mode === "hotspots") {
    return (
      <div className="rounded-xl border border-slate-200 bg-white/95 p-3 shadow-sm">
        <p className="text-[11px] font-bold uppercase tracking-wide text-slate-500">
          Reports per cell
        </p>
        <ul className="mt-2 space-y-1.5">
          {[1, 5, 20, 50].map((n) => (
            <li key={n} className="flex items-center gap-2 text-xs text-slate-700">
              <span
                className="h-3 w-3 rounded-full border border-brand-400"
                style={{
                  background: `rgba(37, 99, 235, ${Math.min(0.15 + n / 60, 0.75)})`,
                }}
              />
              {n === 1 ? "1" : `${n}+`}
            </li>
          ))}
        </ul>
      </div>
    );
  }
  const items: [IssueSeverity, string][] = [
    ["critical", "Critical"],
    ["high", "High"],
    ["medium", "Medium"],
    ["low", "Low"],
  ];
  return (
    <div className="rounded-xl border border-slate-200 bg-white/95 p-3 shadow-sm">
      <p className="text-[11px] font-bold uppercase tracking-wide text-slate-500">
        Severity
      </p>
      <ul className="mt-2 space-y-1.5">
        {items.map(([sev, label]) => (
          <li key={sev} className="flex items-center gap-2 text-xs text-slate-700">
            <span
              className="h-3 w-3 rounded-full"
              style={{ background: severityColor(sev) }}
            />
            {label}
          </li>
        ))}
      </ul>
    </div>
  );
}

/**
 * A hotspot cell drawn as a sized, shaded circle.
 *
 * The radius is derived from what the backend actually reports: `radius_m` when
 * the cell provides it, otherwise the half-diagonal of the cell's own `grid`
 * size in degrees. Both are real reported values -- see the note rendered under
 * the map. Nothing here invents a severity or a category.
 */
function HotspotCircle({ cell, maxReports }: { cell: HotspotCell; maxReports: number }) {
  const intensity = maxReports > 0 ? cell.report_count / maxReports : 0;
  // Colour follows the worst severity when the cell reports one; otherwise it
  // is keyed to volume, which the cell always reports.
  const color = cell.worst_severity
    ? severityColor(cell.worst_severity)
    : "#6366f1";
  const radiusM = cell.radius_m ?? gridCellRadiusM(cell);
  return (
    <Circle
      center={[cell.latitude, cell.longitude]}
      // `radius_m` is a ground distance; Leaflet needs pixels, so it is scaled
      // by latitude. This is a presentational approximation, not a measurement.
      radius={metersToPixels(radiusM, cell.latitude)}
      pathOptions={{
        color,
        weight: 1.5,
        fillColor: color,
        fillOpacity: 0.12 + intensity * 0.45,
      }}
    >
      <Popup>
        <div className="min-w-[220px]">
          <p className="text-sm font-bold text-slate-900">Hotspot cell</p>
          <p className="mt-1 text-xs text-slate-500">
            {formatCount(cell.report_count)} citizen report
            {cell.report_count === 1 ? "" : "s"} across{" "}
            {formatCount(cell.master_count)} physical problem
            {cell.master_count === 1 ? "" : "s"}
          </p>
          <div className="mt-2 flex flex-wrap items-center gap-2">
            {cell.worst_severity ? (
              <SeverityBadge severity={cell.worst_severity} />
            ) : (
              <span className="rounded-full bg-slate-100 px-2 py-0.5 text-[11px] font-semibold text-slate-600">
                Severity not reported per cell
              </span>
            )}
            {cell.dominant_category ? (
              <span className="rounded-full bg-slate-100 px-2 py-0.5 text-[11px] font-semibold text-slate-700">
                Mostly {categoryLabel(cell.dominant_category)}
              </span>
            ) : null}
          </div>
          <table className="mt-2 w-full text-left text-[11px] text-slate-600">
            <tbody>
              {Object.entries(cell.categories)
                .sort((a, b) => b[1] - a[1])
                .map(([cat, n]) => (
                  <tr key={cat}>
                    <td className="py-0.5 pr-2">{categoryLabel(cat)}</td>
                    <td className="py-0.5 text-right font-semibold tabular-nums">
                      {n}
                    </td>
                  </tr>
                ))}
            </tbody>
          </table>
          {cell.top_priority != null ? (
            <p className="mt-2 text-[11px] text-slate-500">
              Highest priority in cell: {cell.top_priority}
            </p>
          ) : null}
          <p className="mt-2 text-[11px] text-slate-400">
            {cell.radius_m != null
              ? `Cell radius ≈ ${Math.round(cell.radius_m)} m`
              : `Cell spans ≈ ${cell.grid ?? "?"}° (≈ ${Math.round(radiusM)} m half-diagonal)`}
          </p>
        </div>
      </Popup>
    </Circle>
  );
}

const METERS_PER_DEGREE = 111_320;

/**
 * Half-diagonal of a square grid cell, derived from the cell's own reported
 * `grid` size in degrees. Used only when the endpoint supplies no `radius_m`.
 */
function gridCellRadiusM(cell: HotspotCell): number {
  if (cell.grid == null || cell.grid <= 0) return 200;
  return (cell.grid * METERS_PER_DEGREE * Math.SQRT2) / 2;
}

/** Metres -> Leaflet pixels at 60% of a 256px tile at zoom 13. */
function metersToPixels(meters: number, latitude: number): number {
  const METERS_PER_PIXEL =
    (156543.03392 * Math.cos((latitude * Math.PI) / 180)) / 2 ** 13;
  return Math.max(20, Math.min(400, meters / METERS_PER_PIXEL));
}

function IssueLayer({ issues }: { issues: Issue[] }) {
  return (
    <>
      {issues.map((issue) => (
        <Marker
          key={issue.id}
          position={[issue.latitude, issue.longitude]}
          icon={makeIcon(issue.severity, issue.cluster_size)}
        >
          <Popup>
            <div className="min-w-[220px]">
              <div className="flex items-center justify-between gap-2">
                <p className="text-sm font-bold text-slate-900">
                  #{issue.id} · {categoryLabel(issue.category)}
                </p>
                <SeverityBadge severity={issue.severity} showLabel={false} />
              </div>
              <p className="mt-1 line-clamp-2 text-xs text-slate-500">
                {issue.description || issue.address || "No description"}
              </p>
              <div className="mt-2 flex flex-wrap items-center gap-2">
                <StatusBadge status={issue.status} />
                <PriorityBadge
                  score={issue.priority}
                  priorityClass={issue.priority_class}
                />
                {issue.cluster_size > 1 ? (
                  <span className="rounded-full bg-amber-50 px-2 py-0.5 text-[11px] font-semibold text-amber-700">
                    {formatCount(issue.cluster_size)} reports
                  </span>
                ) : null}
              </div>
              <p className="mt-1.5 text-[11px] text-slate-400">
                {relativeTime(issue.created_at)}
                {issue.is_master ? "" : " · supporting report"}
              </p>
              <Link
                to={`/issues/${issue.id}`}
                className="mt-2 inline-flex w-full items-center justify-center rounded-lg bg-slate-900 px-3 py-1.5 text-xs font-semibold text-white hover:bg-slate-800"
              >
                Open issue detail
              </Link>
            </div>
          </Popup>
        </Marker>
      ))}
    </>
  );
}

function MapView({
  issues,
  cells,
  mode,
  showResolved,
}: {
  issues: Issue[];
  cells: HotspotCell[];
  mode: LayerMode;
  showResolved: boolean;
}) {
  const markers = useMemo(
    () => issues.filter((i) => isValidCoord(i.latitude, i.longitude)),
    [issues],
  );
  const validCells = useMemo(
    () => cells.filter((c) => isValidCoord(c.latitude, c.longitude)),
    [cells],
  );
  // Every hook must run on every render, so this is derived before the
  // empty-state early return below: toggling between an empty and populated
  // dataset must not change the number of hooks called.
  const points = useMemo(
    () =>
      mode === "hotspots"
        ? validCells.map((c) => [c.latitude, c.longitude] as [number, number])
        : markers.map((m) => [m.latitude, m.longitude] as [number, number]),
    [mode, markers, validCells],
  );
  const maxReports = useMemo(
    () => validCells.reduce((m, c) => Math.max(m, c.report_count), 0),
    [validCells],
  );

  const hasNothing =
    mode === "hotspots" ? validCells.length === 0 : markers.length === 0;

  if (hasNothing) {
    return (
      <div className="rounded-2xl border border-slate-200 bg-white p-6">
        <EmptyState
          title={
            mode === "hotspots"
              ? "No hotspot cells available"
              : "No map markers available"
          }
          description={
            mode === "hotspots"
              ? "Hotspots are aggregated from open master issues with valid coordinates."
              : showResolved
                ? "No issues with valid coordinates were returned."
                : "No open issues with valid coordinates were returned. Toggle resolved issues to include them."
          }
        />
      </div>
    );
  }

  return (
    <div className="relative overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm">
      <MapContainer
        center={DEFAULT_CENTER}
        zoom={12}
        scrollWheelZoom
        className="h-[460px] w-full sm:h-[520px] lg:h-[600px]"
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />
        <FitBounds points={points} />
        {mode === "hotspots" ? (
          validCells.map((cell) => (
            <HotspotCircle
              key={`${cell.latitude},${cell.longitude}`}
              cell={cell}
              maxReports={maxReports}
            />
          ))
        ) : (
          <IssueLayer issues={markers} />
        )}
      </MapContainer>
      <div className="pointer-events-none absolute bottom-6 left-6 hidden sm:block">
        <div className="pointer-events-auto">
          <Legend mode={mode} />
        </div>
      </div>
    </div>
  );
}

function ModeToggle({
  mode,
  onChange,
}: {
  mode: LayerMode;
  onChange: (m: LayerMode) => void;
}) {
  const options: { value: LayerMode; label: string }[] = [
    { value: "issues", label: "Individual issues" },
    { value: "hotspots", label: "Hotspots" },
  ];
  return (
    <div
      role="tablist"
      aria-label="Map layer"
      className="inline-flex rounded-xl border border-slate-300 bg-white p-0.5"
    >
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          role="tab"
          aria-selected={mode === o.value}
          onClick={() => onChange(o.value)}
          className={`rounded-[10px] px-3.5 py-1.5 text-sm font-medium transition-colors ${
            mode === o.value
              ? "bg-brand-600 text-white"
              : "text-slate-600 hover:bg-slate-50"
          }`}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

export default function IssueMapPage() {
  const [showResolved, setShowResolved] = useState(false);
  const [mode, setMode] = useState<LayerMode>("issues");
  const [category, setCategory] = useState<IssueCategory | "">("");

  // Category options come from the backend so a new category appears here
  // without a frontend change; the compiled-in list is only a fallback.
  const { meta } = useMeta();
  const categoryOptions = meta?.categories ?? CATEGORIES.map((c) => ({ value: c, label: categoryLabel(c) }));

  // Both layers are always fetched so switching between them is instant; the
  // map only ever draws one.
  const issuesQuery = useAsync(
    () =>
      fetchIssues({
        scope: "masters",
        category: category || undefined,
        includeResolved: showResolved,
      }).then((r) => r.issues),
    [showResolved, category],
  );
  const hotspotsQuery = useAsync(
    () =>
      fetchHotspots({
        category: category || undefined,
        includeResolved: showResolved,
      }),
    [showResolved, category],
  );

  const issues = issuesQuery.data ?? [];
  const hotspots = hotspotsQuery.data;

  // Only the active layer's request drives the error/loading state.
  const active = mode === "hotspots" ? hotspotsQuery : issuesQuery;
  const error = active.error;
  const loading = active.loading && active.data == null;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-xl font-bold tracking-tight text-slate-900">
            Live issue map
          </h2>
          <p className="mt-1 text-sm text-slate-500">
            Actual report coordinates from the backend
            {mode === "issues" ? ", colored by severity." : ", aggregated into grid cells."}
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <select
            value={category}
            onChange={(e) => setCategory(e.target.value as IssueCategory | "")}
            aria-label="Filter by category"
            className="h-9 rounded-xl border border-slate-300 bg-white px-3 text-sm text-slate-700 focus:border-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-600/20"
          >
            <option value="">All categories</option>
            {categoryOptions.map((c) => (
              <option key={c.value} value={c.value}>
                {c.label}
              </option>
            ))}
          </select>
          <ModeToggle mode={mode} onChange={setMode} />
          <button
            type="button"
            onClick={() => setShowResolved((v) => !v)}
            className={`inline-flex h-9 items-center gap-2 rounded-xl border px-3.5 text-sm font-medium transition-colors ${
              showResolved
                ? "border-brand-300 bg-brand-50 text-brand-700"
                : "border-slate-300 bg-white text-slate-600 hover:bg-slate-50"
            }`}
          >
            <span
              className={`h-2 w-2 rounded-full ${showResolved ? "bg-brand-500" : "bg-slate-300"}`}
            />
            Show resolved &amp; rejected
          </button>
        </div>
      </div>

      {error ? (
        <ErrorState message={error} onRetry={active.reload} />
      ) : loading ? (
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <CardSkeleton />
          <div className="lg:col-span-2 rounded-2xl border border-slate-200 bg-white p-5">
            <div className="h-[520px] animate-pulse rounded-xl bg-slate-100" />
          </div>
        </div>
      ) : (
        <>
          {mode === "issues" ? (
            <p className="text-sm text-slate-500">
              Showing{" "}
              <span className="font-semibold text-slate-700">
                {formatCount(issues.length)}
              </span>{" "}
              issue{issues.length === 1 ? "" : "s"} with valid coordinates.
            </p>
          ) : (
            hotspots && (
              <div className="text-sm text-slate-500">
                <p>
                  <span className="font-semibold text-slate-700">
                    {formatCount(hotspots.hotspots.length)}
                  </span>{" "}
                  hotspot cell{hotspots.hotspots.length === 1 ? "" : "s"} from{" "}
                  <span className="font-semibold text-slate-700">
                    {formatCount(hotspots.total_masters)}
                  </span>{" "}
                  open physical problem
                  {hotspots.total_masters === 1 ? "" : "s"}.
                </p>
                {/* The method label is rendered verbatim from the backend so the
                    UI cannot imply a learned anomaly model that does not exist. */}
                <p className="mt-1 text-xs text-slate-400">
                  {hotspots.method_honest_label} Spatial backend:{" "}
                  <span className="font-medium text-slate-500">
                    {hotspots.spatial_backend.engine}
                  </span>
                  {!isPostgisActive(hotspots.spatial_backend) ? (
                    <>
                      {" · "}
                      {hotspots.spatial_backend.spatial_index}
                    </>
                  ) : null}
                  .
                </p>
                {hotspots.data_source_note ? (
                  <p className="mt-1 text-xs text-amber-700">
                    {hotspots.data_source_note}
                  </p>
                ) : null}
              </div>
            )
          )}

          <MapView
            issues={issues}
            cells={hotspots?.hotspots ?? []}
            mode={mode}
            showResolved={showResolved}
          />
        </>
      )}
    </div>
  );
}
