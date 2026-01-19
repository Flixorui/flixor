// Plex PIN Auth
export interface PlexPin {
  id: number;
  code: string;
}

// Plex User
export interface PlexUser {
  id: number;
  uuid: string;
  username: string;
  email?: string;
  thumb?: string;
  title?: string;
}

// Plex Server (from plex.tv resources)
export interface PlexServer {
  id: string; // clientIdentifier
  name: string;
  owned: boolean;
  accessToken: string;
  connections: PlexConnection[];
  publicAddress?: string;
  presence?: boolean;
}

export interface PlexConnection {
  uri: string;
  protocol: string;
  local: boolean;
  relay: boolean;
  IPv6: boolean;
}

// Plex Library
export interface PlexLibrary {
  key: string;
  title: string;
  type: 'movie' | 'show' | 'artist' | 'photo';
  agent?: string;
  scanner?: string;
  language?: string;
  uuid?: string;
}

// Plex Media Item (metadata)
export interface PlexMediaItem {
  ratingKey: string;
  key: string;
  guid?: string;
  type: 'movie' | 'show' | 'season' | 'episode';
  title: string;
  originalTitle?: string;
  summary?: string;
  year?: number;
  thumb?: string;
  art?: string;
  banner?: string;
  theme?: string;
  duration?: number;
  viewOffset?: number;
  viewCount?: number;
  lastViewedAt?: number;
  addedAt?: number;
  updatedAt?: number;

  // Ratings
  rating?: number;
  audienceRating?: number;
  contentRating?: string;
  Rating?: Array<{ image?: string; value?: number; type?: string }>;

  // TV Show specific
  grandparentRatingKey?: string;
  grandparentTitle?: string;
  grandparentThumb?: string;
  grandparentArt?: string;
  parentRatingKey?: string;
  parentTitle?: string;
  parentThumb?: string;
  parentIndex?: number;
  index?: number;

  // Season specific
  leafCount?: number;
  viewedLeafCount?: number;

  // Media info
  Media?: PlexMedia[];

  // GUIDs for external matching
  Guid?: Array<{ id: string }>;

  // Markers (intro/credits)
  Marker?: PlexMarker[];
}

export interface PlexMedia {
  id: number;
  duration: number;
  bitrate?: number;
  width?: number;
  height?: number;
  aspectRatio?: number;
  audioChannels?: number;
  audioCodec?: string;
  videoCodec?: string;
  videoResolution?: string;
  container?: string;
  videoFrameRate?: string;
  editionTitle?: string; // e.g., "Theatrical Cut", "Director's Cut", "Extended Edition"
  Part?: PlexPart[];
}

export interface PlexPart {
  id: number;
  key: string;
  duration: number;
  file?: string;
  size?: number;
  container?: string;
  videoProfile?: string;
  Stream?: PlexStream[];
}

export interface PlexStream {
  id: number;
  streamType: number; // 1=video, 2=audio, 3=subtitle
  codec?: string;
  index?: number;
  bitrate?: number;
  language?: string;
  languageCode?: string;
  title?: string;
  displayTitle?: string;
  selected?: boolean;
  default?: boolean;
  forced?: boolean;
}

export interface PlexMarker {
  id?: number;  // Plex API returns Int, not String
  type: 'intro' | 'credits' | 'commercial';
  startTimeOffset: number;
  endTimeOffset: number;
}

// Library query options
export interface PlexLibraryOptions {
  type?: number; // 1=movie, 2=show, 4=episode
  sort?: string;
  limit?: number;
  offset?: number;
  filter?: Record<string, string>;
}

// API Response wrappers
export interface PlexMediaContainer<T> {
  MediaContainer: {
    size?: number;
    totalSize?: number;
    offset?: number;
    Metadata?: T[];
    Directory?: T[];
  };
}

// UltraBlur Colors
export interface PlexUltraBlurColors {
  topLeft: string;
  topRight: string;
  bottomRight: string;
  bottomLeft: string;
}

export interface PlexUltraBlurResponse {
  MediaContainer: {
    size?: number;
    UltraBlurColors?: PlexUltraBlurColors[];
  };
}

// Continue Watching result with deduplication info
export interface ContinueWatchingResult {
  items: PlexMediaItem[];
  itemsWithMultipleVersions: Set<string>; // ratingKeys that had duplicates across libraries
}

/**
 * Get version string from media info (resolution/HDR/audio)
 * Used for Continue Watching to show which version user was watching
 * e.g., "4K · Dolby Vision · Atmos"
 */
export function getVersionString(media?: PlexMedia[]): string | null {
  if (!media || media.length === 0) return null;
  const m = media[0];

  const parts: string[] = [];

  // Resolution
  if (m.width && m.width >= 3800) parts.push('4K');
  else if (m.width && m.width >= 1900) parts.push('1080p');
  else if (m.width && m.width >= 1200) parts.push('720p');

  // HDR (from videoProfile in Part)
  const videoProfile = m.Part?.[0]?.videoProfile?.toLowerCase() || '';
  if (videoProfile.includes('dolby vision') || videoProfile.includes('dovi')) {
    parts.push('Dolby Vision');
  } else if (videoProfile.includes('hdr10+')) {
    parts.push('HDR10+');
  } else if (videoProfile.includes('hdr')) {
    parts.push('HDR');
  }

  // Audio
  if (m.audioChannels && m.audioChannels >= 8) {
    parts.push('Atmos');
  } else if (m.audioChannels && m.audioChannels >= 6) {
    parts.push('5.1');
  }

  return parts.length > 0 ? parts.join(' · ') : null;
}
