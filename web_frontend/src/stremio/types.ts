/** Types for the Stremio addon platform. Import them from `@/stremio`. */

export type StremioRequestType = 'movie' | 'series';

export type StremioSourceType =
  | 'url' | 'externalUrl' | 'ytId' | 'infoHash' | 'nzbUrl' | 'archive' | 'unknown';

export interface StremioAddon {
  /** Unique per install, since one addon can be installed with different configs. */
  installationId: string;
  id: string;
  name: string;
  version: string;
  description?: string;
  logo?: string;
  /** Manifest URL. May embed debrid keys: never log it or send it to analytics. */
  manifestUrl: string;
  types: string[];
  resources: string[];
  idPrefixes?: string[];
  catalogs: StremioCatalog[];
  configurable: boolean;
  /** Page where the addon's settings are edited, when it has one. */
  configureUrl?: string;
}

export interface StremioCatalog {
  installationId: string;
  addonName: string;
  type: string;
  id: string;
  name: string;
  supportsSearch: boolean;
  supportsSkip: boolean;
  /** Extras the addon rejects a request without. Empty for plain rows. */
  requiredExtras?: string[];
}

export interface StremioCatalogItem {
  id: string;
  type: string;
  name: string;
  poster?: string;
  background?: string;
  year?: number;
  imdbId?: string;
  tmdbId?: number;
  description?: string;
  imdbRating?: string;
}

/** A title resolved to the ids addons understand. */
export interface StremioContentIdentity {
  requestType: StremioRequestType;
  /** Show or movie id, for example `tt0903747`. */
  baseId: string;
  /** Id sent to addons, for example `tt0903747:1:1` for an episode. */
  requestId: string;
  imdbId?: string;
  tmdbId?: number;
  seasonNumber?: number;
  episodeNumber?: number;
}

/**
 * Input for {@link resolveContentIdentity}. Provide whichever ids are known. For an
 * episode, `imdbId` and `tmdbId` are the show's, since addons address episodes as
 * `<show id>:<season>:<episode>`.
 */
export interface StremioContentRef {
  mediaType: 'movie' | 'show' | 'episode';
  plexRatingKey?: string;
  imdbId?: string;
  tmdbId?: number;
  seasonNumber?: number;
  episodeNumber?: number;
}

export interface StremioSubtitle {
  id: string;
  url: string;
  lang: string;
  format?: 'srt' | 'vtt' | 'ass' | 'ssa';
  addonId?: string;
  addonName?: string;
}

export interface StremioStream {
  name?: string;
  title?: string;
  description?: string;
  sourceType: StremioSourceType;
  url?: string;
  /**
   * URL to give the player. Set by SourcesSheet and prepareStreamForPlayback, and
   * differs from `url` when the stream has to go through the backend proxy.
   */
  playbackUrl?: string;
  externalUrl?: string;
  ytId?: string;
  infoHash?: string;
  fileIdx?: number;
  addonId: string;
  addonName: string;
  installationId: string;
  /** Position in the addon's response, the tiebreaker for ranking. */
  streamIndex: number;
  sizeBytes?: number;
  quality?: string;
  subtitles?: StremioSubtitle[];
  behaviorHints?: {
    bingeGroup?: string;
    notWebReady?: boolean;
    cached?: boolean;
    filename?: string;
    videoHash?: string;
    videoSize?: number;
    proxyHeaders?: {
      request?: Record<string, string>;
      response?: Record<string, string>;
    };
  };
}

export interface StremioAddonStreams {
  installationId: string;
  addonId: string;
  addonName: string;
  streams: StremioStream[];
  /** Set when this addon failed. Other addons' results are still returned. */
  error?: string;
}

export type PlayabilityReason =
  | 'torrent' | 'nzb' | 'archive' | 'external' | 'notWebReady' | 'container' | 'videoCodec'
  | 'audioCodec' | 'hdrFormat' | 'unknownSource';

/** Whether this browser can play a stream. Web addon playback is label-only. */
export interface BrowserPlayability {
  playable: boolean;
  reason?: PlayabilityReason;
  /** Short user-facing explanation, shown when `playable` is false. */
  label?: string;
}

export interface RankStreamsOptions {
  /** Matches an earlier stream's bingeGroup first, for next-episode continuity. */
  preferredBingeGroup?: string;
}

/** Router state for `/player/stream:...`. The route itself is owned by P3. */
export interface StreamPlayerState {
  stream: StremioStream;
  identity: StremioContentIdentity;
  title: string;
  alternatives?: StremioStream[];
}

export interface StremioRequestOptions {
  signal?: AbortSignal;
}

export interface StremioStreamRequestOptions extends StremioRequestOptions {
  /** Called as each addon answers, in arrival order, so a list can fill in progressively. */
  onAddonResult?: (result: StremioAddonStreams) => void;
}

export interface StremioSubtitleRequestOptions extends StremioRequestOptions {
  /** The playing stream, whose file details let addons return release-matched subtitles. */
  stream?: StremioStream;
}
