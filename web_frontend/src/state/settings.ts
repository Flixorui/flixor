import { useSyncExternalStore } from 'react';

export type AccentPalette =
  | 'crimson' | 'orange' | 'amber' | 'emerald' | 'teal'
  | 'sky' | 'blue' | 'violet' | 'pink' | 'mono';
export type NavigationStyle = 'topBar' | 'sidebar';
export type NavigationBarStyle = 'adaptive' | 'expanded' | 'compact';
export type CardTitleMode = 'always' | 'hover' | 'never';
export type HoverTrailerMode = 'off' | 'muted' | 'sound';
export type ContinueWatchingSource = 'automatic' | 'library' | 'trakt';
export type ContinueWatchingSort = 'recent' | 'nextEpisodeFirst' | 'title';
export type StremioPlayAction = 'showSources' | 'playBest' | 'matchRules' | 'addonOrder';
export type StremioUnsupportedSourceVisibility = 'showDisabled' | 'hide';
export type SubtitleSourcePreference = 'internal' | 'external' | 'any';
export type PlayerAspectMode = 'fit' | 'fill' | 'zoom' | 'stretch';
export type DetailsSectionKey =
  | 'episodes' | 'suggested' | 'collection' | 'cast' | 'trailers' | 'comments' | 'about';
export type DetailsSectionPreference = { key: DetailsSectionKey; enabled: boolean };
export type DetailsSeasonPickerStyle = 'chips' | 'posters';
export type SearchIdleTab = 'explore' | 'discover';
export type SearchDiscoverFilters = {
  mediaType: 'movie' | 'tv';
  genreId?: number;
  genreName?: string;
  sort: 'popular' | 'topRated' | 'newest' | 'oldest' | 'title';
  yearFrom?: number;
  yearTo?: number;
  minimumRating?: number;
};

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

/**
 * Keys added for macOS parity, with their defaults. Add new keys here, so they are
 * typed and defaulted in one place. Defaults are applied on read and never written
 * back, so changing one later reaches users who have not touched the setting.
 */
export const SETTINGS_DEFAULTS = {
  // Appearance
  accentPalette: 'crimson' as AccentPalette,
  pureBlack: false,

  // Navigation
  navigationStyle: 'topBar' as NavigationStyle,
  navigationSidebarPinned: false,
  navigationBarStyle: 'adaptive' as NavigationBarStyle,
  navigationBarGlow: true,

  // Advanced
  debugLoggingEnabled: false,

  // Cards
  cardTitleMode: 'hover' as CardTitleMode,
  cardShowRatingBadges: false,
  cardHoverPreviewEnabled: true,
  cardHoverPreviewDelay: 0.8, // seconds, 0.3-2.0
  cardHoverTrailerMode: 'muted' as HoverTrailerMode,

  // Home rows and hero
  homeRowOrder: [] as string[],
  homeRowTitles: {} as Record<string, string>,
  homeRowHidden: [] as string[],
  homeHeroSource: 'default', // 'default' | 'continueWatching' | 'myList' | `row:${rowId}`
  showWatchlistRow: true,
  showCollectionRows: true,
  hiddenCollectionKeys: [] as string[],
  groupRecentlyAddedEpisodes: true,

  // Continue Watching
  continueWatchingSource: 'automatic' as ContinueWatchingSource,
  continueWatchingSort: 'recent' as ContinueWatchingSort,
  continueWatchingBlurNextUp: false,
  continueWatchingTraktDismissals: {} as Record<string, number>, // item key -> epoch ms
  useCachedStreams: false,
  openMetadataScreenWhenCacheDisabled: false,
  streamCacheTTL: 60 * 60 * 1000, // ms

  // Search and Library
  recentSearches: [] as string[], // most recent first, at most 15
  searchIdleTab: 'explore' as SearchIdleTab,
  searchDiscoverFilters: null as SearchDiscoverFilters | null,
  libraryViewMode: 'grid' as 'grid' | 'list',
  enabledLibraryKeys: [] as string[], // empty means all libraries

  // Details
  detailsSectionOrder: [
    { key: 'episodes', enabled: true },
    { key: 'suggested', enabled: true },
    { key: 'collection', enabled: true },
    { key: 'cast', enabled: true },
    { key: 'trailers', enabled: true },
    { key: 'comments', enabled: true },
    { key: 'about', enabled: true },
  ] as DetailsSectionPreference[],
  detailsHideEpisodeSpoilers: false,
  detailsSeasonPickerStyle: 'chips' as DetailsSeasonPickerStyle,
  detailsShowEpisodeRatings: true,
  detailsHeroInlineTrailerEnabled: true,
  detailsHeroTrailerStartsMuted: true,
  suggestedLayout: 'landscape' as 'landscape' | 'poster',
  showRelatedContent: true,
  showCastCrew: true,

  // Stremio
  stremioPlaybackEnabled: false,
  /** Set once the user flips addon playback themselves; adding an addon then leaves it alone. */
  stremioPlaybackSetByUser: false,
  showStremioCatalogRows: true,
  stremioCatalogSearchEnabled: true,
  stremioShowOnTmdbDetails: true,
  stremioPreferCachedSourceResume: true,
  stremioSubtitleAddonsEnabled: true,
  stremioUnsupportedSourceVisibility: 'showDisabled' as StremioUnsupportedSourceVisibility,
  stremioPlayAction: 'showSources' as StremioPlayAction,
  stremioAutoPickTimeLimit: 5, // seconds
  stremioRulesInclude: '',
  stremioRulesIncludeRegex: false,
  stremioRulesExclude: '',
  stremioRulesPreferredAddon: '', // installationId, empty means none
  stremioRulesMaxResolution: 0, // vertical pixels, 0 means no limit

  // Player
  autoPlayNext: true,
  skipIntroAutomatically: true,
  skipCreditsAutomatically: true,
  skipRecapAutomatically: true,
  autoSkipDelay: 5, // seconds
  communitySkipSegmentsEnabled: true,
  animeSkipClientId: '',
  creditsCountdownFallback: 30, // seconds
  seekTimeSmall: 10, // seconds
  seekTimeLarge: 30, // seconds
  defaultPlaybackSpeed: 1,
  maxVolume: 100, // percent; above 100 uses Web Audio gain
  playerAspectMode: 'fit' as PlayerAspectMode,

  // Tracks and subtitles (subtitleFontSize and subtitleOffset are stored above)
  rememberTrackSelections: true,
  preferredAudioLanguage: '', // empty means the media default, 'original' means original language
  preferredSubtitleLanguage: 'en',
  subtitleSourcePreference: 'internal' as SubtitleSourcePreference,
  enableSubtitleAutoSelect: true,
  subtitleFontName: '', // empty means the player default
  subtitleBold: false,
  subtitleTextColor: '#FFFFFF',
  subtitleBorderSize: 3,
  subtitleBorderColor: '#000000',
  subtitleBackgroundColor: '#000000',
  subtitleBackgroundOpacity: 0, // 0-1
  subtitleFilterSDH: false,

  // Integrations
  traktAutoSyncWatched: true,
  traktSyncRatings: true,
  traktSyncWatchlist: true,
  overseerrAuthMethod: 'api_key' as 'api_key' | 'plex',
  overseerrPlexUsername: '',
  tmdbApiKey: '',
  enrichMetadataWithTMDB: true,
  useTmdbLocalizedMetadata: false,
  tmdbLanguagePreference: 'en',
};

export type DefaultedSettings = typeof SETTINGS_DEFAULTS;

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
  continueWatchingLayout?: 'landscape' | 'poster' | 'wide';
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
  posterSize?: 'small' | 'medium' | 'large' | 'xlarge';
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
} & Partial<DefaultedSettings>;

/** Stored settings with every key in {@link SETTINGS_DEFAULTS} guaranteed present. */
export type ResolvedSettings = AppSettings & DefaultedSettings;

const MAIN_KEY = 'app.settings.v1';
export const ACTIVE_PROFILE_STORAGE_KEY = 'app.activeProfile.v1';
const ACTIVE_PROFILE_KEY = ACTIVE_PROFILE_STORAGE_KEY;
const PROFILE_KEY_PREFIX = 'profile:';

/** Settings shared by every profile on this browser. The main account's copy wins. */
const GLOBAL_SETTING_KEYS = ['hasCompletedOnboarding', 'plexClientId'] as const;

/** The Plex Home profile in use on this browser. Null means the signed-in account. */
export type ActiveProfile = {
  uuid: string;
  title: string;
  thumb?: string;
  restricted: boolean;
  protected: boolean;
};

export function getActiveProfile(): ActiveProfile | null {
  try {
    const parsed = JSON.parse(localStorage.getItem(ACTIVE_PROFILE_KEY) || 'null');
    return parsed && typeof parsed.uuid === 'string' ? parsed : null;
  } catch {
    return null;
  }
}

/** Points settings at a profile's storage. The main account keeps the original key. */
export function setActiveProfile(profile: ActiveProfile | null) {
  if (profile) localStorage.setItem(ACTIVE_PROFILE_KEY, JSON.stringify(profile));
  else localStorage.removeItem(ACTIVE_PROFILE_KEY);
  scheduleNotify();
}

function settingsKey(): string {
  const profile = getActiveProfile();
  return profile ? `${PROFILE_KEY_PREFIX}${profile.uuid}:${MAIN_KEY}` : MAIN_KEY;
}

/** Raw stored values. Keys with a default stay undefined until the user changes them. */
export function loadSettings(): AppSettings {
  return withGlobals(parseStored(readRaw()));
}

export function saveSettings(patch: Partial<AppSettings>) {
  const key = settingsKey();
  const curr = loadSettings();
  const next = { ...curr, ...patch };
  localStorage.setItem(key, JSON.stringify(next));
  if (key !== MAIN_KEY) saveGlobals(patch);
  scheduleNotify();
  return next;
}

function saveGlobals(patch: Partial<AppSettings>) {
  const globals = GLOBAL_SETTING_KEYS.filter((k) => k in patch);
  if (globals.length === 0) return;
  const main: Record<string, unknown> = parseStored(readKey(MAIN_KEY));
  for (const k of globals) main[k] = patch[k];
  localStorage.setItem(MAIN_KEY, JSON.stringify(main));
}

function withGlobals(settings: AppSettings): AppSettings {
  if (settingsKey() === MAIN_KEY) return settings;
  const main = parseStored(readKey(MAIN_KEY));
  const merged: Record<string, unknown> = { ...settings };
  for (const k of GLOBAL_SETTING_KEYS) {
    if (main[k] !== undefined) merged[k] = main[k];
  }
  return merged as AppSettings;
}

function readKey(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function readRaw(): string | null {
  return readKey(settingsKey());
}

function parseStored(raw: string | null): AppSettings {
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
  } catch {
    return {};
  }
}

// Stable snapshot for useSyncExternalStore: only rebuilt when the stored JSON changes.
let snapshot: { raw: string; value: ResolvedSettings } | null = null;

/** Current settings with defaults applied, for code outside React. */
export function getSettings(): ResolvedSettings {
  const key = settingsKey();
  // A profile also depends on the main account's copy of the global keys.
  const raw = `${key}\u0000${readKey(key)}\u0000${key === MAIN_KEY ? '' : readKey(MAIN_KEY)}`;
  if (!snapshot || snapshot.raw !== raw) {
    snapshot = { raw, value: { ...structuredClone(SETTINGS_DEFAULTS), ...loadSettings() } };
  }
  return snapshot.value;
}

const listeners = new Set<() => void>();
let notifyQueued = false;

// Deferred because saveSettings is called from inside React state updaters
// (routes/Settings.tsx), where re-rendering subscribers synchronously is not allowed.
function scheduleNotify() {
  if (notifyQueued) return;
  notifyQueued = true;
  queueMicrotask(() => {
    notifyQueued = false;
    listeners.forEach((listener) => listener());
  });
}

function onStorage(event: StorageEvent) {
  if (event.key === null || event.key === ACTIVE_PROFILE_KEY || event.key === MAIN_KEY || event.key === settingsKey()) {
    scheduleNotify();
  }
}

/** Calls `listener` after any settings change, including from other tabs. */
export function subscribeSettings(listener: () => void): () => void {
  if (listeners.size === 0) window.addEventListener('storage', onStorage);
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
    if (listeners.size === 0) window.removeEventListener('storage', onStorage);
  };
}

/** Settings with defaults applied. Re-renders the caller when any setting changes. */
export function useSettings(): ResolvedSettings {
  return useSyncExternalStore(subscribeSettings, getSettings, getSettings);
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

const ACCOUNT_SETTING_KEYS = [
  'plexBaseUrl', 'plexToken', 'plexTvToken', 'plexAccountToken', 'plexServer',
  'plexServers', 'plexUserProfile', 'plexUsers', 'plexCurrentUserId',
] as const;

/** Sign-out: removes Plex credentials from every profile and keeps preferences. */
export function clearAccountSettings() {
  const keys = [MAIN_KEY];
  for (let i = 0; i < localStorage.length; i++) {
    const key = localStorage.key(i);
    if (key?.startsWith(PROFILE_KEY_PREFIX) && key.endsWith(`:${MAIN_KEY}`)) keys.push(key);
  }
  for (const key of keys) {
    const stored: Record<string, unknown> = parseStored(readKey(key));
    ACCOUNT_SETTING_KEYS.forEach((k) => delete stored[k]);
    localStorage.setItem(key, JSON.stringify(stored));
  }
  localStorage.removeItem(ACTIVE_PROFILE_KEY);
  scheduleNotify();
}

/**
 * Reset all app settings to defaults, including every profile's copy.
 */
export function resetAllSettings() {
  const keys: string[] = [];
  for (let i = 0; i < localStorage.length; i++) {
    const key = localStorage.key(i);
    if (key?.startsWith(PROFILE_KEY_PREFIX) && key.endsWith(`:${MAIN_KEY}`)) keys.push(key);
  }
  keys.forEach((key) => localStorage.removeItem(key));
  localStorage.removeItem(MAIN_KEY);
  localStorage.removeItem(ACTIVE_PROFILE_KEY);
  scheduleNotify();
}
