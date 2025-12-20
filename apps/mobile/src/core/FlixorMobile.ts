/**
 * FlixorMobile - Mobile API wrapper around FlixorCore
 *
 * This provides a similar interface to the old MobileApi class for easier migration,
 * while using the new standalone FlixorCore under the hood.
 */

import { FlixorCore, type PlexMediaItem, type TMDBMedia } from '@flixor/core';
import { getFlixorCore, initializeFlixorCore } from './index';

export interface MobileHomeData {
  continueWatching: PlexMediaItem[];
  recentlyAdded: PlexMediaItem[];
  onDeck: PlexMediaItem[];
  trending: TMDBMedia[];
}

export interface LibraryItemsResult {
  items: PlexMediaItem[];
  totalSize: number;
  page: number;
  pageSize: number;
}

/**
 * Compatibility layer for the mobile app
 * Wraps FlixorCore to provide similar API to the old backend-based MobileApi
 */
export class FlixorMobile {
  private core: FlixorCore;

  constructor(core: FlixorCore) {
    this.core = core;
  }

  static async initialize(): Promise<FlixorMobile> {
    const core = await initializeFlixorCore();
    return new FlixorMobile(core);
  }

  // ============================================
  // Authentication
  // ============================================

  get isPlexAuthenticated(): boolean {
    return this.core.isPlexAuthenticated;
  }

  get isTraktAuthenticated(): boolean {
    return this.core.isTraktAuthenticated;
  }

  get isConnected(): boolean {
    return this.core.isPlexServerConnected;
  }

  async createPlexPin() {
    return this.core.createPlexPin();
  }

  async waitForPlexPin(
    pinId: number,
    onPoll?: () => void
  ): Promise<string> {
    return this.core.waitForPlexPin(pinId, { onPoll });
  }

  async getServers() {
    return this.core.getPlexServers();
  }

  async connectToServer(server: Awaited<ReturnType<typeof this.getServers>>[0]) {
    return this.core.connectToPlexServer(server);
  }

  async getPlexUser() {
    if (!this.core.isPlexAuthenticated) return null;
    // User info is embedded in the token verification
    // We can get it from the auth service
    const token = (this.core as any).plexToken;
    if (!token) return null;
    return this.core.plexAuth.getUser(token);
  }

  async logout() {
    await this.core.signOutPlex();
  }

  // ============================================
  // Trakt Authentication
  // ============================================

  async createTraktDeviceCode() {
    return this.core.createTraktDeviceCode();
  }

  async waitForTraktDeviceCode(
    deviceCode: Awaited<ReturnType<typeof this.createTraktDeviceCode>>,
    onPoll?: () => void
  ) {
    return this.core.waitForTraktDeviceCode(deviceCode, { onPoll });
  }

  async getTraktProfile() {
    return this.core.trakt.getProfile();
  }

  async logoutTrakt() {
    await this.core.signOutTrakt();
  }

  // ============================================
  // Home Screen Data
  // ============================================

  async getHomeData(): Promise<MobileHomeData> {
    const [continueWatching, recentlyAdded, onDeck, trendingMovies, trendingShows] =
      await Promise.all([
        this.core.plexServer.getContinueWatching().catch(() => []),
        this.core.plexServer.getRecentlyAdded().catch(() => []),
        this.core.plexServer.getOnDeck().catch(() => []),
        this.core.tmdb.getTrendingMovies('week', 1).catch(() => ({ results: [] })),
        this.core.tmdb.getTrendingTV('week', 1).catch(() => ({ results: [] })),
      ]);

    // Merge trending movies and shows
    const trending = [
      ...trendingMovies.results.slice(0, 10),
      ...trendingShows.results.slice(0, 10),
    ];

    return {
      continueWatching,
      recentlyAdded,
      onDeck,
      trending,
    };
  }

  // ============================================
  // Library
  // ============================================

  async getLibraries() {
    return this.core.plexServer.getLibraries();
  }

  async getLibraryItems(opts: {
    libraryKey: string;
    type?: number;
    sort?: string;
    page?: number;
    pageSize?: number;
  }): Promise<LibraryItemsResult> {
    const { libraryKey, type, sort, page = 1, pageSize = 30 } = opts;

    const offset = (page - 1) * pageSize;
    const items = await this.core.plexServer.getLibraryItems(libraryKey, {
      type,
      sort,
      limit: pageSize,
      offset,
    });

    // Note: Plex doesn't return total count in all endpoints
    // We estimate based on whether we got a full page
    return {
      items,
      totalSize: items.length === pageSize ? -1 : offset + items.length,
      page,
      pageSize,
    };
  }

  async search(query: string, type?: number) {
    return this.core.plexServer.search(query, type);
  }

  // ============================================
  // Details
  // ============================================

  async getMetadata(ratingKey: string) {
    return this.core.plexServer.getMetadata(ratingKey);
  }

  async getChildren(ratingKey: string) {
    return this.core.plexServer.getChildren(ratingKey);
  }

  async getRelated(ratingKey: string) {
    return this.core.plexServer.getRelated(ratingKey);
  }

  // ============================================
  // TMDB Enrichment
  // ============================================

  async getTMDBMovieDetails(tmdbId: number) {
    return this.core.tmdb.getMovieDetails(tmdbId);
  }

  async getTMDBTVDetails(tmdbId: number) {
    return this.core.tmdb.getTVDetails(tmdbId);
  }

  async getTMDBMovieCredits(tmdbId: number) {
    return this.core.tmdb.getMovieCredits(tmdbId);
  }

  async getTMDBTVCredits(tmdbId: number) {
    return this.core.tmdb.getTVCredits(tmdbId);
  }

  async getTMDBMovieVideos(tmdbId: number) {
    return this.core.tmdb.getMovieVideos(tmdbId);
  }

  async getTMDBTVVideos(tmdbId: number) {
    return this.core.tmdb.getTVVideos(tmdbId);
  }

  async getTMDBSimilar(tmdbId: number, type: 'movie' | 'tv') {
    if (type === 'movie') {
      return this.core.tmdb.getSimilarMovies(tmdbId);
    }
    return this.core.tmdb.getSimilarTV(tmdbId);
  }

  async getTMDBRecommendations(tmdbId: number, type: 'movie' | 'tv') {
    if (type === 'movie') {
      return this.core.tmdb.getMovieRecommendations(tmdbId);
    }
    return this.core.tmdb.getTVRecommendations(tmdbId);
  }

  // ============================================
  // Playback
  // ============================================

  async getStreamUrl(ratingKey: string) {
    return this.core.plexServer.getStreamUrl(ratingKey);
  }

  getTranscodeUrl(ratingKey: string, options?: {
    maxVideoBitrate?: number;
    videoResolution?: string;
    directStream?: boolean;
  }) {
    return this.core.plexServer.getTranscodeUrl(ratingKey, options);
  }

  async updateTimeline(
    ratingKey: string,
    state: 'playing' | 'paused' | 'stopped',
    timeMs: number,
    durationMs: number
  ) {
    return this.core.plexServer.updateTimeline(ratingKey, state, timeMs, durationMs);
  }

  async getMarkers(ratingKey: string) {
    return this.core.plexServer.getMarkers(ratingKey);
  }

  // ============================================
  // Images
  // ============================================

  getPlexImageUrl(path: string | null | undefined, width?: number) {
    return this.core.plexServer.getImageUrl(path, width);
  }

  getTMDBPosterUrl(path: string | null | undefined) {
    return this.core.tmdb.getPosterUrl(path);
  }

  getTMDBBackdropUrl(path: string | null | undefined) {
    return this.core.tmdb.getBackdropUrl(path);
  }

  // ============================================
  // Watchlist (Plex.tv)
  // ============================================

  async getWatchlist() {
    return this.core.plexTv.getWatchlist();
  }

  async addToWatchlist(ratingKey: string) {
    return this.core.plexTv.addToWatchlist(ratingKey);
  }

  async removeFromWatchlist(ratingKey: string) {
    return this.core.plexTv.removeFromWatchlist(ratingKey);
  }

  async isInWatchlist(ratingKey: string) {
    return this.core.plexTv.isInWatchlist(ratingKey);
  }

  // ============================================
  // Trakt Sync
  // ============================================

  async getTraktWatchlist(type?: 'movies' | 'shows') {
    return this.core.trakt.getWatchlist(type);
  }

  async addToTraktWatchlist(item: { tmdbId: number; type: 'movie' | 'show' }) {
    if (item.type === 'movie') {
      return this.core.trakt.addMovieToWatchlist({ ids: { tmdb: item.tmdbId } });
    }
    return this.core.trakt.addShowToWatchlist({ ids: { tmdb: item.tmdbId } });
  }

  async removeFromTraktWatchlist(item: { tmdbId: number; type: 'movie' | 'show' }) {
    if (item.type === 'movie') {
      return this.core.trakt.removeMovieFromWatchlist({ ids: { tmdb: item.tmdbId } });
    }
    return this.core.trakt.removeShowFromWatchlist({ ids: { tmdb: item.tmdbId } });
  }

  async getTraktHistory(type?: 'movies' | 'shows' | 'episodes') {
    return this.core.trakt.getHistory(type);
  }

  async markWatched(item: {
    tmdbId: number;
    type: 'movie' | 'episode';
    showTmdbId?: number;
    season?: number;
    episode?: number;
  }) {
    if (item.type === 'movie') {
      return this.core.trakt.markMovieWatched({ ids: { tmdb: item.tmdbId } });
    }
    if (item.showTmdbId && item.season !== undefined && item.episode !== undefined) {
      return this.core.trakt.markEpisodeWatched(
        { ids: { tmdb: item.showTmdbId } },
        item.season,
        item.episode
      );
    }
    throw new Error('Missing show/season/episode info for episode watch');
  }

  async getTraktRecommendedMovies() {
    return this.core.trakt.getRecommendedMovies();
  }

  async getTraktRecommendedShows() {
    return this.core.trakt.getRecommendedShows();
  }

  // ============================================
  // Cache Management
  // ============================================

  async clearCache() {
    return this.core.clearAllCaches();
  }

  async clearPlexCache() {
    return this.core.clearPlexCache();
  }

  async clearTmdbCache() {
    return this.core.clearTmdbCache();
  }

  async clearTraktCache() {
    return this.core.clearTraktCache();
  }
}

// Singleton instance
let flixorMobileInstance: FlixorMobile | null = null;

export async function initializeFlixorMobile(): Promise<FlixorMobile> {
  if (!flixorMobileInstance) {
    flixorMobileInstance = await FlixorMobile.initialize();
  }
  return flixorMobileInstance;
}

export function getFlixorMobile(): FlixorMobile {
  if (!flixorMobileInstance) {
    throw new Error('FlixorMobile not initialized. Call initializeFlixorMobile first.');
  }
  return flixorMobileInstance;
}
