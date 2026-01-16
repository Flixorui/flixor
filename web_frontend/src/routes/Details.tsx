import { useParams, useNavigate } from 'react-router-dom';
import Badge from '@/components/Badge';
import Row from '@/components/Row';
import { loadSettings } from '@/state/settings';
import { plexMetadata, plexSearch, plexChildren, plexFindByGuid, plexComprehensiveGuidSearch, plexMetadataWithExtras, plexPartUrl } from '@/services/plex';
import { plexBackendMetadataWithExtras, plexBackendDir, plexBackendSearch, plexBackendFindByGuid, plexBackendMetadata } from '@/services/plex_backend';
import { tmdbDetails, tmdbImage, tmdbCredits, tmdbExternalIds, tmdbRecommendations, tmdbVideos, tmdbSearchTitle, tmdbTvSeasons, tmdbTvSeasonEpisodes, tmdbTvSeasonDetails, tmdbSimilar, tmdbImages } from '@/services/tmdb';
import { apiClient } from '@/services/api';
import { plexTvAddToWatchlist } from '@/services/plextv';
import { getTraktTokens, traktAddToWatchlist } from '@/services/trakt';
import PersonModal from '@/components/PersonModal';
import SmartImage from '@/components/SmartImage';
import { useEffect, useState } from 'react';
import DetailsHero from '@/components/DetailsHero';
import DetailsTabs from '@/components/DetailsTabs';
import TechnicalChips from '@/components/TechnicalChips';
import VersionPickerModal, { type VersionDetail } from '@/components/VersionPickerModal';
import Toast from '@/components/Toast';
import EpisodeItem from '@/components/EpisodeItem';
import EpisodeLandscapeCard from '@/components/EpisodeLandscapeCard';
import EpisodeSkeletonList from '@/components/EpisodeSkeletonList';
import SeasonSelector from '@/components/SeasonSelector';
import SkeletonRow from '@/components/SkeletonRow';
import TrackPicker, { Track } from '@/components/TrackPicker';
import BrowseModal from '@/components/BrowseModal';
import RatingsBar from '@/components/RatingsBar';
import UltraBlurBackground from '@/components/UltraBlurBackground';
import TrailerModal from '@/components/TrailerModal';
import ContentRatingBadge from '@/components/ContentRatingBadge';
import { fetchPlexRatingsByRatingKey, fetchPlexVodRatingsById } from '@/services/ratings';

export default function Details() {
  let { id } = useParams();
  id = id ? decodeURIComponent(id) : id;
  const nav = useNavigate();
  const [title, setTitle] = useState<string>('');
  const [overview, setOverview] = useState<string>('');
  const [badges, setBadges] = useState<string[]>([]);
  const [backdrop, setBackdrop] = useState<string>('');
  const [related, setRelated] = useState<any[]>([]);
  const [similar, setSimilar] = useState<any[]>([]);
  const [meta, setMeta] = useState<{ genres?: string[]; runtime?: number; rating?: string }>({});
  const [year, setYear] = useState<string | undefined>(undefined);
  const [cast, setCast] = useState<Array<{ id?: string; name: string; img?: string; character?: string }>>([]);
  const [plexWatch, setPlexWatch] = useState<string | undefined>(undefined);
  const [poster, setPoster] = useState<string | undefined>(undefined);
  const [toast, setToast] = useState<string>('');
  const [activeTab, setActiveTab] = useState<string>('SUGGESTED');
  const [seasons, setSeasons] = useState<Array<{key:string; title:string}>>([]);
  const [seasonKey, setSeasonKey] = useState<string>('');
  const [episodes, setEpisodes] = useState<any[]>([]);
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
  const [plexDetailsUrl, setPlexDetailsUrl] = useState<string | undefined>(undefined);
  // Movie resume/progress state
  const [movieViewOffset, setMovieViewOffset] = useState<number | undefined>(undefined); // in ms
  const [movieDuration, setMovieDuration] = useState<number | undefined>(undefined); // in ms
  const [trailerKey, setTrailerKey] = useState<string | undefined>(undefined);
  const [trailerMuted, setTrailerMuted] = useState<boolean>(true);
  const [showTrailer, setShowTrailer] = useState<boolean>(false);
  const [plexTrailerUrl, setPlexTrailerUrl] = useState<string | undefined>(undefined);
  const [logoUrl, setLogoUrl] = useState<string | undefined>(undefined);
  const [imdbId, setImdbId] = useState<string | undefined>(undefined);
  const [externalRatings, setExternalRatings] = useState<{ imdb?: { rating?: number; votes?: number } | null; rt?: { critic?: number; audience?: number } | null } | null>(null);
  const [showMediaInfo, setShowMediaInfo] = useState<boolean>(false);
  const [showVersionPicker, setShowVersionPicker] = useState<boolean>(false);
  const [moodTags, setMoodTags] = useState<string[]>([]);
  const [plexMappedId, setPlexMappedId] = useState<string | undefined>(undefined);
  const [personOpen, setPersonOpen] = useState(false);
  const [personId, setPersonId] = useState<string | undefined>(undefined);
  const [personName, setPersonName] = useState<string | undefined>(undefined);
  const [tmdbCtx, setTmdbCtx] = useState<{ media?: 'movie'|'tv'; id?: string } | undefined>(undefined);
  const [kind, setKind] = useState<'movie'|'tv'|undefined>(undefined);
  const [watchIds, setWatchIds] = useState<{ tmdbId?: string; imdbId?: string; plexKey?: string; media?: 'movie'|'tv' }>({});
  const [trailers, setTrailers] = useState<Array<{ id: string; key: string; name: string; site: string; type: string }>>([]);
  const [trailerModalOpen, setTrailerModalOpen] = useState(false);
  const [selectedTrailerKey, setSelectedTrailerKey] = useState<string | undefined>(undefined);
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

  // Layout settings
  const settings = loadSettings();
  const isUnifiedLayout = settings.detailsLayout === 'unified';
  const isHorizontalEpisodes = settings.episodeLayout === 'horizontal';

  useEffect(() => {
    // expose setter for trailer mute to toggle function
    (window as any).reactSetTrailerMuted = setTrailerMuted;
    const s = loadSettings();
    async function load() {
      if (!id) return;
      try {
        // Reset all state when navigating to a different details item
        setPlexMappedId(undefined);
        setShowTrailer(false);
        setTrailerKey(undefined);
        setPlexTrailerUrl(undefined);
        setTrailerMuted(true);
        setBackdrop('');
        setLogoUrl(undefined);
        // Reset episode state
        setIsEpisode(false);
        setShowRatingKey(undefined);
        setShowTitle(undefined);
        setEpisodeInfo(undefined);
        // Reset movie resume state
        setMovieViewOffset(undefined);
        setMovieDuration(undefined);
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
            if (m.type === 'episode') {
              setIsEpisode(true);
              setKind('tv');
              setShowRatingKey(m.grandparentRatingKey);
              setShowTitle(m.grandparentTitle);
              const seasonNum = m.parentIndex || m.seasonNumber;
              const epNum = m.index || m.episodeNumber;
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
              // Store viewOffset and duration for movie resume functionality
              if (m.type === 'movie' || m.type === 'episode') {
                setMovieViewOffset(m.viewOffset || undefined);
                setMovieDuration(m.duration || undefined);
              }
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
            // Build watch URL (first Part)
            const part = media?.Part?.[0];
            if (part?.id) {
              const url = `${s.plexBaseUrl!.replace(/\/$/, '')}/library/parts/${part.id}/stream?X-Plex-Token=${s.plexToken}`;
              setPlexWatch(url);
            } else { setToast('No direct stream found. Open in Plex.'); }
            setPlexDetailsUrl(`${s.plexBaseUrl!.replace(/\/$/, '')}/web/index.html#!/details?key=/library/metadata/${m.ratingKey}`);
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
            const tmdbGuid = (m.Guid || []).map((g:any)=>String(g.id||''))
              .find((g:string)=>g.includes('tmdb://')||g.includes('themoviedb://'));
            const imdbGuid = (m.Guid || []).map((g:any)=>String(g.id||''))
              .find((g:string)=>g.includes('imdb://'));
            setWatchIds({ tmdbId: tmdbGuid ? tmdbGuid.split('://')[1] : undefined, imdbId: imdbGuid ? imdbGuid.split('://')[1] : undefined, plexKey: String(m.ratingKey||''), media: (m.type==='movie'?'movie':'tv') });
            if (imdbGuid) {
              try { setImdbId(imdbGuid.split('://')[1]); } catch {}
            }
            if (s.tmdbBearer && tmdbGuid) {
              const tid = tmdbGuid.split('://')[1];
              const mediaType = (m.type === 'movie') ? 'movie' : 'tv';
              // For episodes, don't override kind - it's already set to 'tv'
              if (m.type !== 'episode') {
                setKind(mediaType);
              }
              // Also fetch external IDs to get IMDb id when available
              try {
                const exIds: any = await tmdbExternalIds(s.tmdbBearer!, mediaType as any, tid);
                if (exIds?.imdb_id) setImdbId(exIds.imdb_id);
              } catch {}
              setTmdbCtx({ media: mediaType as any, id: String(tid) });
                try {
                  const d: any = await tmdbDetails(s.tmdbBearer!, mediaType as any, tid);
                  // For episodes, preserve episode title/overview from Plex, only get show metadata
                  if (m.type !== 'episode') {
                    setTitle(d.title || d.name || title);
                    setOverview(d.overview || overview);
                  }
                  setPoster(tmdbImage(d.poster_path, 'w500') || poster);
                  setMeta({ genres: (d.genres||[]).map((x:any)=>x.name), runtime: Math.round((m.type === 'episode' ? (m.duration || 0) / 60000 : (d.runtime||d.episode_run_time?.[0]||0))), rating: m.contentRating || m.rating });
                  const y2 = (d.release_date || d.first_air_date || '').slice(0,4); if (y2) setYear(y2);
                  try { setMoodTags(deriveTags((d.genres||[]).map((g:any)=>g.name))); } catch {}
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
                  // Try fetch a logo image
                  try {
                    const imgs: any = await tmdbImages(s.tmdbBearer!, mediaType as any, tid, 'en,null');
                    const logo = (imgs?.logos||[]).find((l:any)=>l.iso_639_1==='en') || (imgs?.logos||[])[0];
                    if (logo?.file_path) setLogoUrl(tmdbImage(logo.file_path, 'w500') || tmdbImage(logo.file_path, 'original'));
                  } catch {}
                  try {
                    const cr: any = await tmdbCredits(s.tmdbBearer!, mediaType as any, tid);
                    setCast((cr.cast||[]).slice(0,16).map((c:any)=>({ id:String(c.id), name:c.name, img: tmdbImage(c.profile_path,'w500'), character: c.character })));
                    // Get director and writers from crew
                    const crew = cr.crew || [];
                    const directors = crew.filter((c: any) => c.job === 'Director').map((c: any) => c.name);
                    const writersList = crew.filter((c: any) => c.department === 'Writing' || c.job === 'Screenplay' || c.job === 'Writer').map((c: any) => c.name);
                    if (directors.length > 0) setDirector(directors.join(', '));
                    if (writersList.length > 0) setWriters([...new Set(writersList)].slice(0, 5));
                  } catch {}
                  try {
                  const vids:any = await tmdbVideos(s.tmdbBearer!, mediaType as any, tid);
                  console.log('[Details] TMDB videos response:', vids);
                  const ytVideos = (vids.results||[]).filter((v:any)=>v.site==='YouTube'&&(v.type==='Trailer'||v.type==='Teaser'||v.type==='Clip'||v.type==='Behind the Scenes'||v.type==='Featurette'));
                  console.log('[Details] Filtered trailers:', ytVideos);
                  setTrailers(ytVideos.map((v:any)=>({ id: v.id, key: v.key, name: v.name, site: v.site, type: v.type })));
                  const yt = ytVideos.find((v:any)=>v.type==='Trailer'||v.type==='Teaser');
                  if (yt) {
                    console.log('[Details] Found trailer, setting key:', yt.key);
                    setTimeout(()=>{ setTrailerKey(yt.key); setShowTrailer(true); }, 5000);
                  }
                } catch (e) { console.error('[Details] Error fetching videos:', e); }
                try {
                  const recs:any = await tmdbRecommendations(s.tmdbBearer!, mediaType as any, tid);
                  setRelated((recs.results||[]).slice(0,8).map((r:any)=>({ id:`tmdb:${mediaType}:${r.id}`, title:r.title||r.name, image: tmdbImage(r.backdrop_path,'w780')||tmdbImage(r.poster_path,'w500') })));
                } catch {}
                try {
                  const sim:any = await tmdbSimilar(s.tmdbBearer!, mediaType as any, tid);
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
                setPlexTrailerUrl(plexPartUrl(s.plexBaseUrl!, s.plexToken!, pkey));
                setTimeout(()=> setShowTrailer(true), 5000);
              }
            } catch {}
            // Seasons for Plex-native series
            if (m.type === 'show') {
              setKind('tv');
              setShowKey(rk);
              try {
                const ch: any = await plexBackendDir(`/library/metadata/${rk}/children`);
                const ss = (ch?.MediaContainer?.Metadata||[]).map((x:any)=>({ key:String(x.ratingKey), title:x.title }));
                setSeasons(ss);
                if (ss[0]) setSeasonKey(ss[0].key);
                setActiveTab('EPISODES');
              } catch (e) { console.error(e); }

              // Continue watching (onDeck) for shows
              try {
                const od: any = await plexBackendDir(`/library/metadata/${rk}/onDeck`);
                const ep = od?.MediaContainer?.Metadata?.[0];
                if (ep) {
                  setOnDeck({
                    id: `plex:${ep.ratingKey}`,
                    title: ep.title,
                    overview: ep.summary,
                    image: apiClient.getPlexImageNoToken(ep.thumb || ep.parentThumb || ''),
                    duration: Math.round((ep.duration||0)/60000),
                    progress: ep.viewOffset ? Math.round(((ep.viewOffset/1000)/((ep.duration||1)/1000))*100) : 0,
                    ratingKey: String(ep.ratingKey),
                  });
                } else {
                  setOnDeck(null);
                }
              } catch (e) { setOnDeck(null); }
            }
          }
        } else if (id.startsWith('tmdb:')) {
          const [, media, tmdbId] = id.split(':');
          if (s.tmdbBearer) {
            const d: any = await tmdbDetails(s.tmdbBearer!, media as any, tmdbId);
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
              const cr: any = await tmdbCredits(s.tmdbBearer!, media as any, tmdbId);
              setCast((cr.cast || []).slice(0, 16).map((c: any) => ({ id: String(c.id), name: c.name, img: tmdbImage(c.profile_path, 'w500'), character: c.character })));
              // Get director and writers from crew
              const crew = cr.crew || [];
              const directors = crew.filter((c: any) => c.job === 'Director').map((c: any) => c.name);
              const writersList = crew.filter((c: any) => c.department === 'Writing' || c.job === 'Screenplay' || c.job === 'Writer').map((c: any) => c.name);
              if (directors.length > 0) setDirector(directors.join(', '));
              if (writersList.length > 0) setWriters([...new Set(writersList)].slice(0, 5));
            } catch {}
            try {
              const vids: any = await tmdbVideos(s.tmdbBearer!, media as any, tmdbId);
              console.log('[Details TMDB] videos response:', vids);
              const ytVideos = (vids.results||[]).filter((v:any)=>v.site==='YouTube'&&(v.type==='Trailer'||v.type==='Teaser'||v.type==='Clip'||v.type==='Behind the Scenes'||v.type==='Featurette'));
              console.log('[Details TMDB] Filtered trailers:', ytVideos);
              setTrailers(ytVideos.map((v:any)=>({ id: v.id, key: v.key, name: v.name, site: v.site, type: v.type })));
              const yt = ytVideos.find((v:any)=>v.type==='Trailer'||v.type==='Teaser');
              if (yt) {
                console.log('[Details TMDB] Found trailer, setting key:', yt.key);
                setTimeout(() => { setTrailerKey(yt.key); setShowTrailer(true); }, 5000);
              }
            } catch (e) { console.error('[Details TMDB] Error fetching videos:', e); }
            try {
              const recs: any = await tmdbRecommendations(s.tmdbBearer!, media as any, tmdbId);
              setRelated((recs.results || []).slice(0, 8).map((r: any) => ({ id: `tmdb:${media}:${r.id}`, title: r.title || r.name, image: tmdbImage(r.backdrop_path, 'w780') || tmdbImage(r.poster_path, 'w500') })));
            } catch {}
            try {
              const sim: any = await tmdbSimilar(s.tmdbBearer!, media as any, tmdbId);
              setSimilar((sim.results || []).slice(0, 8).map((r: any) => ({ id: `tmdb:${media}:${r.id}`, title: r.title || r.name, image: tmdbImage(r.backdrop_path, 'w780') || tmdbImage(r.poster_path, 'w500') })));
            } catch {}
            setTmdbCtx({ media: media as any, id: String(tmdbId) });
            setWatchIds({ tmdbId: String(tmdbId), media: (media as any) });
            // Try to fetch a logo for the TMDB item
            try {
              const imgs: any = await tmdbImages(s.tmdbBearer!, media as any, tmdbId, 'en,null');
              const logo = (imgs?.logos||[]).find((l:any)=>l.iso_639_1==='en') || (imgs?.logos||[])[0];
              if (logo?.file_path) setLogoUrl(tmdbImage(logo.file_path, 'w500') || tmdbImage(logo.file_path, 'original'));
            } catch {}
            // TMDB seasons fallback (if mapping to Plex fails or no Plex)
            // Use "tmdb:" prefix to distinguish from Plex ratingKeys
            if (media === 'tv') {
              try {
                const tv: any = await tmdbTvSeasons(s.tmdbBearer!, tmdbId);
                const ss = (tv.seasons||[]).filter((x:any)=>x.season_number>0).map((x:any)=>({ key: `tmdb:${x.season_number}`, title: `Season ${x.season_number}` }));
                if (ss.length) {
                  setSeasons(ss);
                  setSeasonKey(ss[0].key);
                  setActiveTab('EPISODES');
                }
              } catch (e) { console.error(e); }
            }
            const bs: string[] = [];
            if ((d?.belongs_to_collection)) bs.push('Collection');
            if ((d?.runtime ?? 0) > 0 || (d?.episode_run_time?.[0] ?? 0) > 0) bs.push('Runtime');
            setBadges(bs);
            // Try find on Plex (first by GUID, then fallback title/year search)
            if (s.plexBaseUrl && s.plexToken) {
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
                  const ex: any = await tmdbExternalIds(s.tmdbBearer!, media as any, tmdbId);
                  if (ex?.imdb_id) {
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

                console.log(`[TMDB->Plex] Searching for TMDB ID: ${tmdbId}, Title: "${q}", Year: ${year}`);
                console.log(`[TMDB->Plex] Found ${uniqueHits.length} unique Plex items`);

                // First priority: exact TMDB GUID match
                for (const h of uniqueHits) {
                  const guids = (h.Guid || []).map((g: any) => String(g.id||''));
                  console.log(`[TMDB->Plex] Checking item "${h.title}" (${h.ratingKey}), GUIDs:`, guids);
                  if (guids.some(g => g === `tmdb://${tmdbId}` || g === `themoviedb://${tmdbId}`)) {
                    console.log(`[TMDB->Plex] ✓ Found exact TMDB match!`);
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
                      console.log(`[TMDB->Plex] ✓ Found title/year match: "${h.title}" (${h.year})`);
                      match = h;
                      break;
                    }
                  }
                }

                if (!match) {
                  console.log(`[TMDB->Plex] ✗ No match found for TMDB ID ${tmdbId}`);
                }
                if (match) {
                  // Replace backdrop with plex art for authenticity and add badges
                  const m = match;
                  setPlexMappedId(`plex:${String(m.ratingKey)}`);
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
                  const part = media0?.Part?.[0];
                  if (part?.id) setPlexWatch(`${s.plexBaseUrl!.replace(/\/$/, '')}/library/parts/${part.id}/stream?X-Plex-Token=${s.plexToken}`);
                  // If it's a show, load seasons/episodes
            if (m.type === 'show') {
              try {
                const ch: any = await plexBackendDir(`/library/metadata/${String(m.ratingKey)}/children`);
                const ss = (ch?.MediaContainer?.Metadata || []).map((x: any) => ({ key: String(x.ratingKey), title: x.title }));
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
                      setPlexTrailerUrl(plexPartUrl(s.plexBaseUrl!, s.plexToken!, pkey));
                      setTimeout(()=> setShowTrailer(true), 5000);
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

  // Load episodes when a season is picked (Plex or TMDB)
  useEffect(() => {
    const s = loadSettings();
    async function loadEps() {
      if (!seasonKey) return;
      try {
        setEpisodesLoading(true);

        // Check if this is a TMDB season (prefixed with "tmdb:")
        const isTmdbSeason = seasonKey.startsWith('tmdb:');

        if (isTmdbSeason && tmdbCtx?.media === 'tv' && tmdbCtx?.id) {
          // Load episodes from TMDB
          const tvSeason = Number(seasonKey.replace('tmdb:', ''));
          const data: any = await tmdbTvSeasonDetails(s.tmdbBearer!, tmdbCtx.id, tvSeason);
          const eps = (data.episodes||[]).map((e:any)=>({
            id: `tmdb:tv:${tmdbCtx.id}:s${tvSeason}e${e.episode_number}`,
            title: e.name,
            overview: e.overview,
            image: tmdbImage(e.still_path,'w780'),
            duration: Math.round((e.runtime||0)),
            index: e.episode_number,
            progress: 0,
            airDate: e.air_date,
          }));
          setEpisodes(eps);
        } else if (/^\d+$/.test(seasonKey)) {
          // Load episodes from Plex (seasonKey is a Plex ratingKey)
          const ch: any = await plexBackendDir(`/library/metadata/${seasonKey}/children?nocache=${Date.now()}`);

          // Try to get TMDB stills for better quality images
          let tmdbStills: Map<number, string> = new Map();
          if (tmdbCtx?.media === 'tv' && tmdbCtx?.id && s.tmdbBearer) {
            try {
              // Extract season number from season title (e.g., "Season 1" -> 1)
              const currentSeason = seasons.find(ss => ss.key === seasonKey);
              const seasonMatch = currentSeason?.title?.match(/\d+/);
              const seasonNum = seasonMatch ? parseInt(seasonMatch[0]) : 1;
              const tmdbSeason: any = await tmdbTvSeasonDetails(s.tmdbBearer, tmdbCtx.id, seasonNum);
              for (const ep of tmdbSeason.episodes || []) {
                if (ep.still_path) {
                  tmdbStills.set(ep.episode_number, tmdbImage(ep.still_path, 'w780') || '');
                }
              }
            } catch (e) { /* TMDB fetch failed, use Plex images */ }
          }

          const eps = (ch?.MediaContainer?.Metadata||[]).map((e:any, idx: number)=>({
            id: `plex:${e.ratingKey}`,
            title: e.title,
            overview: e.summary,
            // Prefer TMDB still over Plex thumb
            image: tmdbStills.get(e.index || idx + 1) || apiClient.getPlexImageNoToken((e.thumb || e.parentThumb) || ''),
            duration: Math.round((e.duration||0)/60000),
            index: e.index || idx + 1,
            progress: (() => {
              const dur = (e.duration||0)/1000; const vo = (e.viewOffset||0)/1000; const vc = e.viewCount||0;
              if (vc > 0) return 100;
              if (dur > 0 && vo/dur >= 0.95) return 100;
              if (dur > 0) return Math.round((vo/dur)*100);
              return 0;
            })(),
          }));
          setEpisodes(eps);
        }
      } catch (e) { console.error(e); setEpisodes([]); }
      finally { setEpisodesLoading(false); }
    }
    loadEps();
  }, [seasonKey, seasons, tmdbCtx]);

  // Refresh episodes and onDeck when returning to the tab (progress updates)
  useEffect(() => {
    const s = loadSettings();
    const onVis = async () => {
      if (document.visibilityState !== 'visible') return;
      try {
        if (activeTab === 'EPISODES' && seasonKey && /^\d+$/.test(seasonKey)) {
          setEpisodesLoading(true);
          const ch: any = await plexBackendDir(`/library/metadata/${seasonKey}/children?nocache=${Date.now()}`);

          // Try to get TMDB stills for better quality images
          let tmdbStills: Map<number, string> = new Map();
          if (tmdbCtx?.media === 'tv' && tmdbCtx?.id && s.tmdbBearer) {
            try {
              const currentSeason = seasons.find(ss => ss.key === seasonKey);
              const seasonMatch = currentSeason?.title?.match(/\d+/);
              const seasonNum = seasonMatch ? parseInt(seasonMatch[0]) : 1;
              const tmdbSeason: any = await tmdbTvSeasonDetails(s.tmdbBearer, tmdbCtx.id, seasonNum);
              for (const ep of tmdbSeason.episodes || []) {
                if (ep.still_path) {
                  tmdbStills.set(ep.episode_number, tmdbImage(ep.still_path, 'w780') || '');
                }
              }
            } catch (e) { /* TMDB fetch failed, use Plex images */ }
          }

          const eps = (ch?.MediaContainer?.Metadata||[]).map((e:any, idx: number)=>({
            id: `plex:${e.ratingKey}`,
            title: e.title,
            overview: e.summary,
            image: tmdbStills.get(e.index || idx + 1) || apiClient.getPlexImageNoToken((e.thumb || e.parentThumb) || ''),
            duration: Math.round((e.duration||0)/60000),
            index: e.index || idx + 1,
            progress: (() => {
              const dur = (e.duration||0)/1000; const vo = (e.viewOffset||0)/1000; const vc = e.viewCount||0;
              if (vc > 0) return 100;
              if (dur > 0 && vo/dur >= 0.95) return 100;
              if (dur > 0) return Math.round((vo/dur)*100);
              return 0;
            })(),
          }));
          setEpisodes(eps);
          setEpisodesLoading(false);
        }
        if (kind === 'tv' && showKey) {
          const od: any = await plexBackendDir(`/library/metadata/${showKey}/onDeck?nocache=${Date.now()}`);
          const ep = od?.MediaContainer?.Metadata?.[0];
          setOnDeck(ep ? {
            id: `plex:${ep.ratingKey}`,
            title: ep.title,
            overview: ep.summary,
            image: apiClient.getPlexImageNoToken(ep.thumb || ep.parentThumb || ''),
            duration: Math.round((ep.duration||0)/60000),
            progress: ep.viewOffset ? Math.round(((ep.viewOffset/1000)/((ep.duration||1)/1000))*100) : 0,
            ratingKey: String(ep.ratingKey),
          } : null);
        }
      } catch {}
    };
    document.addEventListener('visibilitychange', onVis);
    return () => document.removeEventListener('visibilitychange', onVis);
  }, [activeTab, seasonKey, kind, showKey, seasons, tmdbCtx]);

  const tabsData = seasons.length > 0
    ? [
        { id: 'EPISODES', label: 'Episodes', count: episodes.length || undefined },
        { id: 'SUGGESTED', label: 'Suggested' },
        { id: 'DETAILS', label: 'Details' }
      ]
    : [
        { id: 'SUGGESTED', label: 'Suggested' },
        { id: 'DETAILS', label: 'Details' }
      ];
  // Play with a specific version
  const playWithVersion = (version: VersionDetail) => {
    setShowVersionPicker(false);
    const targetId = (plexMappedId || id)!;
    nav(`/player/${encodeURIComponent(targetId)}?v=${encodeURIComponent(version.id)}`);
  };

  const playSelected = async () => {
    try {
    // For TV series, prefer on-deck episode or first episode
    if (kind === 'tv') {
      if (onDeck?.id) {
        nav(`/player/${encodeURIComponent(onDeck.id)}`);
        return;
      }
      if (episodes && episodes.length > 0) {
        nav(`/player/${encodeURIComponent(episodes[0].id)}`);
        return;
      }
    }
    // For movies with multiple versions, show version picker
    if (versionDetails.length > 1) {
      setShowVersionPicker(true);
      return;
    }
    // Otherwise go through in-app player for the item (movie or fallback)
    const targetId = (plexMappedId || id)!;
    const ver = activeVersion ? `?v=${encodeURIComponent(activeVersion)}` : '';
    nav(`/player/${encodeURIComponent(targetId)}${ver}`);
    } catch (e) { console.error(e); }
  };

  return (
    <UltraBlurBackground imageUrl={backdrop} className="min-h-screen">
      {toast && <Toast message={toast} onClose={() => setToast('')} />}
      <TrailerModal
        isOpen={trailerModalOpen}
        onClose={() => setTrailerModalOpen(false)}
        youtubeKey={selectedTrailerKey}
        title={title}
      />

      {/* Version Picker Modal */}
      <VersionPickerModal
        open={showVersionPicker}
        onClose={() => setShowVersionPicker(false)}
        title={title}
        versions={versionDetails as VersionDetail[]}
        onSelect={playWithVersion}
      />

      {/* Modern Hero Section - seamless blend */}
      <div className="relative" style={{
        background: 'linear-gradient(to bottom, transparent 0%, transparent 70%, #0b0b0b 100%)'
      }}>
        <DetailsHero
        key={id} // Force re-render when ID changes
        title={title}
        overview={overview}
        backdrop={backdrop || `https://picsum.photos/seed/details-${id}/1920/1080`}
        poster={poster}
        logo={logoUrl}
        year={year}
        rating={meta.rating}
        runtime={meta.runtime}
        genres={meta.genres}
        badges={badges}
        ratings={externalRatings || undefined}
        cast={cast}
        director={director}
        moodTags={moodTags}
        kind={kind}
        techInfo={{
          resolution: tech.resolution,
          hdr: (() => {
            const vp = (tech.videoProfile || '').toLowerCase();
            if (vp.includes('dv') || vp.includes('dolby vision')) return 'dolby vision';
            if (vp.includes('hdr10+')) return 'hdr10+';
            if (vp.includes('hdr10') || vp.includes('hdr')) return 'hdr10';
            if (vp.includes('hlg')) return 'hlg';
            return undefined;
          })(),
          videoCodec: tech.videoCodec,
          audioCodec: tech.audioCodec,
        }}
        hasMediaInfo={versions.length > 0}
        onToggleMediaInfo={() => setShowMediaInfo(v => !v)}
        showMediaInfo={showMediaInfo}
        versionDetails={versionDetails}
        infoVersion={infoVersion}
        onVersionChange={(id) => {
          setInfoVersion(id);
          setActiveVersion(id);
          const v = versionDetails.find(vd => vd.id === id);
          if (v) {
            setAudioTracks(v.audios);
            setSubtitleTracks(v.subs);
          }
        }}
        playable={id?.startsWith('plex:') || !!plexMappedId}
        onPlay={playSelected}
        onContinue={(() => {
          // For TV shows: use onDeck or find episode with progress
          if (kind === 'tv' && !isEpisode) {
            const cont = onDeck?.id || (episodes.find(e => (e.progress||0) > 0)?.id) || (episodes.find(e => (e.progress||0) < 100)?.id);
            return cont ? (() => nav(`/player/${encodeURIComponent(cont)}`)) : undefined;
          }
          // For movies and individual episodes: check viewOffset
          if ((kind === 'movie' || isEpisode) && movieViewOffset && movieViewOffset > 0 && movieDuration) {
            const progressPct = (movieViewOffset / movieDuration) * 100;
            // Only show continue if not near the end (< 95%)
            if (progressPct < 95) {
              const targetId = plexMappedId || id;
              return targetId ? (() => nav(`/player/${encodeURIComponent(targetId)}`)) : undefined;
            }
          }
          return undefined;
        })()}
        continueLabel={(() => {
          // For TV shows
          if (kind === 'tv' && !isEpisode) {
            return 'Continue Watching';
          }
          // For movies and episodes with progress
          if ((kind === 'movie' || isEpisode) && movieViewOffset && movieViewOffset > 0 && movieDuration) {
            const progressPct = (movieViewOffset / movieDuration) * 100;
            if (progressPct < 95) {
              // Format remaining time
              const remainingMs = movieDuration - movieViewOffset;
              const remainingMin = Math.round(remainingMs / 60000);
              if (remainingMin >= 60) {
                const hours = Math.floor(remainingMin / 60);
                const mins = remainingMin % 60;
                return `Resume · ${hours}h ${mins}m left`;
              }
              return `Resume · ${remainingMin}m left`;
            }
          }
          return undefined;
        })()}
        watchlistProps={{
          itemId: id!,
          itemType: (kind==='tv'?'show':'movie') as any,
          tmdbId: tmdbCtx?.id || watchIds.tmdbId,
        }}
        requestProps={tmdbCtx?.id ? {
          tmdbId: Number(tmdbCtx.id),
          mediaType: tmdbCtx.media || 'movie',
        } : undefined}
        onMarkWatched={() => setToast('Marked as Watched')}
        onPersonClick={(person) => {
          setPersonId(person.id);
          setPersonName(person.name);
          setPersonOpen(true);
        }}
        trailerUrl={plexTrailerUrl}
        trailerKey={trailerKey}
        trailerMuted={trailerMuted}
        showTrailer={showTrailer}
        onToggleMute={toggleMute}
        trailers={trailers}
        onTrailerClick={(trailer) => {
          setSelectedTrailerKey(trailer.key);
          setTrailerModalOpen(true);
        }}
        hasCC={hasCC}
        hasSDH={hasSDH}
        hasAD={hasAD}
        isEpisode={isEpisode}
        showTitle={showTitle}
        episodeInfo={episodeInfo}
        onViewShow={showRatingKey ? () => nav(`/details/plex:${showRatingKey}`) : undefined}
      />
      </div>

      {/* Continue Watching for TV shows */}
      {kind === 'tv' && onDeck && (
        <div className="page-gutter-left mt-4">
          <div className="bg-white/5 rounded-xl ring-1 ring-white/10 overflow-hidden">
            <div className="px-4 py-3 text-white/90 font-semibold">Continue watching</div>
            <div className="px-3 pb-3">
              <EpisodeItem ep={{
                id: onDeck.id,
                title: onDeck.title,
                overview: onDeck.overview,
                image: onDeck.image,
                duration: onDeck.duration,
                progress: onDeck.progress,
              }} onClick={(eid)=> nav(`/player/${encodeURIComponent(eid)}`)} />
            </div>
          </div>
        </div>
      )}

      {/* Ratings now inline with metadata row in DetailsHero */}

      {/* Tabs Navigation - only show in tabbed mode */}
      {!isUnifiedLayout && (
        <DetailsTabs
          tabs={tabsData}
          activeTab={activeTab}
          onTabChange={setActiveTab}
        />
      )}

      {/* Content Section Below Hero */}
      <div className="page-gutter-left py-8">
        {/* Unified Layout - single scrollable view */}
        {isUnifiedLayout ? (
          <div className="space-y-12">
            {/* Episodes Section (TV shows only) */}
            {seasons.length > 0 && (
              <section>
                <h2 className="text-lg font-bold text-white mb-3">Episodes</h2>
                <SeasonSelector
                  seasons={seasons}
                  seasonKey={seasonKey}
                  onChange={(key) => setSeasonKey(key)}
                />
                {isHorizontalEpisodes ? (
                  <div className="mt-3">
                    <h3 className="text-lg font-extrabold text-white mb-2">
                      Season {seasons.find(s => s.key === seasonKey)?.title?.replace(/Season\s*/i, '') || seasonKey.replace('tmdb:', '')}
                    </h3>
                    <div className="overflow-x-auto pb-4 -mx-4 px-4 no-scrollbar">
                      <div className="flex gap-4" style={{ minWidth: 'max-content' }}>
                        {episodesLoading ? (
                          Array.from({ length: 5 }).map((_, i) => (
                            <div key={i} className="w-[320px] aspect-[16/10] bg-white/10 rounded-xl animate-pulse flex-shrink-0" />
                          ))
                        ) : episodes.length ? (
                          episodes.map((e: any, idx: number) => (
                            <EpisodeLandscapeCard
                              key={e.id || idx}
                              ep={{
                                id: e.id,
                                title: e.title,
                                overview: e.overview,
                                image: e.image,
                                duration: e.duration,
                                progress: e.progress,
                                index: e.index ?? idx + 1,
                                airDate: e.airDate,
                              }}
                              onClick={(eid) => nav(`/player/${encodeURIComponent(eid)}`)}
                              disabled={e.id?.startsWith('tmdb:')}
                            />
                          ))
                        ) : (
                          <div className="text-white/60 py-8">{badges.includes('No local source') ? 'No source found' : 'No episodes found'}</div>
                        )}
                      </div>
                    </div>
                  </div>
                ) : (
                  <div className="space-y-4 mt-4">
                    {episodesLoading ? (
                      <EpisodeSkeletonList />
                    ) : episodes.length ? (
                      episodes.map((e: any, idx: number) => (
                        <EpisodeItem
                          key={e.id || idx}
                          ep={{ ...e, index: idx + 1 }}
                          onClick={(eid) => nav(`/player/${encodeURIComponent(eid)}`)}
                          disabled={e.id?.startsWith('tmdb:')}
                        />
                      ))
                    ) : (
                      <div className="text-white/60 text-center py-10">{badges.includes('No local source') ? 'No source found' : 'No episodes found'}</div>
                    )}
                  </div>
                )}
              </section>
            )}

            {/* Suggested Section */}
            {(related.length > 0 || similar.length > 0) && (
              <section className="space-y-8">
                {related.length > 0 && (
                  <Row
                    title="Recommendations"
                    items={related as any}
                    browseKey={tmdbCtx?.id ? `tmdb:recs:${tmdbCtx.media}:${tmdbCtx.id}` : undefined}
                    gutter="edge"
                    onItemClick={(id) => nav(`/details/${encodeURIComponent(id)}`)}
                  />
                )}
                {similar.length > 0 && (
                  <Row
                    title="More Like This"
                    items={similar as any}
                    browseKey={tmdbCtx?.id ? `tmdb:similar:${tmdbCtx.media}:${tmdbCtx.id}` : undefined}
                    gutter="edge"
                    onItemClick={(id) => nav(`/details/${encodeURIComponent(id)}`)}
                  />
                )}
              </section>
            )}

            {/* Details Section */}
            <section className="space-y-8">
              {/* About */}
              <div>
                <h3 className="text-lg font-bold text-white mb-2">About</h3>
                {tagline && (
                  <p className="text-white/70 italic mb-4">"{tagline}"</p>
                )}
                <div className="bg-white/5 rounded-xl p-4 ring-1 ring-white/10">
                  <div className="flex justify-between items-start">
                    <div className="flex-1">
                      <h4 className="text-white font-semibold text-lg mb-1">{title}</h4>
                      <p className="text-white/60 text-sm mb-3">
                        {meta.genres?.join(', ').toUpperCase()}
                      </p>
                      <p className="text-white/80 text-sm leading-relaxed">{overview}</p>
                    </div>
                    {meta.rating && (
                      <div className="ml-4 flex-shrink-0">
                        <ContentRatingBadge rating={meta.rating} size="lg" />
                      </div>
                    )}
                  </div>
                </div>
              </div>

              {/* Cast & Crew */}
              {cast.length > 0 && (
                <div>
                  <h3 className="text-lg font-bold text-white mb-4">Cast & Crew</h3>
                  <div className="overflow-x-auto pb-4 -mx-4 px-4">
                    <div className="flex gap-4" style={{ minWidth: 'max-content' }}>
                      {cast.map((c, i) => (
                        <button
                          key={i}
                          onClick={() => {
                            setPersonId(c.id);
                            setPersonName(c.name);
                            setPersonOpen(true);
                          }}
                          className="flex-shrink-0 text-center hover:opacity-80 transition-opacity w-20"
                        >
                          <div className="w-20 h-20 rounded-full overflow-hidden bg-white/10 mb-2 mx-auto ring-1 ring-white/10">
                            {c.img ? (
                              <SmartImage url={c.img} alt={c.name} width={80} className="w-full h-full" imgClassName="object-cover" />
                            ) : (
                              <div className="w-full h-full flex items-center justify-center text-white/20">
                                <svg className="w-8 h-8" fill="currentColor" viewBox="0 0 24 24">
                                  <path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z" />
                                </svg>
                              </div>
                            )}
                          </div>
                          <p className="text-xs text-white font-medium truncate">{c.name}</p>
                          {c.character && (
                            <p className="text-xs text-white/50 truncate">{c.character}</p>
                          )}
                        </button>
                      ))}
                    </div>
                  </div>
                </div>
              )}

              {/* Production */}
              {((kind === 'movie' && productionCompanies.length > 0) || (kind === 'tv' && networks.length > 0)) && (
                <div>
                  <h3 className="text-lg font-bold text-white mb-4">{kind === 'movie' ? 'Production' : 'Network'}</h3>
                  <div className="flex flex-wrap gap-3">
                    {(kind === 'movie' ? productionCompanies : networks).slice(0, 6).map((company) => (
                      <div
                        key={company.id}
                        className="px-4 py-3 bg-white rounded-xl flex items-center justify-center min-h-[44px]"
                      >
                        {company.logo ? (
                          <img
                            src={company.logo}
                            alt={company.name}
                            className="h-6 w-auto max-w-[80px] object-contain"
                            style={{ filter: 'brightness(0)' }}
                          />
                        ) : (
                          <span className="text-black text-sm font-semibold">{company.name}</span>
                        )}
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Info Grid */}
              <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
                <div>
                  <h3 className="text-lg font-bold text-white mb-4">Information</h3>
                  <div className="space-y-3">
                    <InfoRow label="Released" value={releaseDate ? new Date(releaseDate).getFullYear().toString() : year} />
                    <InfoRow label="Run Time" value={meta.runtime ? `${Math.floor(meta.runtime / 60)}h ${meta.runtime % 60}min` : undefined} />
                    <InfoRow label="Rated" value={meta.rating} />
                    <InfoRow label="Status" value={status} />
                    {director && <InfoRow label="Directed By" value={director} />}
                    {writers.length > 0 && <InfoRow label="Written By" value={writers.join(', ')} />}
                  </div>
                </div>
                <div>
                  <h3 className="text-lg font-bold text-white mb-4">Languages</h3>
                  <div className="space-y-3">
                    <InfoRow label="Original Audio" value={originalLanguage?.toUpperCase() || 'English'} />
                    {audioTracks2.length > 0 && (
                      <div>
                        <p className="text-white/50 text-sm">Audio</p>
                        <p className="text-white/90 text-sm">{audioTracks2.slice(0, 3).join(', ')}</p>
                      </div>
                    )}
                  </div>
                </div>
                <div>
                  <h3 className="text-lg font-bold text-white mb-4">Technical</h3>
                  <div className="space-y-3">
                    <InfoRow label="Resolution" value={tech.resolution} />
                    <InfoRow label="Video" value={tech.videoCodec?.toUpperCase()} />
                    <InfoRow label="Audio" value={tech.audioCodec?.toUpperCase()} />
                    <InfoRow label="Bitrate" value={bitrate ? `${bitrate} Mbps` : undefined} />
                    <InfoRow label="File Size" value={fileSize ? `${fileSize.toFixed(1)} GB` : undefined} />
                  </div>
                </div>
              </div>
            </section>
          </div>
        ) : (
          <>
            {/* Tabbed Layout - original implementation */}
            {/* Season Selector */}
            {activeTab === 'EPISODES' && seasons.length > 0 && (
              <div className="mb-4">
                <SeasonSelector
                  seasons={seasons}
                  seasonKey={seasonKey}
                  onChange={(key) => setSeasonKey(key)}
                />
              </div>
            )}

            {/* Tab Content */}
            {activeTab === 'EPISODES' && seasons.length > 0 && (
              <section>
                <h3 className="text-lg font-extrabold text-white mb-2">
                  Season {seasons.find(s => s.key === seasonKey)?.title?.replace(/Season\s*/i, '') || seasonKey.replace('tmdb:', '')}
                </h3>
                {isHorizontalEpisodes ? (
                  <div className="overflow-x-auto pb-4 -mx-4 px-4 no-scrollbar">
                    <div className="flex gap-4" style={{ minWidth: 'max-content' }}>
                      {episodesLoading ? (
                        Array.from({ length: 5 }).map((_, i) => (
                          <div key={i} className="w-[320px] aspect-[16/10] bg-white/10 rounded-xl animate-pulse flex-shrink-0" />
                        ))
                      ) : episodes.length ? (
                        episodes.map((e: any, idx: number) => (
                          <EpisodeLandscapeCard
                            key={e.id || idx}
                            ep={{
                              id: e.id,
                              title: e.title,
                              overview: e.overview,
                              image: e.image,
                              duration: e.duration,
                              progress: e.progress,
                              index: e.index ?? idx + 1,
                              airDate: e.airDate,
                            }}
                            onClick={(eid) => nav(`/player/${encodeURIComponent(eid)}`)}
                            disabled={e.id?.startsWith('tmdb:')}
                          />
                        ))
                      ) : (
                        <div className="text-white/60 py-8">{badges.includes('No local source') ? 'No source found' : 'No episodes found'}</div>
                      )}
                    </div>
                  </div>
                ) : (
                  <div className="space-y-4">
                    {episodesLoading ? (
                      <EpisodeSkeletonList />
                    ) : episodes.length ? (
                      episodes.map((e: any, idx: number) => (
                        <EpisodeItem
                          key={e.id || idx}
                          ep={{ ...e, index: idx + 1 }}
                          onClick={(eid) => nav(`/player/${encodeURIComponent(eid)}`)}
                          disabled={e.id?.startsWith('tmdb:')}
                        />
                      ))
                    ) : (
                      <div className="text-white/60 text-center py-10">{badges.includes('No local source') ? 'No source found' : 'No episodes found'}</div>
                    )}
                  </div>
                )}
              </section>
            )}

            {activeTab === 'SUGGESTED' && (
              <section className="space-y-8">
                {related.length > 0 ? (
                  <>
                    <Row
                      title="Recommendations"
                      items={related as any}
                      browseKey={tmdbCtx?.id ? `tmdb:recs:${tmdbCtx.media}:${tmdbCtx.id}` : undefined}
                      gutter="edge"
                      onItemClick={(id) => nav(`/details/${encodeURIComponent(id)}`)}
                    />
                    {similar.length > 0 && (
                      <Row
                        title="More Like This"
                        items={similar as any}
                        browseKey={tmdbCtx?.id ? `tmdb:similar:${tmdbCtx.media}:${tmdbCtx.id}` : undefined}
                        gutter="edge"
                        onItemClick={(id) => nav(`/details/${encodeURIComponent(id)}`)}
                      />
                    )}
                  </>
                ) : (
                  <SkeletonRow />
                )}
              </section>
            )}

            {activeTab === 'DETAILS' && (
              <section className="space-y-8">
                {/* About Section */}
                <div>
                  <h3 className="text-lg font-bold text-white mb-2">About</h3>
                  {tagline && (
                    <p className="text-white/70 italic mb-4">"{tagline}"</p>
                  )}
                  <div className="bg-white/5 rounded-xl p-4 ring-1 ring-white/10">
                    <div className="flex justify-between items-start">
                      <div className="flex-1">
                        <h4 className="text-white font-semibold text-lg mb-1">{title}</h4>
                        <p className="text-white/60 text-sm mb-3">
                          {meta.genres?.join(', ').toUpperCase()}
                        </p>
                        <p className="text-white/80 text-sm leading-relaxed">{overview}</p>
                      </div>
                      {meta.rating && (
                        <div className="ml-4 flex-shrink-0">
                          <ContentRatingBadge rating={meta.rating} size="lg" />
                        </div>
                      )}
                    </div>
                  </div>
                </div>

                {/* Cast & Crew Section */}
                {cast.length > 0 && (
                  <div>
                    <div className="flex items-center gap-1 mb-4 group">
                      <h3 className="text-lg font-bold text-white">Cast & Crew</h3>
                      <svg className="w-5 h-5 text-white/50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
                      </svg>
                    </div>
                    <div className="overflow-x-auto pb-4 -mx-4 px-4">
                      <div className="flex gap-4" style={{ minWidth: 'max-content' }}>
                        {cast.map((c, i) => (
                          <button
                            key={i}
                            onClick={() => {
                              setPersonId(c.id);
                              setPersonName(c.name);
                              setPersonOpen(true);
                            }}
                            className="flex-shrink-0 text-center hover:opacity-80 transition-opacity w-20"
                          >
                            <div className="w-20 h-20 rounded-full overflow-hidden bg-white/10 mb-2 mx-auto ring-1 ring-white/10">
                              {c.img ? (
                                <SmartImage url={c.img} alt={c.name} width={80} className="w-full h-full" imgClassName="object-cover" />
                              ) : (
                                <div className="w-full h-full flex items-center justify-center text-white/20">
                                  <svg className="w-8 h-8" fill="currentColor" viewBox="0 0 24 24">
                                    <path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z" />
                                  </svg>
                                </div>
                              )}
                            </div>
                            <p className="text-xs text-white font-medium truncate">{c.name}</p>
                            {c.character && (
                              <p className="text-xs text-white/50 truncate">{c.character}</p>
                            )}
                          </button>
                        ))}
                      </div>
                    </div>
                  </div>
                )}

                {/* Production Companies / Networks Section */}
                {((kind === 'movie' && productionCompanies.length > 0) || (kind === 'tv' && networks.length > 0)) && (
                  <div>
                    <h3 className="text-lg font-bold text-white mb-4">{kind === 'movie' ? 'Production' : 'Network'}</h3>
                    <div className="flex flex-wrap gap-3">
                      {(kind === 'movie' ? productionCompanies : networks).slice(0, 6).map((company) => (
                        <div
                          key={company.id}
                          className="px-4 py-3 bg-white rounded-xl flex items-center justify-center min-h-[44px]"
                        >
                          {company.logo ? (
                            <img
                              src={company.logo}
                              alt={company.name}
                              className="h-6 w-auto max-w-[80px] object-contain"
                              style={{ filter: 'brightness(0)' }}
                            />
                          ) : (
                            <span className="text-black text-sm font-semibold">{company.name}</span>
                          )}
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {/* Three Column Info Grid */}
                <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
                  {/* Information Column */}
                  <div>
                    <h3 className="text-lg font-bold text-white mb-4">Information</h3>
                    <div className="space-y-3">
                      <InfoRow label="Released" value={releaseDate ? new Date(releaseDate).getFullYear().toString() : year} />
                      <InfoRow label="Run Time" value={meta.runtime ? `${Math.floor(meta.runtime / 60)}h ${meta.runtime % 60}min` : undefined} />
                      <InfoRow label="Rated" value={meta.rating} />
                      <InfoRow label="Status" value={status} />
                      {kind === 'movie' && budget && budget > 0 && (
                        <InfoRow label="Budget" value={`$${(budget / 1000000).toFixed(0)}M`} />
                      )}
                      {kind === 'movie' && revenue && revenue > 0 && (
                        <InfoRow label="Box Office" value={`$${(revenue / 1000000).toFixed(1)}M`} />
                      )}
                      <InfoRow label="Original Language" value={originalLanguage?.toUpperCase()} />
                      <InfoRow label="Studio" value={studio} />
                      {director && <InfoRow label="Directed By" value={director} />}
                      {writers.length > 0 && <InfoRow label="Written By" value={writers.join(', ')} />}
                      {kind === 'tv' && numberOfSeasons && <InfoRow label="Seasons" value={String(numberOfSeasons)} />}
                      {kind === 'tv' && numberOfEpisodes && <InfoRow label="Episodes" value={String(numberOfEpisodes)} />}
                    </div>
                  </div>

                  {/* Languages Column */}
                  <div>
                    <h3 className="text-lg font-bold text-white mb-4">Languages</h3>
                    <div className="space-y-3">
                      <InfoRow label="Original Audio" value={originalLanguage?.toUpperCase() || 'English'} />
                      {audioTracks2.length > 0 && (
                        <div>
                          <p className="text-white/50 text-sm mb-1">Audio</p>
                          <p className="text-white/90 text-sm">{audioTracks2.join(', ')}</p>
                        </div>
                      )}
                      {subtitleTracks2.length > 0 && (
                        <div>
                          <p className="text-white/50 text-sm mb-1">Subtitles</p>
                          <p className="text-white/90 text-sm leading-relaxed">{subtitleTracks2.join(', ')}</p>
                        </div>
                      )}
                    </div>
                  </div>

                  {/* Technical Column */}
                  <div>
                    <h3 className="text-lg font-bold text-white mb-4">Technical</h3>
                    <div className="space-y-3">
                      <InfoRow label="Resolution" value={tech.resolution} />
                      <InfoRow label="Video" value={tech.videoCodec?.toUpperCase()} />
                      <InfoRow label="Audio" value={tech.audioCodec ? `${tech.audioCodec.toUpperCase()} ${tech.audioChannels || ''}ch` : undefined} />
                      <InfoRow label="HDR" value={tech.videoProfile?.includes('dv') || tech.videoProfile?.includes('hdr') ? (tech.videoProfile.includes('dv') ? 'Dolby Vision' : 'HDR10') : undefined} />
                      <InfoRow label="Container" value={container?.toUpperCase()} />
                      <InfoRow label="Bitrate" value={bitrate ? `${bitrate} Mbps` : undefined} />
                      <InfoRow label="File Size" value={fileSize ? `${fileSize.toFixed(1)} GB` : undefined} />
                    </div>
                  </div>
                </div>

                {/* Ratings Section */}
                {externalRatings && (externalRatings.imdb || externalRatings.rt) && (
                  <div>
                    <h3 className="text-lg font-bold text-white mb-4">Ratings</h3>
                    <RatingsBar imdb={externalRatings.imdb || undefined} rt={externalRatings.rt || undefined} />
                  </div>
                )}
              </section>
            )}
          </>
        )}
      </div>
      <PersonModal open={personOpen} onClose={()=> setPersonOpen(false)} personId={personId} name={personName} tmdbKey={loadSettings().tmdbBearer} />
      <BrowseModal />
    </UltraBlurBackground>
  );
}

// Removed custom addToMyList in favor of WatchlistButton in hero

async function watchOnPlex(url: string) {
  try {
    // Web-only: open in a new tab
    window.open(url, '_blank');
  } catch (e) { console.error(e); }
}

function openPerson(c: { id?: string; name: string }) {
  if (c.id) {
    window.history.pushState({}, '', `/person/${encodeURIComponent(c.id)}`);
    window.dispatchEvent(new PopStateEvent('popstate'));
  } else {
    window.history.pushState({}, '', `/person?name=${encodeURIComponent(c.name)}`);
    window.dispatchEvent(new PopStateEvent('popstate'));
  }
}

function toggleMute() {
  // Prefer toggling HTML5 video if present
  const vid = document.getElementById('plex-trailer') as HTMLVideoElement | null;
  if (vid) {
    vid.muted = !vid.muted;
    const root = (window as any).reactSetTrailerMuted as ((v:boolean)=>void)|undefined;
    if (root) root(vid.muted);
    return;
  }
  const iframe = document.getElementById('yt-trailer') as HTMLIFrameElement | null;
  if (!iframe || !iframe.contentWindow) return;
  try {
    // Toggle mute via YouTube Iframe API postMessage
    const muted = !(window as any)._ytMuted;
    (window as any)._ytMuted = muted;
    const msg = JSON.stringify({ event: 'command', func: muted ? 'mute' : 'unMute', args: [] });
    iframe.contentWindow.postMessage(msg, '*');
    // Also reflect in React state
    const root = (window as any).reactSetTrailerMuted as ((v:boolean)=>void)|undefined;
    if (root) root(muted);
  } catch (e) { console.error(e); }
}

// Info row component for details section
function InfoRow({ label, value }: { label: string; value?: string }) {
  if (!value) return null;
  return (
    <div>
      <p className="text-white/50 text-sm">{label}</p>
      <p className="text-white/90 text-sm">{value}</p>
    </div>
  );
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
