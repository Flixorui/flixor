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

  // Onboarding
  hasCompletedOnboarding?: boolean;

  // Discovery mode - when true, disables all external discovery features
  discoveryDisabled?: boolean;

  // Home screen settings
  showHeroSection?: boolean;
  heroLayout?: 'legacy' | 'carousel' | 'appletv';
  heroAutoRotate?: boolean;
  showContinueWatchingRow?: boolean;
  continueWatchingLayout?: 'landscape' | 'poster';
  showTrendingRows?: boolean;
  showTraktRows?: boolean;
  showPlexPopularRow?: boolean;
  showNewPopularTab?: boolean;
  includeTmdbInSearch?: boolean;
  showPosterTitles?: boolean;
  showLibraryTitles?: boolean;
  posterBorderRadius?: number; // 0, 12, or 20
  rowsVisible?: {
    trending?: boolean;
    watchlist?: boolean;
    popular?: boolean;
    trakt?: boolean;
  };

  // Trakt settings
  traktAccessToken?: string;

  // Details screen settings
  detailsLayout?: 'tabbed' | 'unified';
  episodeLayout?: 'horizontal' | 'vertical';
  ratingsVisible?: {
    imdb?: boolean;
    rtCritic?: boolean;
    rtAudience?: boolean;
    letterboxd?: boolean;
    metacritic?: boolean;
  };

  // Appearance settings
  posterSize?: 'small' | 'medium' | 'large';
  cardCornerRadius?: 'none' | 'small' | 'medium' | 'large';
  showCardTitles?: boolean;
  rowLayout?: 'landscape' | 'poster'; // Layout for regular content rows

  // Integration settings
  mdblistApiKey?: string;
  mdblistEnabled?: boolean;
  overseerrUrl?: string;
  overseerrApiKey?: string;
  overseerrEnabled?: boolean;

  // Player settings
  subtitleFontSize?: number; // percentage 50-200
  subtitleOffset?: number; // pixels
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

/**
 * Set discovery disabled mode. When enabled, turns off all discovery-related settings.
 */
export function setDiscoveryDisabled(disabled: boolean) {
  if (disabled) {
    return saveSettings({
      discoveryDisabled: true,
      showTrendingRows: false,
      showTraktRows: false,
      showPlexPopularRow: false,
      showNewPopularTab: false,
      includeTmdbInSearch: false,
    });
  } else {
    return saveSettings({ discoveryDisabled: false });
  }
}

/**
 * Reset all app settings to defaults (for logout)
 */
export function resetAllSettings() {
  localStorage.removeItem(KEY);
}
