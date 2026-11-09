export type StremioRequestType = 'movie' | 'series';
export type StremioPlaybackMediaType = 'movie' | 'episode';
export type StreamProvider = 'stremio';

export type StremioSourceType =
  | 'url'
  | 'externalUrl'
  | 'ytId'
  | 'infoHash'
  | 'nzbUrl'
  | 'archive'
  | 'unknown';

export interface StremioResourceObject {
  name: string;
  types?: string[];
  idPrefixes?: string[];
}

export type StremioResource = string | StremioResourceObject;

export interface StremioAddonManifest {
  id: string;
  installationId: string;
  name: string;
  version: string;
  description?: string;
  url?: string;
  originalUrl?: string;
  transportUrl?: string;
  resources?: StremioResource[];
  types?: string[];
  idPrefixes?: string[];
  behaviorHints?: {
    configurable?: boolean;
    configurationRequired?: boolean;
    configurationURL?: string;
    adult?: boolean;
    p2p?: boolean;
  };
  config?: Array<{
    key: string;
    type: 'text' | 'number' | 'password' | 'checkbox' | 'select';
    default?: string;
    title?: string;
    options?: string[];
    required?: boolean;
  }>;
}

export interface StremioSubtitleCandidate {
  id: string;
  url: string;
  lang: string;
  format?: 'srt' | 'vtt' | 'ass' | 'ssa';
  addonId?: string;
  addonName?: string;
}

export interface StremioStreamBehaviorHints {
  bingeGroup?: string;
  notWebReady?: boolean;
  countryWhitelist?: string[];
  cached?: boolean;
  proxyHeaders?: {
    request?: Record<string, string>;
    response?: Record<string, string>;
  };
  videoHash?: string;
  videoSize?: number;
  filename?: string;
}

export interface StremioPlayableStream {
  url?: string;
  externalUrl?: string;
  ytId?: string;
  infoHash?: string;
  nzbUrl?: string;
  rarUrls?: Array<{ url: string; bytes?: number }>;
  zipUrls?: Array<{ url: string; bytes?: number }>;
  '7zipUrls'?: Array<{ url: string; bytes?: number }>;
  tgzUrls?: Array<{ url: string; bytes?: number }>;
  tarUrls?: Array<{ url: string; bytes?: number }>;
  fileIdx?: number;
  fileMustInclude?: string;
  servers?: string[];
  name?: string;
  title?: string;
  description?: string;
  addonId?: string;
  addonName?: string;
  addonInstallationId?: string;
  size?: number;
  isFree?: boolean;
  isDebrid?: boolean;
  quality?: string;
  headers?: Record<string, string>;
  subtitles?: StremioSubtitleCandidate[];
  sources?: string[];
  behaviorHints?: StremioStreamBehaviorHints;
  streamIndex: number;
  sourceType: StremioSourceType;
  playable: boolean;
  disabledReason?: string;
}

export interface StremioAddonStreamResult {
  addonId: string;
  addonName: string;
  installationId: string;
  streams: StremioPlayableStream[];
  error?: string;
}

export interface StremioContentIdentity {
  requestType: StremioRequestType;
  baseId: string;
  requestId: string;
  imdbId?: string;
  tmdbId?: number;
  seasonNumber?: number;
  episodeNumber?: number;
  source: 'plex-guid' | 'tmdb' | 'tmdb-external-ids' | 'player';
}

export interface CachedPlaybackSource {
  kind: 'stream';
  provider: 'stremio';
  contentKey: string;
  uri: string;
  headers?: Record<string, string>;
  title: string;
  mediaType: StremioPlaybackMediaType;
  imdbId?: string;
  tmdbId?: number;
  seasonNumber?: number;
  episodeNumber?: number;
  episodeTitle?: string;
  backdrop?: string;
  streamLabel?: string;
  addonId?: string;
  addonName?: string;
  externalSubtitles?: StremioSubtitleCandidate[];
  availableStreams?: StremioPlayableStream[];
  stremioIdentity?: StremioContentIdentity;
  savedAt: number;
  expiresAt: number;
}

export interface ResumeState {
  contentKey: string;
  positionMs: number;
  durationMs: number;
  updatedAt: number;
}

export interface GenericStreamParams {
  type: 'stream';
  provider: StreamProvider;
  uri: string;
  headers?: Record<string, string>;
  title: string;
  mediaType: StremioPlaybackMediaType;
  contentKey: string;
  imdbId?: string;
  tmdbId?: number;
  seasonNumber?: number;
  episodeNumber?: number;
  episodeTitle?: string;
  backdrop?: string;
  streamLabel?: string;
  streamAddonId?: string;
  streamAddonName?: string;
  availableStreams?: StremioPlayableStream[];
  externalSubtitles?: StremioSubtitleCandidate[];
  resumePositionMs?: number;
  stremioIdentity?: StremioContentIdentity;
  /** Replacement sources already tried for this playback. */
  recoveryAttempts?: number;
  /** URLs that failed during this playback. */
  failedStreamUrls?: string[];
  /** `availableStreams` was re-fetched during recovery, so later attempts reuse it. */
  recoverySourcesFetched?: boolean;
  /** Subtitle addons were cut off by a deadline; the player asks again after load. */
  subtitlesIncomplete?: boolean;
}

export interface StremioMetaVideo {
  id?: string;
  title?: string;
  season?: number;
  episode?: number;
  released?: string;
  overview?: string;
  thumbnail?: string;
}

export interface StremioMetaDetail {
  id: string;
  name?: string;
  videos?: StremioMetaVideo[];
}

export interface SubtitleCueSegment {
  text: string;
  italic?: boolean;
  bold?: boolean;
  underline?: boolean;
  color?: string;
}

export interface SubtitleCue {
  startTime: number;
  endTime: number;
  text: string;
  segments?: SubtitleCueSegment[][];
}
