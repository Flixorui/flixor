export type PlexUserProfile = {
  id: number;
  username: string;
  email: string;
  thumb?: string;
  title?: string;
  hasPassword: boolean;
  authToken?: string;
  subscription?: {
    active: boolean;
    status: string;
    plan?: string;
  };
};

export type PlexUser = {
  id: number;
  username: string;
  email?: string;
  thumb?: string;
  title?: string;
  isHome?: boolean;
  isRestricted?: boolean;
};

export type AppSettings = {
  plexBaseUrl?: string;
  plexToken?: string;
  plexTvToken?: string;
  plexAccountToken?: string;
  plexClientId?: string;
  plexServer?: { name: string; clientIdentifier: string; baseUrl: string; token: string };
  plexServers?: Array<{ name: string; clientIdentifier: string; bestUri: string; token: string }>;
  plexUserProfile?: PlexUserProfile;
  plexUsers?: PlexUser[];
  plexCurrentUserId?: number;
  tmdbBearer?: string;
  traktClientId?: string;
  traktTokens?: string; // JSON stringified TraktTokens
  traktScrobbleEnabled?: boolean;
  traktSyncEnabled?: boolean;
  watchlistProvider?: 'trakt' | 'plex';
};

const KEY = 'app.settings.v1';

export function loadSettings(): AppSettings {
  try {
    const s = localStorage.getItem(KEY);
    return s ? JSON.parse(s) : {};
  } catch {
    return {};
  }
}

export function saveSettings(patch: Partial<AppSettings>) {
  const curr = loadSettings();
  const next = { ...curr, ...patch };
  localStorage.setItem(KEY, JSON.stringify(next));
  return next;
}
