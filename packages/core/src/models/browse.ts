// Browse context types for row-level browsing

export type TMDBBrowseKind = 'trending' | 'recommendations' | 'similar';
export type TraktBrowseKind = 'trending' | 'watchlist' | 'history' | 'recommendations';

export type BrowseContext =
  | { type: 'plexDirectory'; path: string; title: string }
  | { type: 'plexLibrary'; libraryKey: string; title: string }
  | { type: 'plexWatchlist' }
  | { type: 'tmdb'; kind: TMDBBrowseKind; mediaType: 'movie' | 'tv'; id?: string; title: string }
  | { type: 'trakt'; kind: TraktBrowseKind; mediaType: 'movie' | 'tv'; title: string };

export interface BrowseItem {
  id: string;        // Format: "plex:12345" or "tmdb:movie:98765"
  title: string;
  image?: string;    // Full image URL
  year?: number;
  subtitle?: string; // e.g., "S1E1" for episodes
}

export interface BrowseResult {
  items: BrowseItem[];
  hasMore: boolean;
  totalCount?: number;
}
