import { apiClient } from '@/services/api';
import { forget } from '@/services/cache';
import { loadSettings, saveSettings } from '@/state/settings';

export type StoredPlexServer = { name: string; clientIdentifier: string; bestUri: string; token: string };

function applyServer(server: StoredPlexServer) {
  saveSettings({
    plexServer: {
      name: server.name,
      clientIdentifier: server.clientIdentifier,
      baseUrl: server.bestUri,
      token: server.token,
    },
    plexBaseUrl: server.bestUri,
    plexToken: server.token,
  });
  forget('plex:');
  window.dispatchEvent(
    new CustomEvent('plex-server-changed', { detail: { name: server.name, baseUrl: server.bestUri } })
  );
}

/** Syncs the server list from Plex, saves it, and selects one if none is selected. */
export async function refreshPlexServers(): Promise<StoredPlexServer[]> {
  const settings = loadSettings();
  try {
    await apiClient.syncPlexServers(settings.plexClientId || 'web');
  } catch {
    // Best effort: the list below still works from Plex directly.
  }
  const response = await apiClient.getServers();
  if (!Array.isArray(response)) return [];
  const list: StoredPlexServer[] = response.map((s: any) => ({
    name: s.name,
    clientIdentifier: s.clientIdentifier,
    bestUri: s.baseUrl,
    token: s.token,
  }));
  saveSettings({ plexServers: list });

  if (list.length > 0 && !loadSettings().plexServer) {
    let activeId: string | undefined;
    try {
      const known = await apiClient.plexServers();
      activeId = Array.isArray(known) ? known.find((s: any) => s.isActive)?.id : undefined;
    } catch {
      // Falls back to the first server.
    }
    applyServer(list.find((s) => s.clientIdentifier === activeId) ?? list[0]);
  }
  return list;
}

/** Makes a server current on the backend and in this browser. */
export async function selectPlexServer(server: StoredPlexServer) {
  await apiClient.plexSetCurrentServer(server.clientIdentifier);
  applyServer(server);
}

/** Updates this browser's selection after the backend's current server or endpoint changed. */
export function adoptPlexServer(clientIdentifier: string, endpoint?: string) {
  const server = loadSettings().plexServers?.find((s) => s.clientIdentifier === clientIdentifier);
  if (server) applyServer(endpoint ? { ...server, bestUri: endpoint } : server);
}
