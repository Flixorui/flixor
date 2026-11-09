import { getStreams, type StremioAddonStreams, type StremioContentIdentity } from '@/stremio';

export interface LookupResult {
  results: StremioAddonStreams[];
  timedOut: boolean;
}

/**
 * All addons' sources within `limitMs`. `stopWhen` ends the wait early, once the
 * addons that have answered so far are good enough. The request is aborted on the
 * way out. A failure resolves with whatever was already known.
 */
export function lookupStreams(
  identity: StremioContentIdentity,
  options: {
    limitMs: number;
    signal?: AbortSignal;
    stopWhen?: (results: StremioAddonStreams[]) => boolean;
  },
): Promise<LookupResult> {
  return new Promise((resolve) => {
    const controller = new AbortController();
    const partial: StremioAddonStreams[] = [];
    let settled = false;

    const finish = (results: StremioAddonStreams[], timedOut: boolean) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      options.signal?.removeEventListener('abort', onAbort);
      controller.abort();
      resolve({ results, timedOut });
    };
    const onAbort = () => finish(partial, false);
    const timer = setTimeout(() => finish(partial, true), options.limitMs);
    options.signal?.addEventListener('abort', onAbort);

    getStreams(identity, {
      signal: controller.signal,
      onAddonResult: (result) => {
        partial.push(result);
        if (options.stopWhen?.(partial)) finish(partial, false);
      },
    }).then(
      (results) => finish(results, false),
      () => finish(partial, false),
    );
  });
}
