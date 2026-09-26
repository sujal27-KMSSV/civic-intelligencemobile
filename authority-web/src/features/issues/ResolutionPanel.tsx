import { useRef, useState, type FormEvent } from "react";
import { resolveIssue } from "../../api/issues";
import { getErrorMessage } from "../../api/client";
import { useToast } from "../../components/Toast";
import { SpinnerInline } from "../../components/Spinner";
import { IconUpload } from "../../components/icons";
import { formatPercent } from "../../utils/format";
import { resolveMediaUrl } from "../../utils/media";
import type { ImageSimilarityResult, Issue } from "../../types";

function localInterpretation(sim: number): { label: string; cls: string; hint: string } {
  if (sim >= 0.92)
    return {
      label: "Identical scene",
      cls: "bg-rose-100 text-rose-700",
      hint: "The after photo still looks like the original scene — likely NOT visually fixed.",
    };
  if (sim >= 0.7)
    return {
      label: "Similar scene",
      cls: "bg-amber-100 text-amber-700",
      hint: "The after photo shares much of the original scene — verify the fix visually.",
    };
  return {
    label: "Different scene",
    cls: "bg-emerald-100 text-emerald-700",
    hint: "The scene has changed substantially compared to the original report.",
  };
}

const INTERPRETATION_STYLE: Record<string, string> = {
  identical: "bg-rose-100 text-rose-700",
  similar: "bg-amber-100 text-amber-700",
  different: "bg-emerald-100 text-emerald-700",
  unavailable: "bg-slate-100 text-slate-500",
};

const INTERPRETATION_LABEL: Record<string, string> = {
  identical: "Identical scene",
  similar: "Similar scene",
  different: "Different scene",
  unavailable: "Not comparable",
};

function ImageFrame({ src, label }: { src: string | undefined; label: string }) {
  return (
    <div className="flex flex-col gap-2">
      <div className="flex h-56 items-center justify-center overflow-hidden rounded-xl border border-slate-200 bg-slate-100">
        {src ? (
          <img
            src={src}
            alt={label}
            className="h-full w-full object-cover"
          />
        ) : (
          <span className="text-sm text-slate-400">No image recorded</span>
        )}
      </div>
      <p className="text-center text-[11px] font-semibold uppercase tracking-wide text-slate-500">
        {label}
      </p>
    </div>
  );
}

export function ResolutionPanel({
  issue,
  onChanged,
}: {
  issue: Issue;
  onChanged: () => void;
}) {
  const toast = useToast();
  const [file, setFile] = useState<File | null>(null);
  const [notes, setNotes] = useState("");
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);
  // The resolve response carries the full server-side verification payload, so
  // the result can be shown the moment the upload succeeds instead of waiting
  // for the refetch that `onChanged` triggers.
  const [justVerified, setJustVerified] =
    useState<ImageSimilarityResult | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const canUpload =
    issue.status === "in_progress" || issue.status === "resolved";
  const before = resolveMediaUrl(issue.image_url);
  const after = resolveMediaUrl(issue.resolution_image_url);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (!file) {
      setUploadError("Select a completion photo first.");
      return;
    }
    setUploading(true);
    setUploadError(null);
    const form = new FormData();
    form.append("image", file);
    if (notes.trim()) form.append("notes", notes.trim());
    try {
      const result = await resolveIssue(issue.id, form);
      if (result.image_similarity) setJustVerified(result.image_similarity);
      toast.success("Resolution recorded with AI verification.");
      setFile(null);
      setNotes("");
      if (fileInputRef.current) fileInputRef.current.value = "";
      onChanged();
    } catch (err) {
      const msg = getErrorMessage(err);
      setUploadError(msg);
      toast.error(msg);
    } finally {
      setUploading(false);
    }
  };

  // Prefer the freshly returned verification, then the value the refetched
  // issue carries, and fall back to a locally-bucketed reading of that scalar.
  const sim = justVerified?.similarity ?? issue.resolution_similarity ?? null;
  const interp =
    justVerified != null
      ? {
          label:
            INTERPRETATION_LABEL[justVerified.interpretation] ??
            justVerified.interpretation,
          cls:
            INTERPRETATION_STYLE[justVerified.interpretation] ??
            INTERPRETATION_STYLE.unavailable,
          hint:
            justVerified.reason ??
            (justVerified.interpretation === "unavailable"
              ? "The two images could not be compared."
              : "The after photo shares much of the original scene — verify the fix visually."),
        }
      : typeof issue.resolution_similarity === "number"
        ? localInterpretation(issue.resolution_similarity)
        : null;
  // The method is only known for the upload that produced it (the backend does
  // not persist it), so after a reload fall back to naming the family of
  // measurement rather than claiming a specific algorithm.
  const methodLabel =
    justVerified?.method ?? "perceptual image similarity";

  return (
    <div id="resolution" className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h3 className="text-sm font-semibold text-slate-800">
            Resolution evidence
          </h3>
          <p className="text-xs text-slate-500">
            BEFORE / AFTER comparison with AI verification
          </p>
        </div>
        {issue.status === "resolved" ? (
          <span className="rounded-full bg-emerald-100 px-3 py-1 text-[11px] font-semibold text-emerald-700">
            Resolved {issue.resolved_at ? `· ${new Date(issue.resolved_at).toLocaleDateString()}` : ""}
          </span>
        ) : null}
      </div>

      <div className="mt-4 grid grid-cols-1 gap-5 md:grid-cols-2">
        <ImageFrame src={before} label="BEFORE · original report" />

        {after ? (
          <ImageFrame src={after} label="AFTER · resolution photo" />
        ) : (
          <form onSubmit={submit} className="flex flex-col gap-3">
            <div className="flex flex-1 flex-col items-center justify-center gap-2 rounded-xl border-2 border-dashed border-slate-300 bg-slate-50 p-6">
              <div className="text-slate-400">
                <IconUpload width={28} height={28} />
              </div>
              <p className="text-sm text-slate-500">
                {file ? file.name : "Select a completion photo"}
              </p>
              <input
                ref={fileInputRef}
                type="file"
                accept="image/*"
                onChange={(e) => setFile(e.target.files?.[0] ?? null)}
                className="text-xs text-slate-500 file:mr-3 file:rounded-lg file:border-0 file:bg-brand-600 file:px-3 file:py-1.5 file:text-xs file:font-semibold file:text-white"
              />
              {!canUpload ? (
                <p className="text-center text-xs text-slate-400">
                  Issue must be <strong>in progress</strong> before it can be resolved.
                </p>
              ) : null}
            </div>
            <textarea
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              rows={2}
              placeholder="Resolution notes (optional) — what the authority did…"
              className="rounded-xl border border-slate-300 px-3 py-2 text-sm focus:border-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-600/20"
            />
            {uploadError ? (
              <p className="rounded-lg bg-rose-50 px-3 py-2 text-xs text-rose-600">
                {uploadError}
              </p>
            ) : null}
            <button
              type="submit"
              disabled={uploading || !canUpload || !file}
              className="inline-flex h-10 items-center justify-center gap-2 rounded-xl bg-brand-600 px-4 text-sm font-semibold text-white hover:bg-brand-700 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {uploading ? <SpinnerInline /> : <IconUpload width={15} height={15} />}
              {uploading ? "Verifying…" : "Record resolution"}
            </button>
          </form>
        )}
      </div>

      {sim != null && interp ? (
        <div className="mt-5 rounded-xl border border-slate-100 bg-slate-50 p-4">
          <p className="text-[11px] font-bold uppercase tracking-wider text-slate-500">
            AI verification
          </p>
          <div className="mt-2 flex flex-wrap items-center gap-3">
            <span className="text-3xl font-bold tracking-tight text-slate-900">
              {formatPercent(sim)}
            </span>
            <span className={`rounded-full px-3 py-1 text-xs font-semibold ${interp.cls}`}>
              {interp.label}
            </span>
            <span className="text-xs text-slate-400">
              {methodLabel} · higher = same scene
            </span>
          </div>
          <p className="mt-2 text-xs leading-relaxed text-slate-500">
            {interp.hint} This measurement is an honest heuristic, not a learned
            model, and never auto-resolves an issue.
          </p>
        </div>
      ) : null}

      {issue.resolution_notes ? (
        <div className="mt-4 rounded-xl bg-slate-50 px-4 py-3">
          <p className="text-[11px] font-bold uppercase tracking-wider text-slate-500">
            Authority notes
          </p>
          <p className="mt-1 whitespace-pre-wrap text-sm text-slate-700">
            {issue.resolution_notes}
          </p>
        </div>
      ) : null}
    </div>
  );
}