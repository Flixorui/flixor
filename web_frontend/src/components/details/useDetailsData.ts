/**
 * All data for the details page: loads a Plex or TMDB title, maps TMDB titles to
 * Plex, and keeps episode and on-deck state fresh. The page is keyed by id, so a
 * new title starts from clean state.
 */
import { useCallback, useEffect, useMemo, useState } from 'react';
import { getSettings, loadSettings } from '@/state/settings';
import { plexPartUrl } from '@/services/plex';
import { plexBackendMetadataWithExtras, plexBackendDir, plexBackendSearch, plexBackendFindByGuid, plexBackendMetadata } from '@/services/plex_backend';
import { tmdbDetails, tmdbImage, tmdbCredits, tmdbExternalIds, tmdbRecommendations, tmdbVideos, tmdbTvSeasons, tmdbTvSeasonDetails, tmdbSimilar, tmdbImages } from '@/services/tmdb';
import { apiClient } from '@/services/api';
import { getMDBListRatings, type MDBListRatings } from '@/services/mdblist';
import { fetchPlexVodRatingsById } from '@/services/ratings';
import { isTraktConnected, locallyWatchedEpisodes, subscribeWatchState, type WatchTarget } from '@/services/watchState';
import { traktLookupId, traktShowProgress } from '@/services/trakt';
import type { Track } from '@/components/TrackPicker';
import type { RatingsData } from '@/components/RatingsBar';

export interface DetailsSeason {
  key: string;
  title: string;
  number?: number;
  image?: string;
  episodeCount?: number;
  watchedCount?: number;
}

export interface DetailsEpisode {
  id: string;
  title: string;
  overview?: string;
  image?: string;
  duration?: number;
  index: number;
  progress: number;
  airDate?: string;
  seasonNumber?: number;
  plexRatingKey?: string;
  rating?: number;
  watched: boolean;
}

export interface DetailsOnDeck {
  id: string;
  title: string;
  overview?: string;
  image?: string;
  duration?: number;
  progress: number;
  ratingKey: string;
}

function plexSeason(x: any): DetailsSeason {
  return {
    key: String(x.ratingKey),
    title: x.title,
    number: x.index != null ? Number(x.index) : undefined,
    image: x.thumb ? apiClient.getPlexImageNoToken(x.thumb) : undefined,
    episodeCount: x.leafCount != null ? Number(x.leafCount) : undefined,
    watchedCount: x.viewedLeafCount != null ? Number(x.viewedLeafCount) : undefined,
  };
}

async function fetchOnDeck(showKey: string): Promise<DetailsOnDeck | null> {
  try {
    const od: any = await plexBackendDir(`/library/metadata/${showKey}/onDeck?nocache=${Date.now()}`);
    const ep = od?.MediaContainer?.Metadata?.[0];
    if (!ep) return null;
    return {
      id: `plex:${ep.ratingKey}`,
      title: ep.title,
      overview: ep.summary,
      image: apiClient.getPlexImageNoToken(ep.thumb || ep.parentThumb || ''),
      duration: Math.round((ep.duration || 0) / 60000),
      progress: ep.viewOffset ? Math.round((ep.viewOffset / (ep.duration || 1)) * 100) : 0,
      ratingKey: String(ep.ratingKey),
    };
  } catch {
    return null;
  }
}

function plexEpisodeProgress(e: any): number {
  const dur = (e.duration || 0) / 1000;
  const vo = (e.viewOffset || 0) / 1000;
  if ((e.viewCount || 0) > 0) return 100;
  if (dur > 0 && vo / dur >= 0.95) return 100;
  if (dur > 0) return Math.round((vo / dur) * 100);
  return 0;
}

const seasonNumberOf = (season?: DetailsSeason) => {
  if (season?.number != null) return season.number;
  const match = season?.title?.match(/\d+/);
  return match ? parseInt(match[0], 10) : undefined;
};

export function useDetailsData(id: string) {
  const [title, setTitle] = useState<string>('');
  const [overview, setOverview] = useState<string>('');
  const [badges, setBadges] = useState<string[]>([]);
  const [backdrop, setBackdrop] = useState<string>('');
  const [related, setRelated] = useState<any[]>([]);
  const [similar, setSimilar] = useState<any[]>([]);
  const [meta, setMeta] = useState<{ genres?: string[]; runtime?: number; rating?: string }>({});
  const [year, setYear] = useState<string | undefined>(undefined);
  const [cast, setCast] = useState<Array<{ id?: string; name: string; img?: string; character?: string }>>([]);
    const [poster, setPoster] = useState<string | undefined>(undefined);
      const [seasons, setSeasons] = useState<DetailsSeason[]>([]);
  const [seasonKey, setSeasonKey] = useState<string>('');
  const [episodes, setEpisodes] = useState<DetailsEpisode[]>([]);
  const [episodesLoading, setEpisodesLoading] = useState<boolean>(false);
  const [onDeck, setOnDeck] = useState<any | null>(null);
  const [showKey, setShowKey] = useState<string | undefined>(undefined);
  const [tech, setTech] = useState<any>({});
  const [versions, setVersions] = useState<Array<{id:string; label:string}>>([]);
  const [activeVersion, setActiveVersion] = useState<string | undefined>(undefined);
  const [versionPartMap, setVersionPartMap] = useState<Record<string, string>>({});
  const [versionDetails, setVersionDetails] = useState<Array<{id:string; label:string; audios: Track[]; subs: Track[]; tech: any}>>([]);
  const [infoVersion, setInfoVersion] = useState<string | undefined>(undefined);
  const [audioTracks, setAudioTracks] = useState<Track[]>([]);
  const [subtitleTracks, setSubtitleTracks] = useState<Track[]>([]);
  const [activeAudio, setActiveAudio] = useState<string | undefined>(undefined);
  const [activeSub, setActiveSub] = useState<string | undefined>(undefined);
    // Movie resume/progress state
  const [movieViewOffset, setMovieViewOffset] = useState<number | undefined>(undefined); // in ms
  const [movieDuration, setMovieDuration] = useState<number | undefined>(undefined); // in ms
  const [trailerKey, setTrailerKey] = useState<string | undefined>(undefined);
  const [trailerMuted, setTrailerMuted] = useState<boolean>(true);
  const [showTrailer, setShowTrailer] = useState<boolean>(false);
  const [plexTrailerUrl, setPlexTrailerUrl] = useState<string | undefined>(undefined);
  const [logoUrl, setLogoUrl] = useState<string | undefined>(undefined);
  const [imdbId, setImdbId] = useState<string | undefined>(undefined);
  // TMDB's audience score: the last fallback for the hero's IMDb badge, as on macOS.
  const [tmdbScore, setTmdbScore] = useState<number | undefined>(undefined);
  const [plexRatings, setExternalRatings] = useState<{ imdb?: { rating?: number; votes?: number } | null; rt?: { critic?: number; audience?: number } | null } | null>(null);
  const [moodTags, setMoodTags] = useState<string[]>([]);
  const [plexMappedId, setPlexMappedId] = useState<string | undefined>(undefined);
    const [tmdbCtx, setTmdbCtx] = useState<{ media?: 'movie'|'tv'; id?: string } | undefined>(undefined);
  const [kind, setKind] = useState<'movie'|'tv'|undefined>(undefined);
  const [watchIds, setWatchIds] = useState<{ tmdbId?: string; imdbId?: string; plexKey?: string; media?: 'movie'|'tv' }>({});
  const [trailers, setTrailers] = useState<Array<{ id: string; key: string; name: string; site: string; type: string }>>([]);
    // Additional metadata for Details tab
  const [tagline, setTagline] = useState<string | undefined>(undefined);
  const [director, setDirector] = useState<string | undefined>(undefined);
  const [writers, setWriters] = useState<string[]>([]);
  const [productionCompanies, setProductionCompanies] = useState<Array<{ id: number; name: string; logo?: string }>>([]);
  const [budget, setBudget] = useState<number | undefined>(undefined);
  const [revenue, setRevenue] = useState<number | undefined>(undefined);
  const [status, setStatus] = useState<string | undefined>(undefined);
  const [releaseDate, setReleaseDate] = useState<string | undefined>(undefined);
  const [originalLanguage, setOriginalLanguage] = useState<string | undefined>(undefined);
  const [studio, setStudio] = useState<string | undefined>(undefined);
  const [numberOfSeasons, setNumberOfSeasons] = useState<number | undefined>(undefined);
  const [numberOfEpisodes, setNumberOfEpisodes] = useState<number | undefined>(undefined);
  const [networks, setNetworks] = useState<Array<{ id: number; name: string; logo?: string }>>([]);
  const [audioTracks2, setAudioTracks2] = useState<string[]>([]);
  const [subtitleTracks2, setSubtitleTracks2] = useState<string[]>([]);
  const [container, setContainer] = useState<string | undefined>(undefined);
  const [fileSize, setFileSize] = useState<number | undefined>(undefined);
  const [bitrate, setBitrate] = useState<number | undefined>(undefined);
  // Accessibility badges
  const [hasCC, setHasCC] = useState<boolean>(false);
  const [hasSDH, setHasSDH] = useState<boolean>(false);
  const [hasAD, setHasAD] = useState<boolean>(false);
  // Episode-specific state
  const [isEpisode, setIsEpisode] = useState<boolean>(false);
  const [showRatingKey, setShowRatingKey] = useState<string | undefined>(undefined);
  const [showTitle, setShowTitle] = useState<string | undefined>(undefined);
  const [episodeInfo, setEpisodeInfo] = useState<string | undefined>(undefined); // e.g., "S01 E05"
  const [episodeNumbers, setEpisodeNumbers] = useState<{ season?: number; episode?: number }>({});
  const [collectionId, setCollectionId] = useState<number | undefined>(undefined);
  const [mdblistRatings, setMdblistRatings] = useState<MDBListRatings | null>(null);

  useEffect(() => {
    // expose setter for trailer mute to toggle function
    (window as any).reactSetTrailerMuted = setTrailerMuted;
    const s = loadSettings();
    const tmdbKey = s.tmdbBearer || '';
    const timers: number[] = [];
    /** Starts the inline trailer after a short delay, when the setting allows it. */
    const scheduleTrailer = (prepare?: () => void) => {
      const current = getSettings();
      setTrailerMuted(current.detailsHeroTrailerStartsMuted);
      if (!current.detailsHeroInlineTrailerEnabled) return;
      timers.push(window.setTimeout(() => {
        prepare?.();
        setShowTrailer(true);
      }, 5000));
    };
    async function load() {
      if (!id) return;
      try {
        if (id.startsWith('plex:')) {
          const rk = id.replace(/^plex:/, '');
          const meta: any = await plexBackendMetadata(rk);
          const m = meta?.MediaContainer?.Metadata?.[0];
          if (m) {
            setTitle(m.title || m.grandparentTitle || '');
            setOverview(m.summary || '');
            {
              const pBackdrop = m.art || m.thumb || m.parentThumb || m.grandparentThumb;
              const pPoster = m.thumb || m.parentThumb || m.grandparentThumb;
              setBackdrop(apiClient.getPlexImageNoToken(pBackdrop || '') || backdrop);
              setPoster(apiClient.getPlexImageNoToken(pPoster || ''));
            }
            // Handle episode type separately
            // Resume position for movies and episodes alike
            if (m.type === 'movie' || m.type === 'episode') {
              setMovieViewOffset(m.viewOffset || undefined);
              setMovieDuration(m.duration || undefined);
            }
            if (m.type === 'episode') {
              setIsEpisode(true);
              setKind('tv');
              setShowRatingKey(m.grandparentRatingKey);
              setShowTitle(m.grandparentTitle);
              const seasonNum = m.parentIndex || m.seasonNumber;
              const epNum = m.index || m.episodeNumber;
              setEpisodeNumbers({ season: seasonNum, episode: epNum });
              if (seasonNum && epNum) {
                setEpisodeInfo(`S${String(seasonNum).padStart(2, '0')} E${String(epNum).padStart(2, '0')}`);
              }
              setTitle(m.title || ''); // Episode title
            } else {
              setIsEpisode(false);
              setShowRatingKey(undefined);
              setShowTitle(undefined);
              setEpisodeInfo(undefined);
              setKind(m.type === 'movie' ? 'movie' : (m.type === 'show' ? 'tv' : undefined));
            }
            setMeta({
              genres: (m.Genre || []).map((g: any) => g.tag),
              runtime: Math.round((m.duration || 0) / 60000),
              rating: m.contentRating || m.rating,
            });
            if (m.year) setYear(String(m.year));
            else if (m.originallyAvailableAt) setYear(m.originallyAvailableAt.split('-')[0]);
            try { setMoodTags(deriveTags((m.Genre||[]).map((g:any)=>g.tag))); } catch {}
            setCast((m.Role || []).slice(0, 16).map((r: any) => ({ name: r.tag, img: apiClient.getPlexImageNoToken(r.thumb || ''), character: r.role })));
            // Additional Plex metadata
            setStudio(m.studio);
            if (m.Director) setDirector(m.Director.map((d: any) => d.tag).join(', '));
            if (m.Writer) setWriters(m.Writer.map((w: any) => w.tag).slice(0, 5));
            // Fetch ratings directly from Plex for plex items
            try {
              const r = await (await import('@/services/ratings')).fetchPlexRatingsByRatingKey(rk);
              if (r) setExternalRatings({ imdb: r.imdb || undefined, rt: r.rt || undefined });
            } catch {}
            // Badges detection
            const bs: string[] = [];
            const media = (m.Media || [])[0];
            if (media) {
              const w = media.width || 0; const h = media.height || 0; if (w >= 3800 || h >= 2100) bs.push('4K');
              const vp = (media.videoProfile || '').toLowerCase(); if (vp.includes('hdr') || vp.includes('hlg')) bs.push('HDR'); if (vp.includes('dv')) bs.push('Dolby Vision');
              const ap = (media.audioProfile || '').toLowerCase(); const ac = (media.audioCodec || '').toLowerCase(); if (ap.includes('atmos') || ac.includes('truehd')) bs.push('Atmos');
              setTech({
                rating: m.contentRating || m.rating,
                runtimeMin: Math.round((m.duration||0)/60000),
                videoCodec: media.videoCodec,
                videoProfile: media.videoProfile,
                resolution: w&&h? `${w}x${h}`: undefined,
                bitrateKbps: media.bitrate ? media.bitrate * 1000 : undefined,
                audioCodec: media.audioCodec,
                audioChannels: media.audioChannels,
                fileSizeMB: media.Part?.[0]?.size ? media.Part[0].size / (1024*1024) : undefined,
                subsCount: (media.Part?.[0]?.Stream||[]).filter((st:any)=>st.streamType===3).length,
              });
              // Set additional tech fields
              setContainer(media.container);
              setFileSize(media.Part?.[0]?.size ? media.Part[0].size / (1024*1024*1024) : undefined); // GB
              setBitrate(media.bitrate);
              // Extract audio and subtitle track names
              const streams = media.Part?.[0]?.Stream || [];
              const audioNames = streams.filter((st: any) => st.streamType === 2).map((st: any) => st.displayTitle || st.language || 'Unknown');
              const subStreams = streams.filter((st: any) => st.streamType === 3);
              const subNames = subStreams.map((st: any) => st.displayTitle || st.language || 'Unknown');
              setAudioTracks2(audioNames);
              setSubtitleTracks2(subNames);
              // Detect CC/SDH/AD badges (matching mobile/macOS logic)
              setHasCC(subStreams.length > 0);
              setHasSDH(subStreams.some((st: any) => {
                const title = ((st.displayTitle || st.title || '') as string).toUpperCase();
                return title.includes('SDH') || title.includes('DEAF') || title.includes('HARD OF HEARING');
              }));
              setHasAD(streams.filter((st: any) => st.streamType === 2).some((st: any) => {
                const title = ((st.displayTitle || st.title || '') as string).toLowerCase();
                return title.includes('description') || title.includes('descriptive') || title.includes(' ad');
              }));
            }
            setBadges(bs);
                        // Versions
            const vs = (m.Media||[]).map((me:any, idx:number)=>({ id:String(me.id||idx), label: `${(me.width||0)>=3800?'4K':'HD'} ${String(me.videoCodec||'').toUpperCase()} ${me.audioChannels||''}` }));
            // Map version -> part id
            const vm: Record<string,string> = {};
            (m.Media||[]).forEach((me:any)=>{ const pid = me.Part?.[0]?.id; if ((me.id || me.Id) && pid) vm[String(me.id || me.Id)] = String(pid); });
            setVersionPartMap(vm);
            setVersions(vs); setActiveVersion(vs[0]?.id);
            // Build per-version media info
            try {
              const vds: Array<{id:string; label:string; audios: Track[]; subs: Track[]; tech: any}> = (m.Media||[]).map((mm:any)=>{
                const streams = mm?.Part?.[0]?.Stream || [];
                const auds: Track[] = streams.filter((st:any)=>st.streamType===2).map((st:any, i:number)=>({ id: String(st.id || i), label: (st.displayTitle || st.languageTag || st.language || `Audio ${i+1}`), forced: st.forced }));
                const subs: Track[] = streams.filter((st:any)=>st.streamType===3).map((st:any, i:number)=>({ id: String(st.id || i), label: (st.displayTitle || st.languageTag || st.language || `Sub ${i+1}`), forced: st.forced }));
                const w = mm.width || 0; const h = mm.height || 0;
                const techInfo = {
                  rating: meta.rating,
                  runtimeMin: Math.round((m.duration||0)/60000),
                  videoCodec: mm.videoCodec,
                  videoProfile: mm.videoProfile,
                  resolution: w&&h? `${w}x${h}`: undefined,
                  width: w,
                  height: h,
                  bitrate: mm.bitrate || undefined, // Plex gives bitrate in Kbps
                  audioCodec: mm.audioCodec,
                  audioChannels: mm.audioChannels,
                  fileSize: mm.Part?.[0]?.size ? mm.Part[0].size / (1024*1024) : undefined,
                  container: mm.container || mm.Part?.[0]?.container,
                  subsCount: subs.length,
                };
                // Build descriptive label: "4K HEVC 7.1" or "1080p H264 5.1"
                const resLabel = w >= 3800 ? '4K' : w >= 1900 ? '1080p' : w >= 1200 ? '720p' : 'HD';
                const codecLabel = String(mm.videoCodec || '').toUpperCase();
                const audioLabel = mm.audioChannels >= 8 ? '7.1' : mm.audioChannels >= 6 ? '5.1' : mm.audioChannels >= 2 ? 'Stereo' : '';
                const label = [resLabel, codecLabel, audioLabel].filter(Boolean).join(' ');
                return { id: String(mm.id||mm.Id), label, audios: auds, subs, tech: techInfo };
              });
              setVersionDetails(vds);
              setInfoVersion(vds[0]?.id);
              // Keep backward-compat tracks state for quick display
              const first = vds[0];
              if (first) { setAudioTracks(first.audios); setSubtitleTracks(first.subs); }
            } catch {}
            // If this Plex item has a TMDB GUID, prefer TMDB textual metadata and recs/videos
            let guidSource = m;
            if (m.type === 'episode' && m.grandparentRatingKey) {
              const show: any = await plexBackendMetadata(String(m.grandparentRatingKey)).catch(() => null);
              guidSource = show?.MediaContainer?.Metadata?.[0] || m;
            }
            const guids: string[] = (guidSource.Guid || []).map((g:any)=>String(g.id||''));
            const tmdbGuid = guids.find((g)=>g.includes('tmdb://')||g.includes('themoviedb://'));
            const imdbGuid = guids.find((g)=>g.includes('imdb://'));
            setWatchIds({ tmdbId: tmdbGuid ? tmdbGuid.split('://')[1] : undefined, imdbId: imdbGuid ? imdbGuid.split('://')[1] : undefined, plexKey: String(m.ratingKey||''), media: (m.type==='movie'?'movie':'tv') });
            if (imdbGuid) {
              try { setImdbId(imdbGuid.split('://')[1]); } catch {}
            }
            if (tmdbGuid) {
              const tid = tmdbGuid.split('://')[1];
              const mediaType = (m.type === 'movie') ? 'movie' : 'tv';
              // For episodes, don't override kind - it's already set to 'tv'
              if (m.type !== 'episode') {
                setKind(mediaType);
              }
              // Also fetch external IDs to get IMDb id when available
              try {
                const exIds: any = await tmdbExternalIds(tmdbKey, mediaType as any, tid);
                if (exIds?.imdb_id) setImdbId(exIds.imdb_id);
              } catch {}
              setTmdbCtx({ media: mediaType as any, id: String(tid) });
                try {
                  const d: any = await tmdbDetails(tmdbKey, mediaType as any, tid);
                  // For episodes, preserve episode title/overview from Plex, only get show metadata
                  if (m.type !== 'episode') {
                    setTmdbScore(d.vote_count > 0 ? d.vote_average : undefined);
                    setTitle(d.title || d.name || title);
                    setOverview(d.overview || overview);
                  }
                  setPoster(tmdbImage(d.poster_path, 'w500') || poster);
                  setMeta({ genres: (d.genres||[]).map((x:any)=>x.name), runtime: Math.round((m.type === 'episode' ? (m.duration || 0) / 60000 : (d.runtime||d.episode_run_time?.[0]||0))), rating: m.contentRating || m.rating });
                  const y2 = (d.release_date || d.first_air_date || '').slice(0,4); if (y2) setYear(y2);
                  try { setMoodTags(deriveTags((d.genres||[]).map((g:any)=>g.name))); } catch {}
                  // Additional TMDB metadata
                  setCollectionId(d?.belongs_to_collection?.id);
                  setTagline(d.tagline);
                  setBudget(d.budget);
                  setRevenue(d.revenue);
                  setStatus(d.status);
                  setReleaseDate(d.release_date || d.first_air_date);
                  setOriginalLanguage(d.original_language);
                  setNumberOfSeasons(d.number_of_seasons);
                  setNumberOfEpisodes(d.number_of_episodes);
                  if (d.production_companies) {
                    setProductionCompanies(d.production_companies.map((c: any) => ({
                      id: c.id,
                      name: c.name,
                      logo: c.logo_path ? tmdbImage(c.logo_path, 'w500') : undefined
                    })));
                  }
                  if (d.networks) {
                    setNetworks(d.networks.map((n: any) => ({
                      id: n.id,
                      name: n.name,
                      logo: n.logo_path ? tmdbImage(n.logo_path, 'w500') : undefined
                    })));
                  }
                  // Try fetch a logo image
                  try {
                    const imgs: any = await tmdbImages(tmdbKey, mediaType as any, tid, 'en,null');
                    const logo = (imgs?.logos||[]).find((l:any)=>l.iso_639_1==='en') || (imgs?.logos||[])[0];
                    if (logo?.file_path) setLogoUrl(tmdbImage(logo.file_path, 'w500') || tmdbImage(logo.file_path, 'original'));
                  } catch {}
                  try {
                    const cr: any = await tmdbCredits(tmdbKey, mediaType as any, tid);
                    setCast((cr.cast||[]).slice(0,16).map((c:any)=>({ id:String(c.id), name:c.name, img: tmdbImage(c.profile_path,'w500'), character: c.character })));
                    // Get director and writers from crew
                    const crew = cr.crew || [];
                    const directors = crew.filter((c: any) => c.job === 'Director').map((c: any) => c.name);
                    const writersList = crew.filter((c: any) => c.department === 'Writing' || c.job === 'Screenplay' || c.job === 'Writer').map((c: any) => c.name);
                    if (directors.length > 0) setDirector(directors.join(', '));
                    if (writersList.length > 0) setWriters([...new Set(writersList as string[])].slice(0, 5));
                  } catch {}
                  try {
                  const vids:any = await tmdbVideos(tmdbKey, mediaType as any, tid);
                  const ytVideos = (vids.results||[]).filter((v:any)=>v.site==='YouTube'&&(v.type==='Trailer'||v.type==='Teaser'||v.type==='Clip'||v.type==='Behind the Scenes'||v.type==='Featurette'));
                  setTrailers(ytVideos.map((v:any)=>({ id: v.id, key: v.key, name: v.name, site: v.site, type: v.type })));
                  const yt = ytVideos.find((v:any)=>v.type==='Trailer'||v.type==='Teaser');
                  if (yt) {
                    scheduleTrailer(() => setTrailerKey(yt.key));
                  }
                } catch (e) { console.error('[Details] Error fetching videos:', e); }
                try {
                  const recs:any = await tmdbRecommendations(tmdbKey, mediaType as any, tid);
                  setRelated((recs.results||[]).slice(0,8).map((r:any)=>({ id:`tmdb:${mediaType}:${r.id}`, title:r.title||r.name, image: tmdbImage(r.backdrop_path,'w780')||tmdbImage(r.poster_path,'w500') })));
                } catch {}
                try {
                  const sim:any = await tmdbSimilar(tmdbKey, mediaType as any, tid);
                  setSimilar((sim.results||[]).slice(0,8).map((r:any)=>({ id:`tmdb:${mediaType}:${r.id}`, title:r.title||r.name, image: tmdbImage(r.backdrop_path,'w780')||tmdbImage(r.poster_path,'w500') })));
                } catch {}
              } catch (e) { console.error(e); }
            }
            // Try Plex Extras for trailer preview
            try {
              const ex: any = await plexBackendMetadataWithExtras(rk);
              const em = ex?.MediaContainer?.Metadata?.[0]?.Extras?.Metadata?.[0];
              const pkey = em?.Media?.[0]?.Part?.[0]?.key as string | undefined;
              if (pkey) {
                if (s.plexBaseUrl && s.plexToken) setPlexTrailerUrl(plexPartUrl(s.plexBaseUrl, s.plexToken, pkey));
                scheduleTrailer();
              }
            } catch {}
            // Seasons for Plex-native series
            if (m.type === 'show') {
              setKind('tv');
              setShowKey(rk);
              try {
                const ch: any = await plexBackendDir(`/library/metadata/${rk}/children`);
                const ss = (ch?.MediaContainer?.Metadata||[]).map(plexSeason);
                setSeasons(ss);
                if (ss[0]) setSeasonKey(ss[0].key);
              } catch (e) { console.error(e); }

              // Continue watching (onDeck) for shows
              setOnDeck(await fetchOnDeck(rk));
            }
          }
        } else if (id.startsWith('tmdb:')) {
          const [, media, tmdbId] = id.split(':');
          {
            const d: any = await tmdbDetails(tmdbKey, media as any, tmdbId);
            setTmdbScore(d.vote_count > 0 ? d.vote_average : undefined);
            setTitle(d.title || d.name || '');
            setOverview(d.overview || '');
            setBackdrop(tmdbImage(d.backdrop_path, 'w1280') || tmdbImage(d.poster_path, 'w780') || backdrop);
            setPoster(tmdbImage(d.poster_path, 'w500') || poster);
            setMeta({
              genres: (d.genres || []).map((g: any) => g.name),
              runtime: Math.round((d.runtime || d.episode_run_time?.[0] || 0)),
              rating: d.adult ? '18+' : undefined,
            });
            const y = (d.release_date || d.first_air_date || '').slice(0,4); if (y) setYear(y);
            try { setMoodTags(deriveTags((d.genres||[]).map((g:any)=>g.name))); } catch {}
            setKind((media as any) === 'movie' ? 'movie' : 'tv');
            // Additional TMDB metadata
            setTagline(d.tagline);
            setBudget(d.budget);
            setRevenue(d.revenue);
            setStatus(d.status);
            setReleaseDate(d.release_date || d.first_air_date);
            setOriginalLanguage(d.original_language);
            setNumberOfSeasons(d.number_of_seasons);
            setNumberOfEpisodes(d.number_of_episodes);
            if (d.production_companies) {
              setProductionCompanies(d.production_companies.map((c: any) => ({
                id: c.id,
                name: c.name,
                logo: c.logo_path ? tmdbImage(c.logo_path, 'w500') : undefined
              })));
            }
            if (d.networks) {
              setNetworks(d.networks.map((n: any) => ({
                id: n.id,
                name: n.name,
                logo: n.logo_path ? tmdbImage(n.logo_path, 'w500') : undefined
              })));
            }
            try {
              const cr: any = await tmdbCredits(tmdbKey, media as any, tmdbId);
              setCast((cr.cast || []).slice(0, 16).map((c: any) => ({ id: String(c.id), name: c.name, img: tmdbImage(c.profile_path, 'w500'), character: c.character })));
              // Get director and writers from crew
              const crew = cr.crew || [];
              const directors = crew.filter((c: any) => c.job === 'Director').map((c: any) => c.name);
              const writersList = crew.filter((c: any) => c.department === 'Writing' || c.job === 'Screenplay' || c.job === 'Writer').map((c: any) => c.name);
              if (directors.length > 0) setDirector(directors.join(', '));
              if (writersList.length > 0) setWriters([...new Set(writersList as string[])].slice(0, 5));
            } catch {}
            try {
              const vids: any = await tmdbVideos(tmdbKey, media as any, tmdbId);
              const ytVideos = (vids.results||[]).filter((v:any)=>v.site==='YouTube'&&(v.type==='Trailer'||v.type==='Teaser'||v.type==='Clip'||v.type==='Behind the Scenes'||v.type==='Featurette'));
              setTrailers(ytVideos.map((v:any)=>({ id: v.id, key: v.key, name: v.name, site: v.site, type: v.type })));
              const yt = ytVideos.find((v:any)=>v.type==='Trailer'||v.type==='Teaser');
              if (yt) {
                scheduleTrailer(() => setTrailerKey(yt.key));
              }
            } catch (e) { console.error('[Details TMDB] Error fetching videos:', e); }
            try {
              const recs: any = await tmdbRecommendations(tmdbKey, media as any, tmdbId);
              setRelated((recs.results || []).slice(0, 8).map((r: any) => ({ id: `tmdb:${media}:${r.id}`, title: r.title || r.name, image: tmdbImage(r.backdrop_path, 'w780') || tmdbImage(r.poster_path, 'w500') })));
            } catch {}
            try {
              const sim: any = await tmdbSimilar(tmdbKey, media as any, tmdbId);
              setSimilar((sim.results || []).slice(0, 8).map((r: any) => ({ id: `tmdb:${media}:${r.id}`, title: r.title || r.name, image: tmdbImage(r.backdrop_path, 'w780') || tmdbImage(r.poster_path, 'w500') })));
            } catch {}
            setTmdbCtx({ media: media as any, id: String(tmdbId) });
            setWatchIds({ tmdbId: String(tmdbId), media: (media as any) });
            // Try to fetch a logo for the TMDB item
            try {
              const imgs: any = await tmdbImages(tmdbKey, media as any, tmdbId, 'en,null');
              const logo = (imgs?.logos||[]).find((l:any)=>l.iso_639_1==='en') || (imgs?.logos||[])[0];
              if (logo?.file_path) setLogoUrl(tmdbImage(logo.file_path, 'w500') || tmdbImage(logo.file_path, 'original'));
            } catch {}
            // TMDB seasons fallback (if mapping to Plex fails or no Plex)
            // Use "tmdb:" prefix to distinguish from Plex ratingKeys
            if (media === 'tv') {
              try {
                const tv: any = await tmdbTvSeasons(tmdbKey, tmdbId);
                const ss = (tv.seasons||[]).filter((x:any)=>x.season_number>0).map((x:any)=>({ key: `tmdb:${x.season_number}`, title: x.name || `Season ${x.season_number}`, number: x.season_number, image: tmdbImage(x.poster_path, 'w500') }));
                if (ss.length) {
                  setSeasons(ss);
                  setSeasonKey(ss[0].key);
                }
              } catch (e) { console.error(e); }
            }
            const bs: string[] = [];
            setCollectionId(d?.belongs_to_collection?.id);
            if ((d?.runtime ?? 0) > 0 || (d?.episode_run_time?.[0] ?? 0) > 0) bs.push('Runtime');
            setBadges(bs);
            // Try find on Plex (first by GUID, then fallback title/year search)
            {
              const q = d.title || d.name;
              if (q) {
                let allHits: any[] = [];

                // Build list of all possible GUIDs to search for
                const searchGuids: string[] = [
                  `tmdb://${tmdbId}`,
                  `themoviedb://${tmdbId}`
                ];

                // Add external IDs if available
                try {
                  const ex: any = await tmdbExternalIds(tmdbKey, media as any, tmdbId);
                  if (ex?.imdb_id) {
                    setImdbId(ex.imdb_id);
                    setWatchIds((ids) => ({ ...ids, imdbId: ex.imdb_id }));
                    searchGuids.push(`imdb://${ex.imdb_id}`);
                  }
                  if (ex?.tvdb_id && media === 'tv') {
                    searchGuids.push(`tvdb://${ex.tvdb_id}`);
                  }
                } catch {}

                // Use backend GUID search for each GUID and merge
                try {
                  const t = media === 'movie' ? 1 : 2;
                  for (const guid of searchGuids) {
                    try {
                      const gr: any = await plexBackendFindByGuid(guid, t as 1|2);
                      const hits = (gr?.MediaContainer?.Metadata || []) as any[];
                      if (hits.length) allHits.push(...hits);
                    } catch {}
                  }
                } catch {}

                // Method 3: Title search as last resort
                if (allHits.length === 0) {
                  try {
                    const search: any = await plexBackendSearch(q, media === 'movie' ? 1 : 2);
                    allHits = (search?.MediaContainer?.Metadata || []) as any[];
                  } catch {}
                }

                // Deduplicate hits by ratingKey
                const uniqueHits = Array.from(
                  new Map(allHits.map(h => [h.ratingKey, h])).values()
                );

                // Find best match
                const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, '');
                const year = (d.release_date || d.first_air_date || '').slice(0,4);
                let match: any | undefined = undefined;

                // First priority: exact TMDB GUID match
                for (const h of uniqueHits) {
                  const guids: string[] = (h.Guid || []).map((g: any) => String(g.id||''));
                  if (guids.some(g => g === `tmdb://${tmdbId}` || g === `themoviedb://${tmdbId}`)) {
                    match = h;
                    break;
                  }
                }

                // Second priority: title and year match
                if (!match) {
                  for (const h of uniqueHits) {
                    const titleMatch = norm(h.title||h.grandparentTitle||'') === norm(q);
                    const yearMatch = !year || String(h.year||'') === year;
                    if (titleMatch && yearMatch) {
                      match = h;
                      break;
                    }
                  }
                }

                if (!match) {
                }
                if (match) {
                  // Replace backdrop with plex art for authenticity and add badges
                  const m = match;
                  setPlexMappedId(`plex:${String(m.ratingKey)}`);
                  setWatchIds((ids) => ({ ...ids, plexKey: String(m.ratingKey) }));
                  // Fetch ratings for mapped Plex item
                  try {
                    const r = await (await import('@/services/ratings')).fetchPlexRatingsByRatingKey(String(m.ratingKey));
                    if (r) setExternalRatings({ imdb: r.imdb || undefined, rt: r.rt || undefined });
                  } catch {}
                  setBackdrop(apiClient.getPlexImageNoToken((m.art || m.thumb || m.parentThumb || m.grandparentThumb) || '') || backdrop);
                  const extra: string[] = [];
                  const media0 = (m.Media || [])[0];
                  if (media0) {
                    const w = media0.width || 0; const h = media0.height || 0; if (w >= 3800 || h >= 2100) extra.push('4K');
                    const vp = (media0.videoProfile || '').toLowerCase(); if (vp.includes('hdr') || vp.includes('hlg')) extra.push('HDR'); if (vp.includes('dv')) extra.push('Dolby Vision');
                    const ap = (media0.audioProfile || '').toLowerCase(); const ac = (media0.audioCodec || '').toLowerCase(); if (ap.includes('atmos') || ac.includes('truehd')) extra.push('Atmos');
                  }
                  // Per-version details for mapped Plex item
                  try {
                    const vds: Array<{id:string; label:string; audios: Track[]; subs: Track[]; tech: any}> = (m.Media||[]).map((mm:any)=>{
                      const streams = mm?.Part?.[0]?.Stream || [];
                      const auds: Track[] = streams.filter((st:any)=>st.streamType===2).map((st:any, i:number)=>({ id: String(st.id || i), label: (st.displayTitle || st.languageTag || st.language || `Audio ${i+1}`), forced: st.forced }));
                      const subs: Track[] = streams.filter((st:any)=>st.streamType===3).map((st:any, i:number)=>({ id: String(st.id || i), label: (st.displayTitle || st.languageTag || st.language || `Sub ${i+1}`), forced: st.forced }));
                      const w = mm.width || 0; const h = mm.height || 0;
                      const techInfo = {
                        rating: m.contentRating || m.rating,
                        runtimeMin: Math.round((m.duration||0)/60000),
                        videoCodec: mm.videoCodec,
                        videoProfile: mm.videoProfile,
                        resolution: w&&h? `${w}x${h}`: undefined,
                        width: w,
                        height: h,
                        bitrate: mm.bitrate || undefined,
                        audioCodec: mm.audioCodec,
                        audioChannels: mm.audioChannels,
                        fileSize: mm.Part?.[0]?.size ? mm.Part[0].size / (1024*1024) : undefined,
                        container: mm.container || mm.Part?.[0]?.container,
                        subsCount: subs.length,
                      };
                      // Build descriptive label
                      const resLabel = w >= 3800 ? '4K' : w >= 1900 ? '1080p' : w >= 1200 ? '720p' : 'HD';
                      const codecLabel = String(mm.videoCodec || '').toUpperCase();
                      const audioLabel = mm.audioChannels >= 8 ? '7.1' : mm.audioChannels >= 6 ? '5.1' : mm.audioChannels >= 2 ? 'Stereo' : '';
                      const label = [resLabel, codecLabel, audioLabel].filter(Boolean).join(' ');
                      return { id: String(mm.id||mm.Id), label, audios: auds, subs, tech: techInfo };
                    });
                    setVersionDetails(vds);
                    setInfoVersion(vds[0]?.id);
                    // Detect CC/SDH/AD badges from first version (matching mobile/macOS logic)
                    const streams0 = (m.Media || [])[0]?.Part?.[0]?.Stream || [];
                    const subStreams0 = streams0.filter((st: any) => st.streamType === 3);
                    setHasCC(subStreams0.length > 0);
                    setHasSDH(subStreams0.some((st: any) => {
                      const title = ((st.displayTitle || st.title || '') as string).toUpperCase();
                      return title.includes('SDH') || title.includes('DEAF') || title.includes('HARD OF HEARING');
                    }));
                    setHasAD(streams0.filter((st: any) => st.streamType === 2).some((st: any) => {
                      const title = ((st.displayTitle || st.title || '') as string).toLowerCase();
                      return title.includes('description') || title.includes('descriptive') || title.includes(' ad');
                    }));
                  } catch {}
                  setBadges((b) => Array.from(new Set([...b, ...extra, 'Plex'])));
                  // If it's a show, load seasons/episodes
            if (m.type === 'show') {
              setShowKey(String(m.ratingKey));
              setOnDeck(await fetchOnDeck(String(m.ratingKey)));
              try {
                const ch: any = await plexBackendDir(`/library/metadata/${String(m.ratingKey)}/children`);
                const ss = (ch?.MediaContainer?.Metadata || []).map(plexSeason);
                setSeasons(ss);
                if (ss[0]) setSeasonKey(ss[0].key);
              } catch (e) { console.error(e); }
            }
                  // Trailer from Plex Extras for matched item
                  try {
                    const ex: any = await plexBackendMetadataWithExtras(String(m.ratingKey));
                    const em = ex?.MediaContainer?.Metadata?.[0]?.Extras?.Metadata?.[0];
                    const pkey = em?.Media?.[0]?.Part?.[0]?.key as string | undefined;
                    if (pkey) {
                      if (s.plexBaseUrl && s.plexToken) setPlexTrailerUrl(plexPartUrl(s.plexBaseUrl, s.plexToken, pkey));
                      scheduleTrailer();
                    }
                  } catch {}
                } else {
                  setBadges((b) => Array.from(new Set([...b, 'No local source'])));
                }
              }
            }
          }
        }
      } catch (e) { console.error(e); }
    }
    load();
    return () => timers.forEach((timer) => window.clearTimeout(timer));
  }, [id]);

  // Fetch VOD ratings automatically if Details id denotes a VOD item (plexvod:<id>)
  useEffect(() => {
    let alive = true;
    (async () => {
      if (!id || !id.startsWith('plexvod:')) return;
      const vid = id.replace(/^plexvod:/, '');
      try {
        const r = await fetchPlexVodRatingsById(vid);
        if (!alive) return;
        if (r) setExternalRatings({ imdb: r.imdb || undefined, rt: r.rt || undefined });
      } catch {}
    })();
    return () => { alive = false; };
  }, [id]);

  // MDBList ratings, when configured and the title's IMDb id is known.
  useEffect(() => {
    if (!imdbId || !kind || isEpisode) return;
    let alive = true;
    getMDBListRatings(imdbId, kind === 'movie' ? 'movie' : 'show')
      .then((ratings) => { if (alive) setMdblistRatings(ratings); })
      .catch(() => { if (alive) setMdblistRatings(null); });
    return () => { alive = false; };
  }, [imdbId, kind, isEpisode]);

  const ratings = useMemo<RatingsData | null>(() => {
    const plex = plexRatings;
    const mdb = mdblistRatings;
    // macOS shows TMDB's score under the IMDb mark when Plex and MDBList have none.
    const tmdbFallback = tmdbScore && tmdbScore > 0 ? Math.round(tmdbScore * 10) / 10 : undefined;
    if (!plex && !mdb && tmdbFallback === undefined) return null;
    const imdbScore = plex?.imdb?.rating ?? mdb?.imdb ?? tmdbFallback;
    const critic = plex?.rt?.critic ?? mdb?.tomatoes;
    const audience = plex?.rt?.audience ?? mdb?.audience;
    return {
      imdb: imdbScore != null ? { rating: imdbScore, votes: plex?.imdb?.votes } : null,
      rt: critic != null || audience != null ? { critic, audience } : null,
      letterboxd: mdb?.letterboxd,
      metacritic: mdb?.metacritic,
      tmdb: mdb?.tmdb,
      trakt: mdb?.trakt,
    };
  }, [plexRatings, mdblistRatings, tmdbScore]);

  const loadEpisodes = useCallback(async () => {
    if (!seasonKey) return;
    const showTmdbId = tmdbCtx?.media === 'tv' && tmdbCtx.id ? tmdbCtx.id : undefined;
    try {
      setEpisodesLoading(true);
      if (seasonKey.startsWith('tmdb:') && showTmdbId) {
        const tvSeason = Number(seasonKey.replace('tmdb:', ''));
        const [data, traktDone] = await Promise.all([
          tmdbTvSeasonDetails('', showTmdbId, tvSeason) as Promise<any>,
          traktCompletedEpisodes(showTmdbId, tvSeason),
        ]);
        const local = locallyWatchedEpisodes({ tmdbId: Number(showTmdbId), imdbId }, tvSeason);
        setEpisodes((data.episodes || []).map((e: any): DetailsEpisode => {
          const watched = local.has(`${tvSeason}:${e.episode_number}`) || traktDone.has(e.episode_number);
          return {
            id: `tmdb:tv:${showTmdbId}:s${tvSeason}e${e.episode_number}`,
            title: e.name,
            overview: e.overview,
            image: tmdbImage(e.still_path, 'w780'),
            duration: Math.round(e.runtime || 0),
            index: e.episode_number,
            progress: watched ? 100 : 0,
            airDate: e.air_date,
            seasonNumber: tvSeason,
            rating: e.vote_count > 0 ? e.vote_average : undefined,
            watched,
          };
        }));
      } else if (/^\d+$/.test(seasonKey)) {
        const season = seasons.find((candidate) => candidate.key === seasonKey);
        const seasonNumber = seasonNumberOf(season);
        const ch: any = await plexBackendDir(`/library/metadata/${seasonKey}/children?nocache=${Date.now()}`);

        // Prefer TMDB stills, and take episode ratings from the same response.
        const tmdbEpisodes = new Map<number, any>();
        if (showTmdbId && seasonNumber != null) {
          try {
            const tmdbSeason: any = await tmdbTvSeasonDetails('', showTmdbId, seasonNumber);
            for (const ep of tmdbSeason.episodes || []) tmdbEpisodes.set(ep.episode_number, ep);
          } catch { /* Plex images are fine */ }
        }

        setEpisodes((ch?.MediaContainer?.Metadata || []).map((e: any, idx: number): DetailsEpisode => {
          const index = e.index || idx + 1;
          const tmdbEp = tmdbEpisodes.get(index);
          const progress = plexEpisodeProgress(e);
          return {
            id: `plex:${e.ratingKey}`,
            title: e.title,
            overview: e.summary,
            image: tmdbImage(tmdbEp?.still_path, 'w780') || apiClient.getPlexImageNoToken((e.thumb || e.parentThumb) || ''),
            duration: Math.round((e.duration || 0) / 60000),
            index,
            progress,
            seasonNumber,
            plexRatingKey: String(e.ratingKey),
            rating: tmdbEp?.vote_count > 0 ? tmdbEp.vote_average : undefined,
            watched: progress >= 100,
          };
        }));
      }
    } catch (error) {
      console.error(error);
      setEpisodes([]);
    } finally {
      setEpisodesLoading(false);
    }
  }, [seasonKey, seasons, tmdbCtx, imdbId]);

  // Load episodes when a season is picked (Plex or TMDB)
  useEffect(() => { loadEpisodes(); }, [loadEpisodes]);

  const refreshProgress = useCallback(async () => {
    if (seasonKey) await loadEpisodes();
    if (kind === 'tv' && showKey) setOnDeck(await fetchOnDeck(showKey));
  }, [seasonKey, loadEpisodes, kind, showKey]);

  // Refresh when returning to the tab, and after any watched change.
  useEffect(() => {
    const onVisible = () => { if (document.visibilityState === 'visible') refreshProgress(); };
    document.addEventListener('visibilitychange', onVisible);
    const unsubscribe = subscribeWatchState(() => { refreshProgress(); });
    return () => {
      document.removeEventListener('visibilitychange', onVisible);
      unsubscribe();
    };
  }, [refreshProgress]);

  const titleTarget = useMemo<WatchTarget | undefined>(() => {
    if (!kind) return undefined;
    const tmdbId = tmdbCtx?.id || watchIds.tmdbId ? Number(tmdbCtx?.id || watchIds.tmdbId) : undefined;
    const plexKey = watchIds.plexKey || (id.startsWith('plex:') ? id.replace(/^plex:/, '') : undefined);
    if (isEpisode) {
      return {
        kind: 'episode',
        plexRatingKey: plexKey,
        showPlexRatingKey: showRatingKey ? String(showRatingKey) : undefined,
        showTmdbId: tmdbCtx?.id ? Number(tmdbCtx.id) : undefined,
        showImdbId: imdbId,
        seasonNumber: episodeNumbers.season,
        episodeNumber: episodeNumbers.episode,
        title,
      };
    }
    return { kind: kind === 'movie' ? 'movie' : 'show', plexRatingKey: plexKey, tmdbId, imdbId, title };
  }, [kind, tmdbCtx, watchIds, id, isEpisode, showRatingKey, imdbId, episodeNumbers, title]);

  const episodeTarget = useCallback((episode: DetailsEpisode): WatchTarget => ({
    kind: 'episode',
    plexRatingKey: episode.plexRatingKey,
    showPlexRatingKey: showKey,
    showTmdbId: tmdbCtx?.media === 'tv' && tmdbCtx.id ? Number(tmdbCtx.id) : undefined,
    showImdbId: imdbId,
    seasonNumber: episode.seasonNumber,
    episodeNumber: episode.index,
    title: `${title} ${episode.title}`.trim(),
  }), [showKey, tmdbCtx, imdbId, title]);

  const seasonTarget = useCallback((season: DetailsSeason): WatchTarget => ({
    kind: 'season',
    plexRatingKey: /^\d+$/.test(season.key) ? season.key : undefined,
    showPlexRatingKey: showKey,
    showTmdbId: tmdbCtx?.media === 'tv' && tmdbCtx.id ? Number(tmdbCtx.id) : undefined,
    showImdbId: imdbId,
    seasonNumber: seasonNumberOf(season),
    title: season.title,
  }), [showKey, tmdbCtx, imdbId]);

  return {
    title, overview, badges, backdrop, related, similar, meta, year, cast, poster, seasons, seasonKey, setSeasonKey,
    episodes, episodesLoading, onDeck, showKey, tech, versions, activeVersion, setActiveVersion, versionDetails,
    infoVersion, setInfoVersion, setAudioTracks, setSubtitleTracks, movieViewOffset, movieDuration,
    trailerKey, trailerMuted, showTrailer, plexTrailerUrl, logoUrl, imdbId, ratings, moodTags, plexMappedId, tmdbCtx,
    kind, watchIds, trailers, tagline, director, writers, productionCompanies, budget, revenue, status, releaseDate,
    originalLanguage, studio, numberOfSeasons, numberOfEpisodes, networks, audioTracks2, subtitleTracks2, container,
    fileSize, bitrate, hasCC, hasSDH, hasAD, isEpisode, showRatingKey, showTitle, episodeInfo, collectionId,
    titleTarget, episodeTarget, seasonTarget, refreshProgress,
  };
}

/** Episode numbers Trakt says are watched in one season, for TMDB-only shows. */
async function traktCompletedEpisodes(showTmdbId: string, season: number): Promise<Set<number>> {
  if (!isTraktConnected() || !getSettings().traktAutoSyncWatched) return new Set();
  try {
    const hit = await traktLookupId('tmdb', showTmdbId, 'show');
    const traktId = hit?.show?.ids?.trakt;
    if (traktId == null) return new Set();
    const progress = await traktShowProgress(traktId);
    const entry = progress.seasons?.find((s) => s.number === season);
    return new Set((entry?.episodes ?? []).filter((e) => e.completed).map((e) => e.number));
  } catch {
    return new Set();
  }
}

// Simple tag derivation from genres to mimic FLIXOR mood tags
function deriveTags(genres: string[]): string[] {
  const g = (genres || []).map(x => x.toLowerCase());
  const tags = new Set<string>();
  if (g.some(x=>['thriller','mystery','crime'].includes(x))) tags.add('Suspenseful');
  if (g.some(x=>['comedy','sitcom'].includes(x))) tags.add('Witty');
  if (g.some(x=>['action','adventure'].includes(x))) tags.add('Exciting');
  if (g.some(x=>['drama'].includes(x))) tags.add('Emotional');
  if (g.some(x=>['horror'].includes(x))) tags.add('Scary');
  if (g.some(x=>['family','kids'].includes(x))) tags.add('Family-friendly');
  if (g.some(x=>['documentary'].includes(x))) tags.add('Inspiring');
  return Array.from(tags).slice(0, 4);
}
