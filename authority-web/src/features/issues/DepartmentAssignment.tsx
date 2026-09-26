import { useEffect, useState } from "react";
import { DEPARTMENTS, type Officer } from "../../types";
import { updateAssignment } from "../../api/issues";
import { getErrorMessage } from "../../api/client";
import { useToast } from "../../components/Toast";
import { SpinnerInline } from "../../components/Spinner";
import { formatDate } from "../../utils/format";

/**
 * Department + officer assignment.
 *
 * Officers come from `GET /authority/meta/` so a newly created staff account is
 * assignable immediately. Sending `officer_id: null` unassigns, which is the
 * only way back to "unassigned" -- there is no separate unassign call.
 */
export function DepartmentAssignment({
  issueId,
  department,
  assignedTo,
  assignedToName,
  assignedAt,
  officers,
  onChanged,
}: {
  issueId: number;
  department: string;
  assignedTo: number | null;
  assignedToName: string | null;
  assignedAt: string | null;
  officers: Officer[];
  onChanged: () => void;
}) {
  const toast = useToast();
  const [dept, setDept] = useState(department);
  const [officer, setOfficer] = useState(
    assignedTo == null ? "" : String(assignedTo),
  );
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Re-sync when the issue is refetched (e.g. after a transition elsewhere).
  useEffect(() => setDept(department), [department]);
  useEffect(
    () => setOfficer(assignedTo == null ? "" : String(assignedTo)),
    [assignedTo],
  );

  const dirty = dept !== department || officer !== (assignedTo == null ? "" : String(assignedTo));

  const save = async () => {
    setSaving(true);
    setError(null);
    try {
      const result = await updateAssignment(issueId, {
        department: dept,
        // `null` is meaningful here: it unassigns. `""` is not sent.
        officer_id: officer === "" ? null : Number(officer),
      });
      toast.success(
        result.assigned_to_name
          ? `Assigned to ${result.department} · ${result.assigned_to_name}.`
          : `Assigned to ${result.department}.`,
      );
      onChanged();
    } catch (err) {
      const msg = getErrorMessage(err);
      setError(msg);
      toast.error(msg);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
      <h3 className="text-sm font-semibold text-slate-800">Assignment</h3>
      <p className="mt-0.5 text-xs text-slate-500">
        Route this issue to a department and a staff officer.
      </p>

      <div className="mt-3 space-y-2">
        <label className="block">
          <span className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">
            Department
          </span>
          <select
            value={dept}
            onChange={(e) => setDept(e.target.value)}
            className="mt-1 h-10 w-full rounded-xl border border-slate-300 bg-white px-3 text-sm text-slate-900 focus:border-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-600/20"
          >
            {DEPARTMENTS.map((d) => (
              <option key={d} value={d}>
                {d}
              </option>
            ))}
          </select>
        </label>

        <label className="block">
          <span className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">
            Officer
          </span>
          <select
            value={officer}
            onChange={(e) => setOfficer(e.target.value)}
            disabled={officers.length === 0}
            className="mt-1 h-10 w-full rounded-xl border border-slate-300 bg-white px-3 text-sm text-slate-900 disabled:bg-slate-50 disabled:text-slate-400 focus:border-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-600/20"
          >
            <option value="">Unassigned</option>
            {officers.map((o) => (
              <option key={o.id} value={String(o.id)}>
                {o.name}
              </option>
            ))}
          </select>
        </label>
      </div>

      {officers.length === 0 ? (
        <p className="mt-2 rounded-lg bg-amber-50 px-3 py-2 text-[11px] text-amber-700">
          The officer list is empty, so an individual officer cannot be assigned.
          This happens when the deployment publishes no staff directory, or when
          it has no staff accounts yet. Department assignment below still works.
        </p>
      ) : null}

      <div className="mt-3 flex items-center gap-2">
        <button
          type="button"
          onClick={save}
          disabled={!dirty || saving}
          className="inline-flex h-10 items-center gap-2 rounded-xl bg-brand-600 px-4 text-sm font-semibold text-white hover:bg-brand-700 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {saving ? <SpinnerInline /> : null}
          Save
        </button>
        {assignedToName ? (
          <p className="text-[11px] text-slate-400">
            Currently {assignedToName}
            {assignedAt ? ` · since ${formatDate(assignedAt)}` : ""}
          </p>
        ) : (
          <p className="text-[11px] text-amber-600">Currently unassigned</p>
        )}
      </div>

      {error ? (
        <p className="mt-2 rounded-lg bg-rose-50 px-3 py-2 text-xs text-rose-600">
          {error}
        </p>
      ) : null}
      <p className="mt-2 text-[11px] text-slate-400">
        Staff-only update via the authority API.
      </p>
    </div>
  );
}
