import type { MutableRefObject } from 'react';
import type { StremioContentIdentity, StremioStream, StremioSubtitle } from '@/stremio';

export type StreamKind = 'hls' | 'dash' | 'direct';

/** Times in seconds. `end` is resolved, so open-ended segments are never stored here. */
export interface PlayerMarker {
  id: string;
  type: string;
  start: number;
  end: number;
  /** Plex's flag for the last credits marker of an episode. */
  final?: boolean;
}

export interface PlayerChapter {
  id: string;
  title: string;
  start: number;
}

export interface PlayerMedia {
  kind: 'movie' | 'episode';
  /** Movie title, or the episode's own title. */
  title: string;
  showTitle?: string;
  season?: number;
  episode?: number;
  poster?: string;
  /** Key for per-title track preferences. */
  itemKey: string;
  seriesKey?: string;
}

export interface TrackOption {
  id: string;
  label: string;
  language?: string;
  languageCode?: string;
  forced?: boolean;
  default?: boolean;
}

export interface SubtitleOption extends TrackOption {
  /** `client` tracks are parsed and drawn here. `burn` tracks need a Plex transcode. */
  delivery: 'client' | 'burn';
  url?: string;
  format?: string;
  addonName?: string;
  /** Set for addon subtitles, which the Stremio service downloads. */
  addonSubtitle?: StremioSubtitle;
}

export interface QualityOption {
  label: string;
  value: string | number;
  note?: string;
  noteTone?: 'muted' | 'warn' | 'good';
}

export interface EpisodeEntry {
  key: string;
  season: number;
  episode: number;
  title: string;
  summary?: string;
  thumb?: string;
  /** 0-1 watched fraction. */
  progress?: number;
  isCurrent: boolean;
}

export interface EpisodeBrowser {
  seasons: number[];
  season: number | null;
  episodes: EpisodeEntry[];
  loading: boolean;
  /** Resets to the playing season and loads the season list. */
  open: () => void;
  selectSeason: (season: number) => void;
  play: (entry: EpisodeEntry) => void;
}

export interface NextEpisode {
  title: string;
  label: string;
  summary?: string;
  thumb?: string;
}

export interface SessionError {
  message: string;
  /** Offers "Choose another source". */
  canChooseSource?: boolean;
  /** Offers a link to the title's details page. */
  detailsPath?: string;
}

/** Mutable playback position, written by the shell and read by sessions without re-rendering. */
export interface PlayerClock {
  time: MutableRefObject<number>;
  duration: MutableRefObject<number>;
  playing: MutableRefObject<boolean>;
  buffering: MutableRefObject<boolean>;
  /** Set by the shell, so sessions can hold playback during a lookup. */
  pause: MutableRefObject<() => void>;
  resume: MutableRefObject<() => void>;
}

export interface TraktMediaInfo {
  type: 'movie' | 'episode';
  title: string;
  year?: number;
  imdbId?: string;
  tmdbId?: number;
  tvdbId?: number;
  season?: number;
  episode?: number;
  episodeTitle?: string;
  duration?: number;
}

export interface SourcesRequest {
  identity: StremioContentIdentity | null;
  title: string;
  onSelect: (stream: StremioStream) => void;
  /** Marks the source playing now in the list. */
  currentUrl?: string;
}

/** What the shell needs from a source. Plex and addon streams both produce one of these. */
export interface PlayerSession {
  kind: 'plex' | 'stream';
  media: PlayerMedia | null;
  src: string;
  /** Undefined means decide from the URL. */
  streamKind?: StreamKind;
  crossOrigin: 'anonymous' | null;
  startAt?: number;
  loading: boolean;
  error: SessionError | null;
  /** Transient banner, such as a codec fallback. */
  notice: string | null;
  /** Blocking status while the session works, shown over the player. */
  status: { message: string; onCancel?: () => void } | null;

  markers: PlayerMarker[];
  chapters: PlayerChapter[];
  /** Movies leave for Details at the credits rather than running them out. */
  exitAtCredits: boolean;
  scrobbleMedia: TraktMediaInfo | null;

  quality: {
    options: QualityOption[];
    value: string | number;
    set: (value: string | number) => void;
    warning?: string;
  } | null;
  audio: {
    options: TrackOption[];
    selected: string | null;
    select: (id: string) => void;
  };
  /** Subtitle tracks known to this source, without an "Off" entry. */
  subtitles: SubtitleOption[];
  /** Track Plex or the remembered choice already applied, if any. */
  initialSubtitleId: string | null;
  /** Switches a `burn` track on, or off with `'0'`. Restarts the Plex stream. */
  setBurnedSubtitle: (id: string) => void;

  previewUrl?: (ms: number) => string;
  stats: Record<string, unknown>;

  next: NextEpisode | null;
  playNext: () => void;
  /** Called about a minute before the next-episode trigger, so play-next is instant. */
  prefetchNext?: () => void;
  browser: EpisodeBrowser | null;
  openSources?: () => void;

  sourcesRequest: SourcesRequest | null;
  closeSources: () => void;

  onEngineError: (message: string) => void;
  onCodecError: (message: string) => void;
  onEnded: () => void;
  onReady?: () => void;
  onAudioTracks?: (tracks: TrackOption[]) => void;
  /** Index for the HLS engine's audio track, when the stream has several. */
  audioTrackIndex?: number;

  /** Stops playback and reports position. Resolves before navigating away. */
  exit: () => void;
  goToDetails: () => void;
}
