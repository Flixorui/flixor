import { Link, useLocation } from 'react-router-dom';
import { useEffect, useRef, useState } from 'react';
import { loadSettings, saveSettings } from '@/state/settings';
import { forget } from '@/services/cache';
import { apiClient } from '@/services/api';

const items = [
  { to: '/', label: 'Home' },
  { to: '/library', label: 'Library' },
  { to: '/my-list', label: 'My List' },
  { to: '/new-popular', label: 'New & Popular' },
  { to: '/search', label: 'Search' },
];

export default function TopNav() {
  const { pathname } = useLocation();
  const [open, setOpen] = useState(false);
  const [servers, setServers] = useState<Array<{ name: string; clientIdentifier: string; bestUri: string; token: string }>>([]);
  const [current, setCurrent] = useState<{ name: string } | null>(null);
  const [loadingServers, setLoadingServers] = useState(false);
  const headerRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const s = loadSettings();
    if (s.plexServer) setCurrent({ name: s.plexServer.name });
    if (s.plexServers) {
      setServers(s.plexServers);
    }

    // Auto-fetch servers if no servers list is available
    if (!s.plexServers || s.plexServers.length === 0) {
      setLoadingServers(true);

      // Try backend first, then Plex.tv
      const fetchServers = async () => {
        let list: Array<{ name: string; clientIdentifier: string; bestUri: string; token: string }> = [];
        // Try backend API
        try {
          try {
            // best-effort server sync
            await apiClient.syncPlexServers(s.plexClientId || 'web');
          } catch {}
          const backendServers = await apiClient.getServers();
          if (backendServers && backendServers.length > 0) {
            list = backendServers.map((s: any) => ({
              name: s.name,
              clientIdentifier: s.clientIdentifier,
              bestUri: s.baseUrl,
              token: s.token
            }));
          }
        } catch (backendError) {}

        if (list.length > 0) {
          setServers(list);
          saveSettings({ plexServers: list });

          // If no server is currently selected, select the first one
          if (!s.plexServer) {
            const firstServer = list[0];
            saveSettings({
              plexServer: {
                name: firstServer.name,
                clientIdentifier: firstServer.clientIdentifier,
                baseUrl: firstServer.bestUri,
                token: firstServer.token
              },
              plexBaseUrl: firstServer.bestUri,
              plexToken: firstServer.token
            });
            setCurrent({ name: firstServer.name });
            // Notify app to refresh Plex-backed views
            window.dispatchEvent(new CustomEvent('plex-server-changed', {
              detail: { name: firstServer.name, baseUrl: firstServer.bestUri }
            }));
          }
        }
      };

      fetchServers().finally(() => {
        setLoadingServers(false);
      });
    }
  }, []);

  // Track scroll and drive background fade with rAF for smoothness
  useEffect(() => {
    const el = headerRef.current;
    if (!el) return;
    let current = 0; // start transparent; fade based on scroll on all pages
    let target = current;
    let rafId: number | null = null;

    const setVars = (v: number) => {
      el.style.setProperty('--nav-bg-o', String(0.85 * v));
      el.style.setProperty('--nav-blur', `${10 * v}px`);
    };
    setVars(current);

    const animate = () => {
      current += (target - current) * 0.18;
      if (Math.abs(target - current) < 0.005) {
        current = target;
        setVars(current);
        rafId = null;
        return;
      }
      setVars(current);
      rafId = requestAnimationFrame(animate);
    };

    const onScroll = () => {
      const y = window.scrollY || 0;
      target = Math.min(1, y / 120);
      if (rafId == null) rafId = requestAnimationFrame(animate);
    };
    // initialize based on current scroll
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true } as any);
    return () => {
      window.removeEventListener('scroll', onScroll);
      if (rafId != null) cancelAnimationFrame(rafId);
    };
  }, [pathname]);

  async function doRefresh() {
    setLoadingServers(true);
    try {
      let list: Array<{ name: string; clientIdentifier: string; bestUri: string; token: string }> = [];
      // Try backend API
      try {
        try {
          await apiClient.syncPlexServers(loadSettings().plexClientId || 'web');
        } catch {}
        const backendServers = await apiClient.getServers();

        if (backendServers && backendServers.length > 0) {
          // Convert backend format to our expected format
          list = backendServers.map((s: any) => ({
            name: s.name,
            clientIdentifier: s.clientIdentifier,
            bestUri: s.baseUrl,
            token: s.token
          }));
        }
      } catch (backendError) {}

      setServers(list);
      saveSettings({ plexServers: list });

      // If we got servers but none is selected, select the first one
      if (list.length > 0 && !current) {
        const firstServer = list[0];
        saveSettings({
          plexServer: {
            name: firstServer.name,
            clientIdentifier: firstServer.clientIdentifier,
            baseUrl: firstServer.bestUri,
            token: firstServer.token
          },
          plexBaseUrl: firstServer.bestUri,
          plexToken: firstServer.token
        });
        setCurrent({ name: firstServer.name });
        // Notify app to refresh Plex-backed views
        window.dispatchEvent(new CustomEvent('plex-server-changed', {
          detail: { name: firstServer.name, baseUrl: firstServer.bestUri }
        }));
      }
    } catch (err) {
      console.error('Failed to refresh servers:', err);
    } finally {
      setLoadingServers(false);
    }
  }
  return (
    <header className="fixed left-0 right-0 z-50">
      <div ref={headerRef} className="relative h-14">
        <div className="nav-bg" />
        <div className="page-gutter h-14 flex items-center relative z-10">
          {/* Left: Logo */}
          <Link to="/" className="flex items-center gap-2">
            <span className="text-2xl font-extrabold tracking-tight text-brand">FLIXOR</span>
          </Link>

          {/* Center: Navigation pill */}
          <nav className="hidden md:flex absolute left-1/2 -translate-x-1/2 items-center bg-neutral-900/80 backdrop-blur-md rounded-full px-1.5 py-1 ring-1 ring-white/10">
            {items.map((it) => {
              const base = it.to.split('?')[0];
              const active = base === '/' ? pathname === '/' : pathname.startsWith(base);
              return (
                <Link
                  key={it.label}
                  to={it.to}
                  className={`px-4 py-1.5 text-[13px] font-medium rounded-full transition-all ${
                    active
                      ? 'bg-white/15 text-white'
                      : 'text-neutral-400 hover:text-white'
                  }`}
                >
                  {it.label}
                </Link>
              );
            })}
          </nav>

          {/* Right: Server selector */}
          <div className="ml-auto flex items-center gap-3">
            <div className="relative hidden md:block">
              <button
                onClick={() => setOpen(v => !v)}
                className="flex items-center gap-2 px-4 py-1.5 text-[13px] font-medium text-white bg-neutral-800/80 backdrop-blur-md rounded-full ring-1 ring-white/10 hover:bg-neutral-700/80 transition-all"
              >
                {current?.name || 'Server'}
              </button>
              {open && (
                <div className="absolute right-0 mt-2 w-64 rounded-xl ring-1 ring-white/10 bg-neutral-900/95 backdrop-blur-xl p-2 z-50 shadow-2xl">
                  <div className="text-xs text-neutral-500 px-2 py-1 font-medium">Servers</div>
                  <div className="max-h-60 overflow-auto">
                    {loadingServers ? (
                      <div className="px-2 py-2 text-neutral-400 text-sm">Loading...</div>
                    ) : (
                      <>
                        {servers.map((s, i) => {
                          const isSelected = current?.name === s.name;
                          return (
                            <button
                              key={i}
                              className={`w-full text-left px-3 py-2 rounded-lg text-sm flex items-center justify-between transition-colors ${
                                isSelected ? 'bg-white/10 text-white' : 'text-neutral-300 hover:bg-white/5'
                              }`}
                              onClick={() => {
                                saveSettings({
                                  plexServer: { name: s.name, clientIdentifier: s.clientIdentifier, baseUrl: s.bestUri, token: s.token },
                                  plexBaseUrl: s.bestUri,
                                  plexToken: s.token
                                });
                                forget('plex:');
                                setCurrent({ name: s.name });
                                setOpen(false);
                                window.dispatchEvent(new CustomEvent('plex-server-changed', { detail: { name: s.name, baseUrl: s.bestUri } }));
                              }}
                            >
                              <span>{s.name}</span>
                              {isSelected && (
                                <svg className="w-4 h-4 text-green-500" fill="currentColor" viewBox="0 0 24 24">
                                  <path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z" />
                                </svg>
                              )}
                            </button>
                          );
                        })}
                        {servers.length === 0 && (
                          <div className="px-3 py-2 text-neutral-500 text-sm">No servers found</div>
                        )}
                      </>
                    )}
                  </div>
                  <div className="border-t border-white/10 mt-2 pt-2 flex justify-between px-2">
                    <button className="text-xs text-neutral-400 hover:text-white transition-colors" onClick={doRefresh}>
                      Refresh
                    </button>
                    <Link to="/settings" className="text-xs text-neutral-400 hover:text-white transition-colors" onClick={() => setOpen(false)}>
                      Settings
                    </Link>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </header>
  );
}

