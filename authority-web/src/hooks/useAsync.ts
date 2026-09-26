import { useCallback, useEffect, useRef, useState } from "react";
import { getErrorMessage } from "../api/client";

/**
 * Small async-data hook with loading/error/refresh state. ``deps`` control
 * when the fetch re-runs; pass an inline fn that closes over latest values.
 */
export function useAsync<T>(
  fn: () => Promise<T>,
  deps: unknown[] = [],
): {
  data: T | null;
  loading: boolean;
  error: string | null;
  reload: () => void;
  setData: (updater: T | ((prev: T | null) => T | null)) => void;
} {
  const [data, setDataRaw] = useState<T | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [tick, setTick] = useState(0);
  const fnRef = useRef(fn);
  fnRef.current = fn;

  const reload = useCallback(() => setTick((t) => t + 1), []);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    fnRef
      .current()
      .then((res) => {
        if (cancelled) return;
        setDataRaw(res);
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
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tick, ...deps]);

  const setData = useCallback(
    (updater: T | ((prev: T | null) => T | null)) => {
      setDataRaw(updater as T);
    },
    [],
  );

  return { data, loading, error, reload, setData };
}

export function useDebouncedValue<T>(value: T, delay = 300): T {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const t = window.setTimeout(() => setDebounced(value), delay);
    return () => window.clearTimeout(t);
  }, [value, delay]);
  return debounced;
}