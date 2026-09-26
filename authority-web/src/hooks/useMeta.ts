import { useEffect, useState } from "react";
import { fetchMeta } from "../api/stats";
import { getErrorMessage } from "../api/client";
import type { MetaResponse } from "../types";

/**
 * `GET /authority/meta/` is immutable for the life of a deployment (enums,
 * departments, officers, the lifecycle table and the capability probes), so it
 * is fetched once per page load and shared by every consumer.
 *
 * Module-level cache rather than context: the payload is small, the request is
 * already authorised, and this keeps the hook usable from any page or component
 * without threading a provider through the tree.
 */
let cached: Promise<MetaResponse | null> | null = null;
let resolved: MetaResponse | null = null;

function load(): Promise<MetaResponse | null> {
  if (!cached) {
    cached = fetchMeta()
      .then((meta) => {
        resolved = meta;
        return meta;
      })
      .catch((err) => {
        // Do not cache a failure: a transient 500 should not poison the page for
        // the rest of the session.
        cached = null;
        throw err;
      });
  }
  return cached;
}

export interface MetaState {
  meta: MetaResponse | null;
  loading: boolean;
  error: string | null;
  /** Clears the cache and refetches (used by the "retry" affordance). */
  reload: () => void;
}

export function useMeta(): MetaState {
  const [meta, setMeta] = useState<MetaResponse | null>(resolved);
  const [loading, setLoading] = useState(resolved == null);
  const [error, setError] = useState<string | null>(null);
  const [tick, setTick] = useState(0);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    load()
      .then((res) => {
        if (cancelled) return;
        setMeta(res);
        setLoading(false);
      })
      .catch((err) => {
        if (cancelled) return;
        setError(getErrorMessage(err));
        setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [tick]);

  return {
    meta,
    loading,
    error,
    reload: () => {
      cached = null;
      setTick((t) => t + 1);
    },
  };
}

/**
 * Assignable department names, from the backend when available and falling back
 * to the compiled-in list only while `/meta/` is still in flight.
 */
export function departmentOptions(meta: MetaResponse | null): string[] {
  return meta?.departments.assignable ?? [];
}