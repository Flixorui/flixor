import { useEffect, useRef, useState } from 'react';
// Trakt-first implementation. Plex paths retained but not used when Trakt is preferred.
import { plexTvWatchlist, plexTvAddToWatchlist, plexTvRemoveFromWatchlist } from '@/services/plextv';
import { traktAddToWatchlist, traktRemoveFromWatchlist, getTraktTokens, traktGetWatchlist } from '@/services/trakt';
import { loadSettings } from '@/state/settings';

interface WatchlistButtonProps {
  itemId: string;
  itemType: 'movie' | 'show';
  tmdbId?: string | number;
  imdbId?: string;
  title?: string;
  year?: number;
  className?: string;
  variant?: 'icon' | 'button';
}

export default function WatchlistButton({
  itemId,
  itemType,
  tmdbId,
  imdbId,
  title,
  year,
  className = '',
  variant = 'icon'
}: WatchlistButtonProps) {
  const [isInList, setIsInList] = useState(false);
  const [loading, setLoading] = useState(false);
  const [checking, setChecking] = useState(true);
  const btnRef = useRef<HTMLButtonElement | null>(null);
  const [visible, setVisible] = useState(false);
  const tokens = getTraktTokens();
  const provider = (loadSettings().watchlistProvider || 'trakt') as 'trakt'|'plex';

  // Defer watchlist check until button is near viewport
  useEffect(() => {
    const el = btnRef.current;
    if (!el) return;
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setVisible(true);
          io.disconnect();
        }
      },
      { root: null, rootMargin: '200px', threshold: 0 }
    );
    io.observe(el);
    return () => io.disconnect();
  }, []);

  useEffect(() => {
    if (!visible) return;
    checkWatchlistStatus();
    // Re-check whenever tmdbId, itemType, provider, or tokens change
  }, [itemId, tmdbId, itemType, provider, (tokens && tokens.access_token), visible]);

  async function checkWatchlistStatus() {
    setChecking(true);
    try {
      // Trakt-first: if authenticated and have tmdbId, use Trakt only
      if (provider === 'trakt' && tokens && tmdbId) {
        const type = itemType === 'movie' ? 'movies' : 'shows';
        const list = await traktGetWatchlist(tokens.access_token, type as any);
        const foundT = (list || []).some((e: any) => {
          const ids = (e.movie || e.show || {}).ids || {};
          return ids.tmdb === (typeof tmdbId === 'string' ? parseInt(tmdbId) : tmdbId);
        });
        setIsInList(foundT);
        return;
      }
      // Fallback: try Plex.tv (best-effort)
      try {
        const watchlist = await plexTvWatchlist();
        const items = watchlist.MediaContainer?.Metadata || [];
        const normalizedId = String(itemId || '').startsWith('plex:') ? String(itemId).replace(/^plex:/,'') : String(itemId);
        const found = items.some((item: any) => {
          if (String(item.ratingKey) === normalizedId) return true;
          if (tmdbId && item.guid?.includes(`tmdb://${tmdbId}`)) return true;
          if (imdbId && item.guid?.includes(`imdb://${imdbId}`)) return true;
          return false;
        });
        setIsInList(found);
      } catch {
        setIsInList(false);
      }
    } catch (err) {
      // Reduce log spam; this can hit rate limits. UI will just hide the button until data loads.
      console.warn('Watchlist status unavailable:', err);
    } finally {
      setChecking(false);
    }
  }

  async function handleToggle(e: React.MouseEvent) {
    e.preventDefault();
    e.stopPropagation();

    if (loading || checking) return;

    setLoading(true);
    try {
      if (isInList) {
        // Remove from watchlist
        await removeFromWatchlists();
        setIsInList(false);
        try { window.dispatchEvent(new CustomEvent('app-toast', { detail: `Removed from ${provider==='trakt'?'Trakt':'Plex'} Watchlist` })); } catch {}
      } else {
        // Add to watchlist
        await addToWatchlists();
        setIsInList(true);
        try { window.dispatchEvent(new CustomEvent('app-toast', { detail: `Added to ${provider==='trakt'?'Trakt':'Plex'} Watchlist` })); } catch {}
      }
    } catch (err) {
      console.error('Failed to update watchlist:', err);
      // Revert on error
      setIsInList(!isInList);
    } finally {
      setLoading(false);
    }
  }

  async function addToWatchlists() {
    const promises: Promise<any>[] = [];
    // Trakt-first
    if (provider === 'trakt' && tokens && tmdbId) {
      const traktItem = {
        [itemType === 'movie' ? 'movies' : 'shows']: [{
          ids: { tmdb: typeof tmdbId === 'string' ? parseInt(tmdbId) : tmdbId },
          ...(title ? { title } : {}),
          ...(year ? { year } : {})
        }]
      };
      promises.push(traktAddToWatchlist(tokens.access_token, traktItem).catch(console.error));
    } else {
      // Fallback to Plex if Trakt not available
      const plexGuid = tmdbId ? `tmdb://${typeof tmdbId === 'string' ? tmdbId : String(tmdbId)}` : (imdbId ? `imdb://${imdbId}` : (itemId.startsWith('plex:') ? itemId.replace(/^plex:/, '') : undefined));
      if (plexGuid) promises.push(plexTvAddToWatchlist(plexGuid).catch(console.error));
    }

    await Promise.all(promises);
  }

  async function removeFromWatchlists() {
    const promises: Promise<any>[] = [];
    if (provider === 'trakt' && tokens && tmdbId) {
      const traktItem = {
        [itemType === 'movie' ? 'movies' : 'shows']: [{ ids: { tmdb: typeof tmdbId === 'string' ? parseInt(tmdbId) : tmdbId } }]
      };
      promises.push(traktRemoveFromWatchlist(tokens.access_token, traktItem).catch(console.error));
    } else {
      const plexGuid = tmdbId ? `tmdb://${typeof tmdbId === 'string' ? tmdbId : String(tmdbId)}` : (imdbId ? `imdb://${imdbId}` : (itemId.startsWith('plex:') ? itemId.replace(/^plex:/, '') : undefined));
      if (plexGuid) promises.push(plexTvRemoveFromWatchlist(plexGuid).catch(console.error));
    }

    await Promise.all(promises);
  }

  const disabled = checking || (provider === 'trakt' && (!tokens || !tmdbId));

  if (variant === 'button') {
    return (
      <div className={`inline-flex items-center ${className}`} ref={btnRef as any}>
        <button
          onClick={handleToggle}
          disabled={loading || disabled}
          className={`inline-flex items-center px-5 py-2.5 text-sm md:text-base font-medium rounded-md transition-all ${
            isInList
              ? 'bg-white/20 text-white hover:bg-white/30'
              : 'bg-white/10 text-white hover:bg-white/20'
          } ${loading || disabled ? 'opacity-50 cursor-not-allowed' : ''}`}
        >
          {loading ? (
            <div className="w-4 h-4 md:w-5 md:h-5 mr-2 border-2 border-white/30 border-t-white rounded-full animate-spin" />
          ) : isInList ? (
            <svg className="w-4 h-4 md:w-5 md:h-5 mr-2" fill="currentColor" viewBox="0 0 24 24">
              <path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/>
            </svg>
          ) : (
            <svg className="w-4 h-4 md:w-5 md:h-5 mr-2" fill="currentColor" viewBox="0 0 24 24">
              <path d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z"/>
            </svg>
          )}
          {provider==='trakt' ? (tokens ? (isInList ? 'In My List' : 'Add to My List') : 'Connect Trakt') : (isInList ? 'In My List' : 'Add to My List')}
        </button>
        {provider==='trakt' && !tokens && (
          <a href="/settings" className="ml-3 text-sm text-white/70 underline hover:text-white">Connect Trakt</a>
        )}
      </div>
    );
  }

  // Icon variant
  return (
    <button
      ref={btnRef}
      onClick={handleToggle}
      disabled={loading}
      className={`w-10 h-10 flex items-center justify-center bg-white/10 border border-white/30 rounded-full hover:bg-white/20 transition-all ${
        loading ? 'opacity-50 cursor-not-allowed' : ''
      } ${className}`}
      title={isInList ? 'Remove from My List' : 'Add to My List'}
    >
      {loading ? (
        <div className="w-5 h-5 border-2 border-white/30 border-t-white rounded-full animate-spin" />
      ) : isInList ? (
        <svg className="w-5 h-5 text-white" fill="currentColor" viewBox="0 0 24 24">
          <path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/>
        </svg>
      ) : (
        <svg className="w-5 h-5 text-white" fill="currentColor" viewBox="0 0 24 24">
          <path d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z"/>
        </svg>
      )}
    </button>
  );
}
