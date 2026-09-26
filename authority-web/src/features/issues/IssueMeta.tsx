import type { IssueDetail, Officer } from "../../types";
import { formatDate } from "../../utils/format";
import { DepartmentAssignment } from "./DepartmentAssignment";

export function IssueMeta({
  issue,
  officers,
  onChanged,
}: {
  issue: IssueDetail;
  officers: Officer[];
  onChanged: () => void;
}) {
  return (
    <div className="space-y-4">
      <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
        <h3 className="text-sm font-semibold text-slate-800">Report metadata</h3>
        <dl className="mt-3 space-y-2">
          {issue.reporter_email ? (
            <MetaRow term="Reporter" value={issue.reporter_email} />
          ) : null}
          <MetaRow term="Description" value={issue.description || "No description provided."} />
          <MetaRow term="Address" value={issue.address || "—"} />
          <MetaRow
            term="GPS"
            value={`${issue.latitude?.toFixed(6)}, ${issue.longitude?.toFixed(6)}`}
          />
          <MetaRow term="Created" value={formatDate(issue.created_at)} />
          <MetaRow term="Last updated" value={formatDate(issue.updated_at)} />
          {issue.resolved_at ? (
            <MetaRow term="Resolved" value={formatDate(issue.resolved_at)} />
          ) : null}
        </dl>
      </div>

      <DepartmentAssignment
        issueId={issue.id}
        department={issue.department}
        assignedTo={issue.assigned_to ?? null}
        assignedToName={issue.assigned_to_name ?? null}
        assignedAt={issue.assigned_at ?? null}
        officers={officers}
        onChanged={onChanged}
      />

      <a
        href={`https://www.openstreetmap.org/?mlat=${issue.latitude}&mlon=${issue.longitude}#map=16/${issue.latitude}/${issue.longitude}`}
        target="_blank"
        rel="noopener noreferrer"
        className="flex items-center justify-center gap-2 rounded-xl border border-slate-200 bg-white px-4 py-2.5 text-sm font-semibold text-brand-700 shadow-sm transition-colors hover:bg-brand-50"
      >
        Open location in OpenStreetMap
      </a>
    </div>
  );
}

function MetaRow({ term, value }: { term: string; value: string }) {
  return (
    <div className="flex items-start gap-2 text-sm">
      <dt className="w-24 flex-none text-xs font-semibold uppercase tracking-wide text-slate-500">
        {term}
      </dt>
      <dd className="min-w-0 flex-1 break-words text-slate-700">{value}</dd>
    </div>
  );
}