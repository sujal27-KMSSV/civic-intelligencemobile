import { useEffect, useState } from "react";
import { IconAlert } from "./icons";
import { resolveMediaUrl } from "../utils/media";

type MediaImageProps = {
  /** Raw value from the API: absolute, root-relative, or null when absent. */
  src: string | null | undefined;
  alt: string;
  /** Classes applied to the real <img> element. */
  className?: string;
  /** Classes applied to the placeholder box, so it matches its container. */
  placeholderClassName?: string;
  /**
   * "thumb" is a small square tile and gets an icon only; "panel" is a large
   * frame and gets an icon plus a short caption.
   */
  variant?: "thumb" | "panel";
  loading?: "lazy" | "eager";
};

/**
 * An <img> that never renders the browser's broken-image glyph.
 *
 * The backend stores `MEDIA_ROOT` on the container filesystem, so an issue row
 * can carry an `image_url` whose bytes no longer exist (HTTP 404) after a
 * redeploy. A bare <img> would then show the browser's torn-image icon, which
 * reads as a rendering bug and implies the UI is broken.
 *
 * A load error is therefore treated exactly like an absent image: both render the
 * same neutral placeholder. The component never hides that an image is missing,
 * it only avoids the misleading broken-icon affordance.
 */
export function MediaImage({
  src,
  alt,
  className,
  placeholderClassName,
  variant = "panel",
  loading,
}: MediaImageProps) {
  const url = resolveMediaUrl(src);
  const [failed, setFailed] = useState(false);

  // Reset when the row (and therefore the URL) changes, so a previously failed
  // image is retried if the caller re-renders with different data.
  useEffect(() => {
    setFailed(false);
  }, [url]);

  if (!url || failed) {
    return (
      <div
        role="img"
        aria-label={alt ? `${alt}: image unavailable` : "Image unavailable"}
        className={
          placeholderClassName ??
          "flex h-full w-full flex-col items-center justify-center gap-1.5 bg-slate-100 text-slate-400"
        }
      >
        <IconAlert width={variant === "thumb" ? 14 : 18} height={variant === "thumb" ? 14 : 18} />
        {variant === "panel" ? (
          <span className="px-2 text-center text-[11px] font-medium leading-tight">
            Image unavailable
          </span>
        ) : null}
      </div>
    );
  }

  return (
    <img
      src={url}
      alt={alt}
      className={className}
      loading={loading}
      onError={() => setFailed(true)}
    />
  );
}
