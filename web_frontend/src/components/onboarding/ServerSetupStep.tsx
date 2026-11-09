import { useCallback, useEffect, useRef, useState } from 'react';
import { apiClient } from '@/services/api';
import { adoptPlexServer, refreshPlexServers } from '@/services/plexServers';

type StepProps = { title: string; subtitle: string; description: string };

type Server = { id: string; name: string; owned: boolean; isActive: boolean };

type Endpoint = {
  uri: string;
  local: boolean;
  relay: boolean;
  IPv6?: boolean;
  isPreferred?: boolean;
  isCurrent?: boolean;
};

type EndpointResult = { status: 'testing' } | { status: 'ok'; ms: number } | { status: 'failed' };

const TYPE_ORDER = { Local: 0, Remote: 1, Relay: 2 };

function endpointType(endpoint: Endpoint): keyof typeof TYPE_ORDER {
  if (endpoint.relay) return 'Relay';
  return endpoint.local ? 'Local' : 'Remote';
}

export default function ServerSetupStep({ title, subtitle, description }: StepProps) {
  const [servers, setServers] = useState<Server[] | null>(null);
  const [loadError, setLoadError] = useState(false);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [endpoints, setEndpoints] = useState<Endpoint[]>([]);
  const [results, setResults] = useState<Record<string, EndpointResult>>({});
  const [chosenUri, setChosenUri] = useState<string | null>(null);
  const [testing, setTesting] = useState(false);
  const [testError, setTestError] = useState<string | null>(null);
  // Bumped to abandon a test run when another server is picked or the step closes.
  const runRef = useRef(0);

  const testServer = useCallback(async (serverId: string) => {
    const run = ++runRef.current;
    const isStale = () => runRef.current !== run;
    setSelectedId(serverId);
    setEndpoints([]);
    setResults({});
    setChosenUri(null);
    setTestError(null);
    setTesting(true);

    let prior: string | undefined;
    try {
      await apiClient.plexSetCurrentServer(serverId);
      adoptPlexServer(serverId);

      const response = await apiClient.plexServerConnections(serverId);
      const all: Endpoint[] = response.connections || [];
      const list = all.filter((c) => !c.IPv6);
      prior = list.find((c) => c.isPreferred || c.isCurrent)?.uri;
      if (isStale()) return;
      setEndpoints(list);
      setResults(Object.fromEntries(list.map((c) => [c.uri, { status: 'testing' } as EndpointResult])));

      // One at a time: the backend saves each endpoint it tests on the server record.
      const working: Array<{ endpoint: Endpoint; ms: number }> = [];
      for (const endpoint of list) {
        const started = performance.now();
        try {
          await apiClient.plexSetServerEndpoint(serverId, endpoint.uri, true);
          const ms = Math.round(performance.now() - started);
          working.push({ endpoint, ms });
          if (!isStale()) setResults((r) => ({ ...r, [endpoint.uri]: { status: 'ok', ms } }));
        } catch {
          if (!isStale()) setResults((r) => ({ ...r, [endpoint.uri]: { status: 'failed' } }));
        }
        if (isStale()) {
          if (prior) await apiClient.plexSetServerEndpoint(serverId, prior, false).catch(() => {});
          return;
        }
      }

      working.sort(
        (a, b) => TYPE_ORDER[endpointType(a.endpoint)] - TYPE_ORDER[endpointType(b.endpoint)] || a.ms - b.ms
      );
      const best = working[0]?.endpoint.uri;
      const final = best ?? prior;
      if (final) await apiClient.plexSetServerEndpoint(serverId, final, false);
      if (best) {
        adoptPlexServer(serverId, best);
        setChosenUri(best);
      } else {
        setTestError('None of this server\'s connections responded. You can continue and change it later in Settings.');
      }
    } catch {
      if (!isStale()) setTestError('Could not test this server. You can continue and change it later in Settings.');
    } finally {
      if (!isStale()) setTesting(false);
    }
  }, []);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        await refreshPlexServers();
        const list = await apiClient.plexServers();
        if (cancelled) return;
        const next: Server[] = Array.isArray(list) ? list : [];
        setServers(next);
        const initial = next.find((s) => s.isActive) ?? next.find((s) => s.owned) ?? next[0];
        if (initial) testServer(initial.id);
      } catch {
        if (!cancelled) setLoadError(true);
      }
    })();
    return () => {
      cancelled = true;
      runRef.current++;
    };
  }, [testServer]);

  async function chooseEndpoint(uri: string) {
    if (!selectedId) return;
    setTestError(null);
    try {
      await apiClient.plexSetServerEndpoint(selectedId, uri, false);
      adoptPlexServer(selectedId, uri);
      setChosenUri(uri);
    } catch {
      setTestError('Could not switch to that connection.');
    }
  }

  return (
    <div className="w-full max-w-lg">
      <h1 className="text-4xl font-extrabold text-white leading-tight whitespace-pre-line mb-3">{title}</h1>
      <h2 className="text-lg font-semibold text-white/60 mb-3">{subtitle}</h2>
      <p className="text-sm text-white/40 leading-relaxed mb-5">{description}</p>

      {loadError ? (
        <p role="alert" className="text-sm text-red-400">
          Could not load your Plex servers. You can continue and connect one later in Settings.
        </p>
      ) : servers === null ? (
        <p className="text-sm text-white/60">Loading your servers...</p>
      ) : servers.length === 0 ? (
        <p className="text-sm text-white/60">No Plex servers were found on this account.</p>
      ) : (
        <div className="space-y-3 max-h-[42vh] overflow-auto pr-1">
          <ul className="rounded-2xl border border-white/10 bg-white/[0.05] overflow-hidden">
            {servers.map((server) => {
              const selected = server.id === selectedId;
              return (
                <li key={server.id} className="border-b border-white/[0.08] last:border-b-0">
                  <button
                    type="button"
                    onClick={() => testServer(server.id)}
                    aria-pressed={selected}
                    className={`w-full flex items-center justify-between gap-3 px-4 py-3 text-left transition-colors ${selected ? 'bg-white/10' : 'hover:bg-white/[0.06]'}`}
                  >
                    <span className="min-w-0">
                      <span className="block text-sm font-semibold text-white truncate">{server.name}</span>
                      <span className="block text-xs text-white/40">{server.owned ? 'Owned' : 'Shared with you'}</span>
                    </span>
                    {selected && <span className="w-2.5 h-2.5 rounded-full bg-brand flex-shrink-0" aria-hidden="true" />}
                  </button>
                </li>
              );
            })}
          </ul>

          {endpoints.length > 0 && (
            <ul aria-label="Connections" className="rounded-2xl border border-white/10 bg-white/[0.05] overflow-hidden">
              {endpoints.map((endpoint) => {
                const result = results[endpoint.uri];
                const chosen = endpoint.uri === chosenUri;
                return (
                  <li key={endpoint.uri} className="flex items-center gap-3 px-4 py-2.5 border-b border-white/[0.08] last:border-b-0">
                    <span className="flex-1 min-w-0">
                      <span className="block text-xs font-semibold text-white">{endpointType(endpoint)}</span>
                      <span className="block text-[11px] text-white/40 truncate">{endpoint.uri}</span>
                    </span>
                    {result?.status === 'testing' && <span className="text-xs text-white/50">Testing...</span>}
                    {result?.status === 'failed' && <span className="text-xs text-red-400">Unreachable</span>}
                    {result?.status === 'ok' &&
                      (chosen ? (
                        <span className="text-xs font-semibold text-green-400">In use, {result.ms} ms</span>
                      ) : (
                        <button
                          type="button"
                          disabled={testing}
                          onClick={() => chooseEndpoint(endpoint.uri)}
                          className="text-xs font-semibold text-white/70 hover:text-white disabled:opacity-40"
                        >
                          Use ({result.ms} ms)
                        </button>
                      ))}
                  </li>
                );
              })}
            </ul>
          )}

          {testError && (
            <p role="alert" className="text-sm text-red-400">
              {testError}
            </p>
          )}
        </div>
      )}
    </div>
  );
}
