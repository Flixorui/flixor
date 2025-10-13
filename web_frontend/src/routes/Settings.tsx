import { useEffect, useState } from 'react';
import { loadSettings, saveSettings } from '@/state/settings';
import { forget } from '@/services/cache';
import { apiClient } from '@/services/api';
import { TraktAuth } from '@/components/TraktAuth';
import { getTraktTokens } from '@/services/trakt';

export default function Settings() {
  const initial = loadSettings();
  const [plexUrl, setPlexUrl] = useState(initial.plexBaseUrl || '');
  const [plexToken, setPlexToken] = useState(initial.plexToken || '');
  const [tmdbKey, setTmdbKey] = useState(initial.tmdbBearer || '');
  const [traktKey, setTraktKey] = useState(initial.traktClientId || '');
  const [plexTvToken, setPlexTvToken] = useState(initial.plexTvToken || '');
  const [watchlistProvider, setWatchlistProvider] = useState<'trakt'|'plex'>(initial.watchlistProvider || 'trakt');
  const [traktConnected, setTraktConnected] = useState<boolean>(!!initial.traktTokens);
  const [tmdbStatus, setTmdbStatus] = useState<string>('');
  const [plexStatus, setPlexStatus] = useState<string>('');
  const [auth, setAuth] = useState<{pinId?: number; code?: string}>({});
  const [servers, setServers] = useState<any[]>([]);
  const [selectedServer, setSelectedServer] = useState<any>(initial.plexServer);
  const [showEndpointsFor, setShowEndpointsFor] = useState<string | null>(null);
  const [endpoints, setEndpoints] = useState<Record<string, { uri: string; isCurrent: boolean; isPreferred: boolean }[]>>({});
  const [backendServers, setBackendServers] = useState<any[]>([]);

  useEffect(() => {
    saveSettings({ plexBaseUrl: plexUrl, plexToken, tmdbBearer: tmdbKey, traktClientId: traktKey, plexTvToken, watchlistProvider });
  }, [plexUrl, plexToken, tmdbKey, traktKey, plexTvToken, watchlistProvider]);

  useEffect(() => {
    const onTraktChanged = () => setTraktConnected(!!(getTraktTokens()));
    window.addEventListener('trakt-auth-changed', onTraktChanged);
    return () => window.removeEventListener('trakt-auth-changed', onTraktChanged);
  }, []);

  return (
    <div className="min-h-screen">
      <div className="max-w-3xl mx-auto p-6 space-y-8 pt-6">
      <section>
        <h2 className="text-xl font-semibold mb-2">Accounts</h2>
        <div className="grid gap-3">
          {/* Plex authentication via PIN */}
          <div className="rounded-lg ring-1 ring-white/10 p-4">
            <div className="flex items-center justify-between">
              <div>
                <div className="text-sm text-neutral-300">Plex Account</div>
                {selectedServer ? (
                  <div className="text-neutral-200 text-sm">Connected to {selectedServer?.name}</div>
                ) : initial.plexAccountToken ? (
                  <div className="text-neutral-400 text-sm">Authenticated. Select a server below.</div>
                ) : (
                  <div className="text-neutral-400 text-sm">Not signed in</div>
                )}
              </div>
              {!initial.plexAccountToken && !auth.pinId && (
                <button className="btn" disabled={selectedServer} onClick={async()=>{
                  const cid = initial.plexClientId || crypto.randomUUID();
                  saveSettings({ plexClientId: cid });
                  const pin:any = await apiClient.createPlexPin(cid);
                  setAuth({ pinId: pin.id, code: pin.code, url: pin.authUrl } as any);
                }}>Sign in with Plex</button>
              )}
              {initial.plexAccountToken && (
                <button className="btn" onClick={async()=>{
                  // Use backend to refresh and fetch servers
                  const cid = loadSettings().plexClientId || 'web';
                  try { await apiClient.syncPlexServers(cid); } catch {}
                  const backendServers = await apiClient.getServers();
                  setServers(backendServers || []);
                }}>Refresh Servers</button>
              )}
            </div>
            {auth.pinId && (
              <div className="mt-3 text-sm">
                <div className="mb-2">Enter this code at Plex: <span className="font-semibold text-white">{auth.code}</span></div>
                <div className="flex gap-2">
                  <button className="btn" onClick={()=> window.open((auth as any).url || '', '_blank')}>Open Plex</button>
                  <button className="btn" onClick={async()=>{
                    const cid = loadSettings().plexClientId!;
                    const res:any = await apiClient.checkPlexPin(auth.pinId!, cid);
                    if (res?.authenticated) {
                      setAuth({});
                      try { await apiClient.syncPlexServers(cid); } catch {}
                      const backendServers = await apiClient.getServers();
                      setServers(backendServers || []);
                    }
                  }}>Poll</button>
                </div>
              </div>
            )}
            {servers.length>0 && (
              <div className="mt-3">
                <div className="text-sm mb-2">Select a server</div>
                <div className="grid gap-2">
                  {servers.map((s:any, idx:number)=>{
                    return (
                      <div key={idx} className="flex items-center justify-between bg-white/5 rounded px-3 py-2">
                        <div className="text-neutral-200">{s.name || s.clientIdentifier}</div>
                        <div className="flex gap-2">
                          <button className="btn" onClick={async()=>{
                            saveSettings({ plexServer: { name: s.name, clientIdentifier: s.clientIdentifier, baseUrl: s.baseUrl, token: s.token }, plexBaseUrl: s.baseUrl, plexToken: s.token });
                            setSelectedServer({ name: s.name, clientIdentifier: s.clientIdentifier, baseUrl: s.baseUrl, token: s.token });
                            // Clear Plex caches and notify app to refresh
                            forget('plex:');
                            window.dispatchEvent(new CustomEvent('plex-server-changed', { detail: { name: s.name, baseUrl: s.baseUrl } }));
                          }}>Use</button>
                          <button className="btn" onClick={async()=>{
                            // Fetch candidate endpoints and show chooser
                            try {
                              const sid = s.clientIdentifier;
                              const data = await apiClient.plexServerConnections(sid);
                              setEndpoints((prev)=> ({ ...prev, [sid]: (data.connections || data || []) }));
                              setShowEndpointsFor(sid);
                            } catch (e) {
                              alert('Failed to load endpoints');
                            }
                          }}>Endpoints…</button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            )}
          </div>

          {/* Trakt Authentication */}
          <div className="mt-6">
            <TraktAuth
              onAuthComplete={() => {
                // Refresh the page or update state as needed
                window.dispatchEvent(new CustomEvent('trakt-auth-changed'));
              }}
              onAuthError={(error) => {
                console.error('Trakt auth error:', error);
              }}
            />
          </div>

          <L label="Plex URL"><input value={plexUrl} onChange={(e) => setPlexUrl(e.target.value)} placeholder="https://app.plex.tv" className="input" /></L>
          <L label="Plex Token"><input value={plexToken} onChange={(e) => setPlexToken(e.target.value)} placeholder="" className="input" /></L>
          <L label="TMDB API Key"><input value={tmdbKey} onChange={(e) => setTmdbKey(e.target.value)} className="input" /></L>
          <L label="Watchlist Provider">
            <select
              className="input"
              value={watchlistProvider}
              onChange={(e)=> {
                const v = e.target.value as 'trakt'|'plex';
                setWatchlistProvider(v);
                try { window.dispatchEvent(new CustomEvent('app-toast', { detail: `Watchlist provider: ${v === 'trakt' ? 'Trakt' : 'Plex'}` })); } catch {}
              }}
            >
              <option value="trakt">Trakt</option>
              <option value="plex">Plex</option>
            </select>
            {watchlistProvider === 'trakt' && !traktConnected && (
              <div className="text-xs text-yellow-300 mt-1">Trakt not connected — use the Trakt section above to sign in.</div>
            )}
          </L>
          <div className="flex gap-3 pt-2">
            <button className="btn" onClick={async () => {
              setTmdbStatus('Testing…');
              try {
                const { tmdbTrending } = await import('@/services/tmdb');
                await tmdbTrending(tmdbKey, 'tv', 'day');
                setTmdbStatus('TMDB OK');
              } catch (e: any) {
                setTmdbStatus('TMDB failed: ' + (e?.message || 'error'));
              }
            }}>Test TMDB</button>
            <span className="text-sm text-neutral-400">{tmdbStatus}</span>
          </div>
          <div className="flex gap-3">
            <button className="btn" onClick={async () => {
              setPlexStatus('Testing…');
              try {
                const { plexLibs } = await import('@/services/plex');
                await plexLibs({ baseUrl: plexUrl, token: plexToken });
                setPlexStatus('Plex OK');
              } catch (e: any) {
                setPlexStatus('Plex failed: ' + (e?.message || 'error'));
              }
            }}>Test Plex</button>
            <span className="text-sm text-neutral-400">{plexStatus}</span>
          </div>
          <div className="flex gap-3">
            <button className="btn" onClick={()=> { forget(''); alert('Cache cleared'); }}>Clear App Cache</button>
            <button className="btn" onClick={()=> { saveSettings({ plexAccountToken: undefined, plexServer: undefined }); alert('Signed out from Plex'); }}>Sign out of Plex</button>
          </div>
        </div>
      </section>
      {/* Backend-managed servers section */}
      <section>
        <h2 className="text-xl font-semibold mb-2">Backend Servers</h2>
        <div className="rounded-lg ring-1 ring-white/10 p-4">
          <div className="flex items-center justify-between mb-3">
            <div className="text-sm text-neutral-300">Servers known to the backend (used for library/search).</div>
            <button className="btn" onClick={async()=>{
              try {
                const sv = await apiClient.plexServers();
                setBackendServers(sv || []);
              } catch (e) {
                alert('Failed to load backend servers');
              }
            }}>Refresh</button>
          </div>
          {backendServers.length === 0 ? (
            <div className="text-neutral-400 text-sm">No servers loaded. Click Refresh.</div>
          ) : (
            <div className="grid gap-2">
              {backendServers.map((s:any, idx:number)=> (
                <div key={idx} className="flex items-center justify-between bg-white/5 rounded px-3 py-2">
                  <div className="text-neutral-200 text-sm">
                    <div className="font-medium">{s.name}</div>
                    <div className="text-xs text-neutral-400">{s.protocol}://{s.host}:{s.port} {s.isActive ? '• active' : ''}</div>
                    {s.preferredUri && (
                      <div className="text-xs text-green-400">preferred: {s.preferredUri}</div>
                    )}
                  </div>
                  <div className="flex gap-2">
                    {!s.isActive && (
                      <button className="btn" onClick={async()=>{
                        try {
                          await apiClient.plexSetCurrentServer(s.id);
                          window.dispatchEvent(new CustomEvent('app-toast', { detail: 'Active server updated' }));
                          const sv = await apiClient.plexServers();
                          setBackendServers(sv || []);
                        } catch (e) {
                          alert('Failed to set current server');
                        }
                      }}>Make Current</button>
                    )}
                    <button className="btn" onClick={async()=>{
                      try {
                        const data = await apiClient.plexServerConnections(s.id);
                        setEndpoints((prev)=> ({ ...prev, [s.id]: (data.connections || data || []) }));
                        setShowEndpointsFor(s.id);
                      } catch (e) {
                        alert('Failed to load endpoints');
                      }
                    }}>Endpoints…</button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </section>
      {showEndpointsFor && (
        <div className="fixed inset-0 bg-black/70 flex items-center justify-center z-50">
          <div className="bg-neutral-900 rounded-lg p-4 w-full max-w-lg ring-1 ring-white/10">
            <div className="flex items-center justify-between mb-3">
              <div className="text-white font-semibold">Select Endpoint</div>
              <button className="text-white/70 hover:text-white" onClick={()=> setShowEndpointsFor(null)}>✕</button>
            </div>
            <div className="space-y-2 max-h-80 overflow-auto pr-1">
              {(endpoints[showEndpointsFor] || []).map((c, i)=> (
                <div key={i} className="flex items-center justify-between bg-white/5 rounded px-3 py-2">
                  <div className="text-white/90 text-sm break-all">
                    {c.uri}
                    {c.isPreferred && <span className="ml-2 text-xs text-green-400">preferred</span>}
                    {c.isCurrent && <span className="ml-2 text-xs text-blue-400">current</span>}
                  </div>
                  <button className="btn" onClick={async()=>{
                    try {
                      await apiClient.plexSetServerEndpoint(showEndpointsFor, c.uri, true);
                      window.dispatchEvent(new CustomEvent('app-toast', { detail: 'Endpoint updated' }));
                      // Refresh backend servers list to reflect change
                      try { const sv = await apiClient.plexServers(); setBackendServers(sv || []); } catch {}
                      setShowEndpointsFor(null);
                    } catch (e:any) {
                      alert('Endpoint unreachable');
                    }
                  }}>Use</button>
                </div>
              ))}
            </div>
            <div className="mt-3 text-xs text-white/60">These endpoints come from your Plex server's advertised addresses (local and public). Choose the one that works best from your network.</div>
          </div>
        </div>
      )}
      <section>
        <h2 className="text-xl font-semibold mb-2">Playback</h2>
        <div className="grid gap-3">
          <L label="MPV Profile">
            <select className="input">
              <option>Direct Play</option>
              <option>Transcode (H264/AAC)</option>
            </select>
          </L>
          <L label="HDR to SDR Tone-map">
            <select className="input">
              <option>auto</option>
              <option>bt.2390</option>
              <option>hable</option>
            </select>
          </L>
        </div>
      </section>
      </div>
    </div>
  );
}

function L({ label, children }: { label: string; children: any }) {
  return (
    <label className="grid gap-1">
      <span className="text-sm text-neutral-300">{label}</span>
      {children}
    </label>
  );
}

// (styled via Tailwind utility classes in src/styles/index.css)
