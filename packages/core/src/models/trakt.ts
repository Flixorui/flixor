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
