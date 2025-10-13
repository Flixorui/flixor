import {
  traktScrobbleStart,
  traktScrobblePause,
  traktScrobbleStop,
  ensureValidToken,
  isTraktAuthenticated,
  TraktScrobble,
  TraktMovie,
  TraktShow,
  TraktEpisode
} from './trakt';
import { loadSettings } from '@/state/settings';

interface ScrobbleState {
  isScrobbling: boolean;
  currentMedia: TraktScrobble | null;
  lastProgress: number;
  startTime: number;
}

class TraktScrobbler {
  private state: ScrobbleState = {
    isScrobbling: false,
    currentMedia: null,
    lastProgress: 0,
    startTime: 0
  };

  private progressInterval: NodeJS.Timeout | null = null;

  async startScrobble(mediaInfo: {
    type: 'movie' | 'episode';
    title: string;
    year?: number;
    imdbId?: string;
    tmdbId?: number;
    tvdbId?: number;
    season?: number;
    episode?: number;
    episodeTitle?: string;
    duration?: number; // in seconds
  }, initialProgress: number = 0): Promise<boolean> {
    try {
      // Check if Trakt is authenticated and scrobbling is enabled
      const settings = loadSettings();
      if (!isTraktAuthenticated() || settings.traktScrobbleEnabled === false) {
        console.log('Trakt scrobbling disabled or not authenticated');
        return false;
      }

      const token = await ensureValidToken();
      if (!token) {
        console.error('No valid Trakt token');
        return false;
      }

      // Stop any existing scrobble
      if (this.state.isScrobbling) {
        await this.stopScrobble();
      }

      // Build the scrobble object
      let scrobbleData: TraktScrobble;

      if (mediaInfo.type === 'movie') {
        const movie: TraktMovie = {
          title: mediaInfo.title,
          year: mediaInfo.year || new Date().getFullYear(),
          ids: {
            trakt: 0, // Will be matched by other IDs
            slug: '',
            imdb: mediaInfo.imdbId,
            tmdb: mediaInfo.tmdbId
          }
        };

        scrobbleData = {
          movie,
          progress: initialProgress,
          app_version: '1.0.0',
          app_date: new Date().toISOString()
        };
      } else {
        const show: TraktShow = {
          title: mediaInfo.title,
          year: mediaInfo.year || new Date().getFullYear(),
          ids: {
            trakt: 0,
            slug: '',
            imdb: mediaInfo.imdbId,
            tmdb: mediaInfo.tmdbId,
            tvdb: mediaInfo.tvdbId
          }
        };

        const episode: TraktEpisode = {
          season: mediaInfo.season || 1,
          number: mediaInfo.episode || 1,
          title: mediaInfo.episodeTitle,
          ids: {
            trakt: 0,
            tvdb: mediaInfo.tvdbId,
            imdb: mediaInfo.imdbId,
            tmdb: mediaInfo.tmdbId
          }
        };

        scrobbleData = {
          show,
          episode,
          progress: initialProgress,
          app_version: '1.0.0',
          app_date: new Date().toISOString()
        };
      }

      // Start the scrobble
      const result = await traktScrobbleStart(token, scrobbleData);

      if (result) {
        this.state = {
          isScrobbling: true,
          currentMedia: scrobbleData,
          lastProgress: initialProgress,
          startTime: Date.now()
        };

        console.log('Trakt scrobble started:', result);
        return true;
      }

      return false;
    } catch (error) {
      console.error('Failed to start Trakt scrobble:', error);
      return false;
    }
  }

  async pauseScrobble(progress: number): Promise<boolean> {
    try {
      if (!this.state.isScrobbling || !this.state.currentMedia) {
        return false;
      }

      const token = await ensureValidToken();
      if (!token) return false;

      const updatedScrobble = {
        ...this.state.currentMedia,
        progress
      };

      const result = await traktScrobblePause(token, updatedScrobble);

      if (result) {
        this.state.lastProgress = progress;
        console.log('Trakt scrobble paused at', progress + '%');
        return true;
      }

      return false;
    } catch (error) {
      console.error('Failed to pause Trakt scrobble:', error);
      return false;
    }
  }

  async resumeScrobble(progress: number): Promise<boolean> {
    try {
      if (!this.state.currentMedia) {
        return false;
      }

      const token = await ensureValidToken();
      if (!token) return false;

      const updatedScrobble = {
        ...this.state.currentMedia,
        progress
      };

      const result = await traktScrobbleStart(token, updatedScrobble);

      if (result) {
        this.state.isScrobbling = true;
        this.state.lastProgress = progress;
        console.log('Trakt scrobble resumed at', progress + '%');
        return true;
      }

      return false;
    } catch (error) {
      console.error('Failed to resume Trakt scrobble:', error);
      return false;
    }
  }

  async updateProgress(progress: number): Promise<void> {
    // Update the current progress without making an API call
    // This is useful for tracking progress locally
    if (this.state.isScrobbling) {
      this.state.lastProgress = progress;
    }
  }

  async stopScrobble(progress?: number): Promise<boolean> {
    try {
      if (!this.state.currentMedia) {
        return false;
      }

      const token = await ensureValidToken();
      if (!token) return false;

      const finalProgress = progress !== undefined ? progress : this.state.lastProgress;
      const updatedScrobble = {
        ...this.state.currentMedia,
        progress: finalProgress
      };

      const result = await traktScrobbleStop(token, updatedScrobble);

      // Clear the interval if it exists
      if (this.progressInterval) {
        clearInterval(this.progressInterval);
        this.progressInterval = null;
      }

      // Reset state
      this.state = {
        isScrobbling: false,
        currentMedia: null,
        lastProgress: 0,
        startTime: 0
      };

      if (result) {
        console.log('Trakt scrobble stopped at', finalProgress + '%');

        // If progress >= 80%, it's marked as watched
        if (finalProgress >= 80) {
          console.log('Media marked as watched on Trakt');
        }

        return true;
      }

      return false;
    } catch (error) {
      console.error('Failed to stop Trakt scrobble:', error);
      return false;
    }
  }

  isCurrentlyScrobbling(): boolean {
    return this.state.isScrobbling;
  }

  getCurrentProgress(): number {
    return this.state.lastProgress;
  }

  getCurrentMedia(): TraktScrobble | null {
    return this.state.currentMedia;
  }

  // Helper to convert Plex metadata to Trakt scrobble format
  convertPlexToTraktMedia(plexMedia: any): {
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
  } | null {
    if (!plexMedia) return null;

    // Extract IDs from Plex GUIDs
    let imdbId: string | undefined;
    let tmdbId: number | undefined;
    let tvdbId: number | undefined;

    if (plexMedia.Guid) {
      for (const guid of plexMedia.Guid) {
        const id = guid.id;
        if (id.startsWith('imdb://')) {
          imdbId = id.replace('imdb://', '');
        } else if (id.startsWith('tmdb://')) {
          tmdbId = parseInt(id.replace('tmdb://', ''));
        } else if (id.startsWith('tvdb://')) {
          tvdbId = parseInt(id.replace('tvdb://', ''));
        }
      }
    }

    // Determine media type
    const type = plexMedia.type === 'movie' ? 'movie' : 'episode';

    if (type === 'movie') {
      return {
        type: 'movie',
        title: plexMedia.title || plexMedia.originalTitle,
        year: plexMedia.year,
        imdbId,
        tmdbId,
        duration: plexMedia.duration ? Math.floor(plexMedia.duration / 1000) : undefined
      };
    } else {
      // For TV episodes
      return {
        type: 'episode',
        title: plexMedia.grandparentTitle || plexMedia.showTitle, // Show title
        year: plexMedia.year,
        imdbId,
        tmdbId,
        tvdbId,
        season: plexMedia.parentIndex || plexMedia.season,
        episode: plexMedia.index || plexMedia.episode,
        episodeTitle: plexMedia.title,
        duration: plexMedia.duration ? Math.floor(plexMedia.duration / 1000) : undefined
      };
    }
  }
}

// Export a singleton instance
export const traktScrobbler = new TraktScrobbler();