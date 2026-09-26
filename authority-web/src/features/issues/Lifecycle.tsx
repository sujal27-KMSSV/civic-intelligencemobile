import { useState } from "react";
import { ALLOWED_TRANSITIONS, STATUS_LABELS, type IssueStatus } from "../../types";
import { transitionIssue } from "../../api/issues";
import { getErrorMessage } from "../../api/client";
import { useToast } from "../../components/Toast";
import { SpinnerInline } from "../../components/Spinner";
import { IconCheck } from "../../components/icons";

const FLOW: IssueStatus[] = [
  "reported",
  "verified",
  "assigned",
  "in_progress",
  "resolved",
];

export function Lifecycle({
  status,
  issueId,
  allowedTransitions,
  onChanged,
}: {
  status: IssueStatus;
  issueId: number;
  /**
   * The backend's per-issue `allowed_transitions`. Preferred over the compiled-in
   * table so the UI can never offer a transition the server would reject; falls
   * back to the static list only if the field is absent.
   */
  allowedTransitions?: IssueStatus[];
  onChanged: () => void;
}) {
  const toast = useToast();
  const [busyTarget, setBusyTarget] = useState<IssueStatus | null>(null);
  const [error, setError] = useState<string | null>(null);

  const currentIndex = FLOW.indexOf(status);
  const source = allowedTransitions ?? ALLOWED_TRANSITIONS[status] ?? [];
  // `resolved` is never offered here: reaching it requires the resolution
  // action with BEFORE/AFTER evidence, which the panel below handles.
  const allowed = source.filter((t) => t !== "resolved");

  const handleTransition = async (target: IssueStatus) => {
    setBusyTarget(target);
    setError(null);
    try {
      await transitionIssue(issueId, target);
      toast.success(`Moved issue to ${STATUS_LABELS[target]}.`);
      onChanged();
    } catch (err) {
      setError(getErrorMessage(err));
      toast.error(getErrorMessage(err));
    } finally {
      setBusyTarget(null);
    }
  };

  return (
    <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-semibold text-slate-800">Issue lifecycle</h3>
        {status === "in_progress" ? (
          <span className="hidden rounded-full bg-blue-50 px-3 py-1 text-[11px] font-medium text-blue-700 sm:block">
            Next step: upload resolution evidence
          </span>
        ) : null}
      </div>

      {/* Stepper */}
      <ol className="mt-5 grid grid-cols-5 gap-1">
        {FLOW.map((step, i) => {
          const isCurrent = status === step;
          const reached = currentIndex >= i && status !== "rejected";
          return (
            <li key={step} className="flex flex-col items-center gap-1.5 text-center">
              <span
                className={`flex h-8 w-8 items-center justify-center rounded-full text-xs font-bold ${
                  reached && status !== "resolved"
                    ? "bg-brand-600 text-white"
                    : status === "resolved" && i === 4
                      ? "bg-emerald-500 text-white"
                      : "bg-slate-100 text-slate-400"
                }`}
              >
                {i === 4 && status === "resolved" ? (
                  <IconCheck width={14} height={14} />
                ) : (
                  i + 1
                )}
              </span>
              <span
                className={`text-[10px] font-medium uppercase tracking-wide sm:text-[11px] ${
                  isCurrent ? "text-slate-900" : "text-slate-400"
                }`}
              >
                {STATUS_LABELS[step]}
              </span>
            </li>
          );
        })}
      </ol>

      {status === "rejected" ? (
        <div className="mt-3 rounded-xl bg-neutral-100 px-4 py-3 text-sm text-neutral-600">
          This issue was <strong>rejected</strong>. It can be reopened to{" "}
          <strong>reported</strong> when new information arrives.
        </div>
      ) : null}

      {/* Transition actions */}
      {allowed.length > 0 && currentIndex >= 0 ? (
        <div className="mt-5 border-t border-slate-100 pt-4">
          <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">
            Allowed transitions
          </p>
          <div className="mt-2 flex flex-wrap items-center gap-2">
            {allowed.map((target) => (
              <button
                key={target}
                type="button"
                disabled={busyTarget !== null}
                onClick={() => handleTransition(target)}
                className={`inline-flex h-9 items-center gap-2 rounded-xl px-3.5 text-sm font-semibold transition-colors disabled:opacity-60 ${
                  target === "rejected"
                    ? "border border-neutral-300 text-neutral-600 hover:bg-neutral-100"
                    : "bg-slate-900 text-white hover:bg-slate-800"
                }`}
              >
                {busyTarget === target ? <SpinnerInline /> : null}
                Mark {STATUS_LABELS[target]}
              </button>
            ))}
            {status === "in_progress" ? (
              <button
                type="button"
                disabled
                title="Resolving requires photo evidence"
                className="inline-flex h-9 cursor-not-allowed items-center rounded-xl bg-emerald-100 px-3.5 text-sm font-semibold text-emerald-400"
              >
                Mark Resolved
              </button>
            ) : null}
          </div>
          {error ? (
            <p className="mt-2 rounded-lg bg-rose-50 px-3 py-2 text-xs text-rose-600">
              {error}
            </p>
          ) : null}
        </div>
      ) : null}

      {status === "resolved" ? (
        <div className="mt-4 rounded-xl bg-emerald-50 px-4 py-3 text-sm text-emerald-700">
          This issue is <strong>resolved</strong>. Use the resolution panel to
          re-open it or re-upload evidence.
        </div>
      ) : null}
    </div>
  );
}