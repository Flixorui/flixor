import { useCallback, useEffect, useRef, useState } from 'react';
import { getStreams, type StremioAddonStreams, type StremioContentIdentity } from '@/stremio';

export interface StremioSourcesState {
  /** One entry per addon that has answered, in addon priority order once loading ends. */
  results: StremioAddonStreams[];
  loading: boolean;
  /** False until the current request has finished, so "nothing found" can wait for it. */
  settled: boolean;
  /** Set when the request as a whole failed. Per-addon failures are in `results`. */
  error: string | null;
  reload: () => void;
}

/**
 * Streams for a title, filling in as each addon answers. Pass null to stay idle.
 * `seedResults` are used instead of a first fetch, for results fetched elsewhere.
 */
export function useStremioSources(
  identity: StremioContentIdentity | null,
  seedResults?: StremioAddonStreams[] | null,
): StremioSourcesState {
  const [results, setResults] = useState<StremioAddonStreams[]>([]);
  const [loading, setLoading] = useState(false);
  const [settled, setSettled] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [revision, setRevision] = useState(0);

  const identityRef = useRef(identity);
  identityRef.current = identity;
  const seedRef = useRef(seedResults);
  seedRef.current = seedResults;
  const reloaded = useRef(false);

  const identityKey = identity ? `${identity.requestType}|${identity.requestId}` : null;

  useEffect(() => {
    setResults([]);
    setError(null);
    setSettled(false);
    const current = identityRef.current;
    if (!identityKey || !current) {
      reloaded.current = false;
      setLoading(false);
      return;
    }

    const seed = seedRef.current;
    if (seed && seed.length > 0 && !reloaded.current) {
      setResults(seed);
      setLoading(false);
      setSettled(true);
      return;
    }

    const controller = new AbortController();
    setLoading(true);
    getStreams(current, {
      signal: controller.signal,
      onAddonResult(result) {
        setResults((previous) => [...previous, result]);
      },
    })
      .then(setResults)
      .catch((err) => {
        if (err?.name !== 'AbortError') setError(err?.message || 'Could not load sources');
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setLoading(false);
          setSettled(true);
        }
      });
    return () => controller.abort();
  }, [identityKey, revision]);

  const reload = useCallback(() => {
    reloaded.current = true;
    setRevision((value) => value + 1);
  }, []);

  return { results, loading, settled, error, reload };
}
