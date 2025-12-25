// TMDB Media (from search/trending results)
export interface TMDBMedia {
  id: number;
  media_type?: 'movie' | 'tv' | 'person';
  title?: string; // Movies
  name?: string; // TV shows
  original_title?: string;
  original_name?: string;
  overview?: string;
  poster_path?: string | null;
  backdrop_path?: string | null;
  release_date?: string; // Movies
  first_air_date?: string; // TV
  vote_average?: number;
  vote_count?: number;
  popularity?: number;
  genre_ids?: number[];
  original_language?: string;
  adult?: boolean;
}

// TMDB Movie Details
export interface TMDBMovieDetails extends TMDBMedia {
  budget?: number;
  revenue?: number;
  runtime?: number;
  status?: string;
  tagline?: string;
  genres?: TMDBGenre[];
  production_companies?: TMDBProductionCompany[];
  production_countries?: TMDBProductionCountry[];
  spoken_languages?: TMDBSpokenLanguage[];
  belongs_to_collection?: TMDBCollection | null;
  imdb_id?: string;
  homepage?: string;

  // Appended responses
  credits?: TMDBCredits;
  external_ids?: TMDBExternalIds;
  videos?: TMDBVideosResponse;
  images?: TMDBImages;
  recommendations?: TMDBResultsResponse<TMDBMedia>;
  similar?: TMDBResultsResponse<TMDBMedia>;
}

// TMDB TV Details
export interface TMDBTVDetails extends TMDBMedia {
  episode_run_time?: number[];
  in_production?: boolean;
  last_air_date?: string;
  number_of_episodes?: number;
  number_of_seasons?: number;
  status?: string;
  tagline?: string;
  type?: string;
  genres?: TMDBGenre[];
  created_by?: TMDBCreator[];
  networks?: TMDBNetwork[];
  production_companies?: TMDBProductionCompany[];
  seasons?: TMDBSeason[];
  last_episode_to_air?: TMDBEpisode;
  next_episode_to_air?: TMDBEpisode | null;

  // Appended responses
  credits?: TMDBCredits;
  external_ids?: TMDBExternalIds;
  videos?: TMDBVideosResponse;
  images?: TMDBImages;
  recommendations?: TMDBResultsResponse<TMDBMedia>;
  similar?: TMDBResultsResponse<TMDBMedia>;
}

export interface TMDBSeason {
  id: number;
  name: string;
  overview?: string;
  poster_path?: string | null;
  season_number: number;
  episode_count?: number;
  air_date?: string;
  episodes?: TMDBEpisode[];
}

export interface TMDBEpisode {
  id: number;
  name: string;
  overview?: string;
  still_path?: string | null;
  air_date?: string;
  episode_number: number;
  season_number: number;
  vote_average?: number;
  vote_count?: number;
  runtime?: number;
}

// Supporting types
export interface TMDBGenre {
  id: number;
  name: string;
}

export interface TMDBProductionCompany {
  id: number;
  name: string;
  logo_path?: string | null;
  origin_country?: string;
}

export interface TMDBProductionCountry {
  iso_3166_1: string;
  name: string;
}

export interface TMDBSpokenLanguage {
  iso_639_1: string;
  name: string;
  english_name?: string;
}

export interface TMDBCollection {
  id: number;
  name: string;
  poster_path?: string | null;
  backdrop_path?: string | null;
}

export interface TMDBCreator {
  id: number;
  name: string;
  profile_path?: string | null;
  credit_id?: string;
}

export interface TMDBNetwork {
  id: number;
  name: string;
  logo_path?: string | null;
  origin_country?: string;
}

// Credits
export interface TMDBCredits {
  cast?: TMDBCastMember[];
  crew?: TMDBCrewMember[];
}

export interface TMDBCastMember {
  id: number;
  name: string;
  character?: string;
  profile_path?: string | null;
  order?: number;
  known_for_department?: string;
}

export interface TMDBCrewMember {
  id: number;
  name: string;
  job?: string;
  department?: string;
  profile_path?: string | null;
}

// External IDs
export interface TMDBExternalIds {
  imdb_id?: string | null;
  tvdb_id?: number | null;
  facebook_id?: string | null;
  instagram_id?: string | null;
  twitter_id?: string | null;
}

// Videos
export interface TMDBVideosResponse {
  results?: TMDBVideo[];
}

export interface TMDBVideo {
  id: string;
  key: string;
  name: string;
  site: string;
  size?: number;
  type?: string;
  official?: boolean;
  published_at?: string;
}

// Images
export interface TMDBImages {
  backdrops?: TMDBImage[];
  posters?: TMDBImage[];
  logos?: TMDBImage[];
}

export interface TMDBImage {
  file_path: string;
  aspect_ratio?: number;
  width?: number;
  height?: number;
  vote_average?: number;
  vote_count?: number;
  iso_639_1?: string | null;
}

// API Response wrapper
export interface TMDBResultsResponse<T> {
  page?: number;
  total_pages?: number;
  total_results?: number;
  results: T[];
}

// Person
export interface TMDBPerson {
  id: number;
  name: string;
  biography?: string;
  birthday?: string;
  deathday?: string;
  place_of_birth?: string;
  profile_path?: string;
  known_for_department?: string;
  popularity?: number;
  also_known_as?: string[];
  gender?: number;
  adult?: boolean;
  imdb_id?: string;
  homepage?: string;
}

export interface TMDBPersonCredits {
  cast?: TMDBPersonCreditItem[];
  crew?: TMDBPersonCreditItem[];
}

export interface TMDBPersonCreditItem {
  id: number;
  title?: string;
  name?: string;
  poster_path?: string;
  backdrop_path?: string;
  media_type: 'movie' | 'tv';
  character?: string;
  job?: string;
  release_date?: string;
  first_air_date?: string;
  vote_average?: number;
  vote_count?: number;
}

// Image sizes
export const TMDBImageSize = {
  POSTER: {
    SMALL: 'w185',
    MEDIUM: 'w342',
    LARGE: 'w500',
    ORIGINAL: 'original',
  },
  BACKDROP: {
    SMALL: 'w300',
    MEDIUM: 'w780',
    LARGE: 'w1280',
    ORIGINAL: 'original',
  },
  PROFILE: {
    SMALL: 'w45',
    MEDIUM: 'w185',
    LARGE: 'h632',
    ORIGINAL: 'original',
  },
  LOGO: {
    SMALL: 'w92',
    MEDIUM: 'w185',
    LARGE: 'w500',
    ORIGINAL: 'original',
  },
} as const;
