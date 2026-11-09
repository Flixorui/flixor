import { useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { refreshPlexServers, selectPlexServer, type StoredPlexServer } from '@/services/plexServers';
import { showToast } from '@/services/toast';
import { useSettings } from '@/state/settings';

export default function ServerMenu() {
  const { plexServer, plexServers } = useSettings();
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const servers = plexServers ?? [];

  useEffect(() => {
    if (!open) return;
    const onPointerDown = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener('pointerdown', onPointerDown);
    return () => document.removeEventListener('pointerdown', onPointerDown);
  }, [open]);

  async function refresh() {
    setLoading(true);
    try {
      await refreshPlexServers();
    } catch {
      showToast('Could not refresh servers', 'error');
    } finally {
      setLoading(false);
    }
  }

  async function select(server: StoredPlexServer) {
    setOpen(false);
    try {
      await selectPlexServer(server);
    } catch {
      showToast(`Could not switch to ${server.name}`, 'error');
    }
  }

  return (
    <div className="relative" ref={rootRef}>
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        title={plexServer?.name}
        className="flex items-center gap-2 max-w-[120px] px-4 py-1.5 text-[13px] font-medium text-white bg-neutral-800/80 backdrop-blur-md rounded-full ring-1 ring-white/10 hover:bg-neutral-700/80 transition-all"
      >
        {/* Capped so a long server name cannot run into the centred tabs. */}
        <span className="truncate">{plexServer?.name || 'Server'}</span>
      </button>
      {open && (
        <div className="absolute right-0 mt-2 w-64 rounded-xl ring-1 ring-white/10 bg-neutral-900/95 backdrop-blur-xl p-2 z-50 shadow-2xl">
          <div className="text-xs text-neutral-500 px-2 py-1 font-medium">Servers</div>
          <div className="max-h-60 overflow-auto">
            {loading ? (
              <div className="px-2 py-2 text-neutral-400 text-sm">Loading...</div>
            ) : servers.length === 0 ? (
              <div className="px-3 py-2 text-neutral-500 text-sm">No servers found</div>
            ) : (
              servers.map((server) => {
                const selected = plexServer?.clientIdentifier === server.clientIdentifier;
                return (
                  <button
                    key={server.clientIdentifier}
                    type="button"
                    onClick={() => select(server)}
                    className={`w-full text-left px-3 py-2 rounded-lg text-sm flex items-center justify-between transition-colors ${
                      selected ? 'bg-white/10 text-white' : 'text-neutral-300 hover:bg-white/5'
                    }`}
                  >
                    <span className="truncate">{server.name}</span>
                    {selected && (
                      <svg className="w-4 h-4 text-green-500" fill="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                        <path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z" />
                      </svg>
                    )}
                  </button>
                );
              })
            )}
          </div>
          <div className="border-t border-white/10 mt-2 pt-2 flex justify-between px-2">
            <button type="button" className="text-xs text-neutral-400 hover:text-white transition-colors" onClick={refresh}>
              Refresh
            </button>
            <Link to="/settings/plex" className="text-xs text-neutral-400 hover:text-white transition-colors" onClick={() => setOpen(false)}>
              Settings
            </Link>
          </div>
        </div>
      )}
    </div>
  );
}
