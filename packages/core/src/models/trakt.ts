// Trakt OAuth Tokens
export interface TraktTokens {
  access_token: string;
  token_type: string;
  expires_in: number;
  refresh_token: string;
  scope: string;
  created_at: number;
}

// Trakt Device Code (for TV/device auth flow)
export interface TraktDeviceCode {
  device_code: string;
  user_code: string;
  verification_url: string;
  expires_in: number;
  interval: number;
}

// Trakt IDs
export interface TraktIds {
  trakt?: number;
  slug?: string;
  imdb?: string;
  tmdb?: number;
  tvdb?: number;
}

// Trakt Movie
export interface TraktMovie {
  title: string;
  year?: number;
  ids: TraktIds;
  tagline?: string;
  overview?: string;
  released?: string;
  runtime?: number;
  country?: string;
  trailer?: string | null;
  homepage?: string | null;
  status?: string;
  rating?: number;
  votes?: number;
  comment_count?: number;
  updated_at?: string;
  language?: string;
  genres?: string[];
  certification?: string;
}

// Trakt Show
export interface TraktShow {
  title: string;
  year?: number;
  ids: TraktIds;
  overview?: string;
  first_aired?: string;
  runtime?: number;
  certification?: string;
  network?: string;
  country?: string;
  trailer?: string | null;
  homepage?: string | null;
  status?: string;
  rating?: number;
  votes?: number;
  comment_count?: number;
  updated_at?: string;
  language?: string;
  genres?: string[];
  aired_episodes?: number;
}

// Trakt Season
export interface TraktSeason {
  number: number;
  ids: TraktIds;
  rating?: number;
  votes?: number;
  episode_count?: number;
  aired_episodes?: number;
  title?: string;
  overview?: string;
  first_aired?: string;
  network?: string;
}

// Trakt Episode
export interface TraktEpisode {
  season: number;
  number: number;
  title?: string;
  ids: TraktIds;
  overview?: string;
  rating?: number;
  votes?: number;
  comment_count?: number;
  first_aired?: string;
  runtime?: number;
}

// Trending item wrapper
export interface TraktTrendingMovie {
  watchers: number;
  movie: TraktMovie;
}

export interface TraktTrendingShow {
  watchers: number;
  show: TraktShow;
}

// Popular item (no watchers count)
export type TraktPopularMovie = TraktMovie;
export type TraktPopularShow = TraktShow;

// Watchlist item
export interface TraktWatchlistItem {
  rank?: number;
  listed_at: string;
  type: 'movie' | 'show' | 'season' | 'episode';
  movie?: TraktMovie;
  show?: TraktShow;
  season?: TraktSeason;
  episode?: TraktEpisode;
}

// History item
export interface TraktHistoryItem {
  id: number;
  watched_at: string;
  action: 'watch' | 'scrobble';
  type: 'movie' | 'episode';
  movie?: TraktMovie;
  show?: TraktShow;
  episode?: TraktEpisode;
}

// Collection item
export interface TraktCollectionItem {
  collected_at: string;
  movie?: TraktMovie;
  show?: TraktShow;
}

// Rating item
export interface TraktRatingItem {
  rated_at: string;
  rating: number;
  type: 'movie' | 'show' | 'season' | 'episode';
  movie?: TraktMovie;
  show?: TraktShow;
  season?: TraktSeason;
  episode?: TraktEpisode;
}

// Recommendation
export interface TraktRecommendation {
  movie?: TraktMovie;
  show?: TraktShow;
}

// User
export interface TraktUser {
  username: string;
  private: boolean;
  name?: string;
  vip?: boolean;
  vip_ep?: boolean;
  ids: {
    slug: string;
    uuid?: string;
  };
  joined_at?: string;
  location?: string | null;
  about?: string | null;
  gender?: string | null;
  age?: number | null;
  images?: {
    avatar?: {
      full?: string;
    };
  };
}

// Playback Progress Item (for Continue Watching)
export interface TraktPlaybackItem {
  id: number;
  progress: number; // 0-100 percentage
  paused_at: string;
  type: 'movie' | 'episode';
  movie?: TraktMovie;
  show?: TraktShow;
  episode?: TraktEpisode;
}

// Stats
export interface TraktStats {
  movies: {
    plays: number;
    watched: number;
    minutes: number;
    collected: number;
    ratings: number;
    comments: number;
  };
  shows: {
    watched: number;
    collected: number;
    ratings: number;
    comments: number;
  };
  seasons: {
    ratings: number;
    comments: number;
  };
  episodes: {
    plays: number;
    watched: number;
    minutes: number;
    collected: number;
    ratings: number;
    comments: number;
  };
}

// Sync request body for /sync/history, /sync/ratings (and their /remove variants)
// and /users/me/lists/{id}/items. Any one id is enough. A show with no seasons
// means the whole show; a season with no episodes means the whole season.
export type TraktSyncIds = TraktIds;

export interface TraktSyncEpisode {
  number: number;
  watched_at?: string;
  rating?: number;
}

export interface TraktSyncSeason {
  number: number;
  episodes?: TraktSyncEpisode[];
  watched_at?: string;
  rating?: number;
}

export interface TraktSyncShow {
  ids: TraktSyncIds;
  seasons?: TraktSyncSeason[];
  watched_at?: string;
  rating?: number;
}

export interface TraktSyncMovie {
  ids: TraktSyncIds;
  watched_at?: string;
  rating?: number;
}

export interface TraktSyncItems {
  movies?: TraktSyncMovie[];
  shows?: TraktSyncShow[];
  /** Episodes addressed by their own ids. Prefer nesting under `shows`. */
  episodes?: Array<{ ids: TraktSyncIds; watched_at?: string; rating?: number }>;
}

// Response of the sync and list-item endpoints. Counts are keyed by
// "movies", "shows", "seasons", "episodes".
export interface TraktSyncResult {
  added?: Record<string, number>;
  deleted?: Record<string, number>;
  updated?: Record<string, number>;
  existing?: Record<string, number>;
  not_found?: Record<string, unknown[]>;
}

// Watched progress for a show (/shows/{id}/progress/watched)
export interface TraktShowProgressEpisode {
  number: number;
  completed: boolean;
  last_watched_at?: string | null;
}

export interface TraktShowProgressSeason {
  number: number;
  title?: string | null;
  aired: number;
  completed: number;
  episodes: TraktShowProgressEpisode[];
}

export interface TraktShowProgress {
  aired: number;
  completed: number;
  last_watched_at?: string | null;
  reset_at?: string | null;
  seasons: TraktShowProgressSeason[];
  next_episode?: TraktEpisode | null;
  last_episode?: TraktEpisode | null;
}

// One page of a paginated endpoint, with totals from the X-Pagination-* headers
export interface TraktPage<T> {
  items: T[];
  page: number;
  limit: number;
  pageCount: number;
  itemCount: number;
}

// Comments
export type TraktCommentSort =
  | 'newest'
  | 'oldest'
  | 'likes'
  | 'replies'
  | 'highest'
  | 'lowest'
  | 'plays';

/**
 * What to load comments for. Ids may be a Trakt id, Trakt slug or IMDb id.
 * TMDB ids are NOT accepted; resolve them with lookupByTmdb first.
 */
export type TraktCommentTarget =
  | { type: 'movie'; id: string | number }
  | { type: 'show'; id: string | number }
  | { type: 'season'; showId: string | number; season: number }
  | { type: 'episode'; showId: string | number; season: number; episode: number };

export interface TraktCommentUser {
  username?: string;
  name?: string | null;
  private?: boolean;
  vip?: boolean;
  ids?: { slug?: string | null };
  images?: { avatar?: { full?: string } };
}

export interface TraktComment {
  id: number;
  parent_id?: number;
  created_at?: string;
  updated_at?: string;
  comment: string;
  spoiler: boolean;
  review: boolean;
  replies: number;
  likes: number;
  user_rating?: number | null;
  user_stats?: { rating?: number | null; play_count?: number; completed_count?: number };
  user?: TraktCommentUser;
}

// Personal lists
export type TraktListPrivacy = 'private' | 'link' | 'friends' | 'public';

export interface TraktUserList {
  name: string;
  description?: string | null;
  privacy?: TraktListPrivacy;
  share_link?: string;
  display_numbers?: boolean;
  allow_comments?: boolean;
  sort_by?: string;
  sort_how?: string;
  created_at?: string;
  updated_at?: string;
  item_count: number;
  comment_count?: number;
  likes?: number;
  ids: { trakt: number; slug?: string | null };
}

export interface TraktListEntry {
  /** List item id (unique within the list). */
  id: number;
  rank?: number;
  listed_at?: string;
  notes?: string | null;
  type: 'movie' | 'show' | 'season' | 'episode' | 'person';
  movie?: TraktMovie;
  show?: TraktShow;
  season?: TraktSeason;
  episode?: TraktEpisode;
}
