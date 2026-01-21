// Main entry point
export { FlixorCore } from './FlixorCore';
export type { FlixorCoreConfig, ActiveProfile } from './FlixorCore';

// Storage interfaces
export type { IStorage } from './storage/IStorage';
export type { ISecureStorage } from './storage/ISecureStorage';
export type { ICache } from './storage/ICache';
export { CacheTTL } from './storage/ICache';

// Services
export {
  PlexAuthService,
  PlexServerService,
  PlexTvService,
  TMDBService,
  TraktService,
} from './services';

// Models - Plex
export type {
  PlexPin,
  PlexUser,
  PlexHomeUser,
  PlexServer,
  PlexConnection,
  PlexLibrary,
  PlexMediaItem,
  PlexMedia,
  PlexPart,
  PlexStream,
  PlexMarker,
  PlexLibraryOptions,
  PlexMediaContainer,
  PlexUltraBlurColors,
  PlexUltraBlurResponse,
  ContinueWatchingResult,
} from './models/plex';
export { getVersionString } from './models/plex';

// Models - TMDB
export type {
  TMDBMedia,
  TMDBMovieDetails,
  TMDBTVDetails,
  TMDBSeason,
  TMDBEpisode,
  TMDBGenre,
  TMDBProductionCompany,
  TMDBProductionCountry,
  TMDBSpokenLanguage,
  TMDBCollection,
  TMDBCreator,
  TMDBNetwork,
  TMDBCredits,
  TMDBCastMember,
  TMDBCrewMember,
  TMDBExternalIds,
  TMDBVideosResponse,
  TMDBVideo,
  TMDBImages,
  TMDBImage,
  TMDBResultsResponse,
  TMDBPerson,
  TMDBPersonCredits,
  TMDBPersonCreditItem,
} from './models/tmdb';
export { TMDBImageSize } from './models/tmdb';

// Models - Trakt
export type {
  TraktTokens,
  TraktDeviceCode,
  TraktIds,
  TraktMovie,
  TraktShow,
  TraktSeason,
  TraktEpisode,
  TraktTrendingMovie,
  TraktTrendingShow,
  TraktPopularMovie,
  TraktPopularShow,
  TraktWatchlistItem,
  TraktHistoryItem,
  TraktCollectionItem,
  TraktRatingItem,
  TraktRecommendation,
  TraktUser,
  TraktStats,
} from './models/trakt';

// Models - Browse
export type {
  BrowseContext,
  BrowseItem,
  BrowseResult,
  TMDBBrowseKind,
  TraktBrowseKind,
} from './models/browse';
