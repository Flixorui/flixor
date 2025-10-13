import { useParams, useNavigate } from 'react-router-dom';
import Badge from '@/components/Badge';
import Row from '@/components/Row';
import { loadSettings } from '@/state/settings';
import { plexMetadata, plexSearch, plexChildren, plexFindByGuid, plexComprehensiveGuidSearch, plexMetadataWithExtras, plexPartUrl } from '@/services/plex';
import { plexBackendMetadataWithExtras, plexBackendDir, plexBackendSearch, plexBackendFindByGuid, plexBackendMetadata } from '@/services/plex_backend';
import { tmdbDetails, tmdbImage, tmdbCredits, tmdbExternalIds, tmdbRecommendations, tmdbVideos, tmdbSearchTitle, tmdbTvSeasons, tmdbTvSeasonEpisodes, tmdbSimilar, tmdbImages } from '@/services/tmdb';
import { apiClient } from '@/services/api';
import { plexTvAddToWatchlist } from '@/services/plextv';
import { getTraktTokens, traktAddToWatchlist } from '@/services/trakt';
import PersonModal from '@/components/PersonModal';
import SmartImage from '@/components/SmartImage';
import { useEffect, useState } from 'react';
import DetailsHero from '@/components/DetailsHero';
import DetailsTabs from '@/components/DetailsTabs';
import TechnicalChips from '@/components/TechnicalChips';
import VersionSelector from '@/components/VersionSelector';
import Toast from '@/components/Toast';
import EpisodeItem from '@/components/EpisodeItem';
import EpisodeSkeletonList from '@/components/EpisodeSkeletonList';
import SkeletonRow from '@/components/SkeletonRow';
import TrackPicker, { Track } from '@/components/TrackPicker';
import BrowseModal from '@/components/BrowseModal';
import RatingsBar from '@/components/RatingsBar';
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
  const [cast, setCast] = useState<Array<{ id?: string; name: string; img?: string }>>([]);
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
  const [trailerKey, setTrailerKey] = useState<string | undefined>(undefined);
  const [trailerMuted, setTrailerMuted] = useState<boolean>(true);
  const [showTrailer, setShowTrailer] = useState<boolean>(false);
  const [plexTrailerUrl, setPlexTrailerUrl] = useState<string | undefined>(undefined);
  const [logoUrl, setLogoUrl] = useState<string | undefined>(undefined);
  const [imdbId, setImdbId] = useState<string | undefined>(undefined);
  const [externalRatings, setExternalRatings] = useState<{ imdb?: { rating?: number; votes?: number } | null; rt?: { critic?: number; audience?: number } | null } | null>(null);
  const [showMediaInfo, setShowMediaInfo] = useState<boolean>(false);
  const [moodTags, setMoodTags] = useState<string[]>([]);
  const [plexMappedId, setPlexMappedId] = useState<string | undefined>(undefined);
  const [personOpen, setPersonOpen] = useState(false);
  const [personId, setPersonId] = useState<string | undefined>(undefined);
  const [personName, setPersonName] = useState<string | undefined>(undefined);
  const [tmdbCtx, setTmdbCtx] = useState<{ media?: 'movie'|'tv'; id?: string } | undefined>(undefined);
  const [kind, setKind] = useState<'movie'|'tv'|undefined>(undefined);
  const [watchIds, setWatchIds] = useState<{ tmdbId?: string; imdbId?: string; plexKey?: string; media?: 'movie'|'tv' }>({});

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
            setKind(m.type === 'movie' ? 'movie' : (m.type === 'show' ? 'tv' : undefined));
            setMeta({
              genres: (m.Genre || []).map((g: any) => g.tag),
              runtime: Math.round((m.duration || 0) / 60000),
              rating: m.contentRating || m.rating,
            });
            if (m.year) setYear(String(m.year));
            try { setMoodTags(deriveTags((m.Genre||[]).map((g:any)=>g.tag))); } catch {}
            setCast((m.Role || []).slice(0, 12).map((r: any) => ({ name: r.tag, img: apiClient.getPlexImageNoToken(r.thumb || '') })));
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
                const auds: Track[] = streams.filter((st:any)=>st.streamType===2).map((st:any, i:number)=>({ id: String(st.id || i), label: (st.displayTitle || st.languageTag || st.language || `Audio ${i+1}`) }));
                const subs: Track[] = streams.filter((st:any)=>st.streamType===3).map((st:any, i:number)=>({ id: String(st.id || i), label: (st.displayTitle || st.languageTag || st.language || `Sub ${i+1}`) }));
                const w = mm.width || 0; const h = mm.height || 0;
                const techInfo = {
                  rating: meta.rating,
                  runtimeMin: Math.round((m.duration||0)/60000),
                  videoCodec: mm.videoCodec, videoProfile: mm.videoProfile,
                  resolution: w&&h? `${w}x${h}`: undefined,
                  bitrateKbps: mm.bitrate ? mm.bitrate * 1000 : undefined,
                  audioCodec: mm.audioCodec, audioChannels: mm.audioChannels,
                  fileSizeMB: mm.Part?.[0]?.size ? mm.Part[0].size / (1024*1024) : undefined,
                  subsCount: subs.length,
                };
                const label = `${(mm.width||0)>=3800?'4K':'HD'} ${String(mm.videoCodec||'').toUpperCase()} ${mm.audioChannels||''}`;
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
              setKind(mediaType);
              // Also fetch external IDs to get IMDb id when available
              try {
                const exIds: any = await tmdbExternalIds(s.tmdbBearer!, mediaType as any, tid);
                if (exIds?.imdb_id) setImdbId(exIds.imdb_id);
              } catch {}
              setTmdbCtx({ media: mediaType as any, id: String(tid) });
                try {
                  const d: any = await tmdbDetails(s.tmdbBearer!, mediaType as any, tid);
                  setTitle(d.title || d.name || title);
                  setOverview(d.overview || overview);
                  setPoster(tmdbImage(d.poster_path, 'w500') || poster);
                  setMeta({ genres: (d.genres||[]).map((x:any)=>x.name), runtime: Math.round((d.runtime||d.episode_run_time?.[0]||0)), rating: m.contentRating || m.rating });
                  const y2 = (d.release_date || d.first_air_date || '').slice(0,4); if (y2) setYear(y2);
                  try { setMoodTags(deriveTags((d.genres||[]).map((g:any)=>g.name))); } catch {}
                  // Try fetch a logo image
                  try {
                    const imgs: any = await tmdbImages(s.tmdbBearer!, mediaType as any, tid, 'en,null');
                    const logo = (imgs?.logos||[]).find((l:any)=>l.iso_639_1==='en') || (imgs?.logos||[])[0];
                    if (logo?.file_path) setLogoUrl(tmdbImage(logo.file_path, 'w500') || tmdbImage(logo.file_path, 'original'));
                  } catch {}
                  try {
                    const cr: any = await tmdbCredits(s.tmdbBearer!, mediaType as any, tid);
                    setCast((cr.cast||[]).slice(0,12).map((c:any)=>({ id:String(c.id), name:c.name, img: tmdbImage(c.profile_path,'w500') })));
                  } catch {}
                  try {
                  const vids:any = await tmdbVideos(s.tmdbBearer!, mediaType as any, tid);
                  const yt = (vids.results||[]).find((v:any)=>v.site==='YouTube'&&(v.type==='Trailer'||v.type==='Teaser'));
                  if (yt) setTimeout(()=>{ setTrailerKey(yt.key); setShowTrailer(true); }, 2000);
                } catch {}
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
                setTimeout(()=> setShowTrailer(true), 2000);
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
            try {
              const cr: any = await tmdbCredits(s.tmdbBearer!, media as any, tmdbId);
              setCast((cr.cast || []).slice(0, 12).map((c: any) => ({ id: String(c.id), name: c.name, img: tmdbImage(c.profile_path, 'w500') })));
            } catch {}
            try {
              const vids: any = await tmdbVideos(s.tmdbBearer!, media as any, tmdbId);
              const yt = (vids.results || []).find((v: any) => v.site === 'YouTube' && (v.type === 'Trailer' || v.type === 'Teaser'));
              if (yt) setTimeout(() => { setTrailerKey(yt.key); setShowTrailer(true); }, 2000);
            } catch {}
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
            if (media === 'tv') {
              try {
                const tv: any = await tmdbTvSeasons(s.tmdbBearer!, tmdbId);
                const ss = (tv.seasons||[]).filter((x:any)=>x.season_number>0).map((x:any)=>({ key: String(x.season_number), title: `Season ${x.season_number}` }));
                if (ss.length) {
                  setSeasons(ss);
                  setSeasonKey(String(ss[0].key));
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
                      const auds: Track[] = streams.filter((st:any)=>st.streamType===2).map((st:any, i:number)=>({ id: String(st.id || i), label: (st.displayTitle || st.languageTag || st.language || `Audio ${i+1}`) }));
                      const subs: Track[] = streams.filter((st:any)=>st.streamType===3).map((st:any, i:number)=>({ id: String(st.id || i), label: (st.displayTitle || st.languageTag || st.language || `Sub ${i+1}`) }));
                      const w = mm.width || 0; const h = mm.height || 0;
                      const techInfo = {
                        rating: m.contentRating || m.rating,
                        runtimeMin: Math.round((m.duration||0)/60000),
                        videoCodec: mm.videoCodec, videoProfile: mm.videoProfile,
                        resolution: w&&h? `${w}x${h}`: undefined,
                        bitrateKbps: mm.bitrate ? mm.bitrate * 1000 : undefined,
                        audioCodec: mm.audioCodec, audioChannels: mm.audioChannels,
                        fileSizeMB: mm.Part?.[0]?.size ? mm.Part[0].size / (1024*1024) : undefined,
                        subsCount: subs.length,
                      };
                      const label = `${(mm.width||0)>=3800?'4K':'HD'} ${String(mm.videoCodec||'').toUpperCase()} ${mm.audioChannels||''}`;
                      return { id: String(mm.id||mm.Id), label, audios: auds, subs, tech: techInfo };
                    });
                    setVersionDetails(vds);
                    setInfoVersion(vds[0]?.id);
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
                  // Prefer cast from Plex if available for better thumbs
                  if (match.Role && match.Role.length) setCast(match.Role.slice(0,12).map((r: any) => ({ name: r.tag, img: apiClient.getPlexImageNoToken(r.thumb || '') })));
                  // Trailer from Plex Extras for matched item
                  try {
                    const ex: any = await plexBackendMetadataWithExtras(String(m.ratingKey));
                    const em = ex?.MediaContainer?.Metadata?.[0]?.Extras?.Metadata?.[0];
                    const pkey = em?.Media?.[0]?.Part?.[0]?.key as string | undefined;
                    if (pkey) {
                      setPlexTrailerUrl(plexPartUrl(s.plexBaseUrl!, s.plexToken!, pkey));
                      setTimeout(()=> setShowTrailer(true), 2000);
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

  // Load episodes when a season is picked (Plex)
  useEffect(() => {
    const s = loadSettings();
    async function loadEps() {
      if (!seasonKey) return;
      try {
        setEpisodesLoading(true);
        // Prefer Plex episodes if plex seasonKey is numeric (ratingKey), otherwise use TMDB fallback
        if (/^\d+$/.test(seasonKey)) {
          const ch: any = await plexBackendDir(`/library/metadata/${seasonKey}/children?nocache=${Date.now()}`);
          const eps = (ch?.MediaContainer?.Metadata||[]).map((e:any)=>({
            id: `plex:${e.ratingKey}`,
            title: e.title,
            overview: e.summary,
            image: apiClient.getPlexImageNoToken((e.thumb || e.parentThumb) || ''),
            duration: Math.round((e.duration||0)/60000),
            progress: (() => {
              const dur = (e.duration||0)/1000; const vo = (e.viewOffset||0)/1000; const vc = e.viewCount||0;
              if (vc > 0) return 100;
              if (dur > 0 && vo/dur >= 0.95) return 100;
              if (dur > 0) return Math.round((vo/dur)*100);
              return 0;
            })(),
          }));
          setEpisodes(eps);
        } else if (tmdbCtx?.media==='tv' && tmdbCtx?.id) {
          const tvSeason = Number(seasonKey);
          const data: any = await tmdbTvSeasonEpisodes(s.tmdbBearer!, tmdbCtx.id, tvSeason);
          const eps = (data.episodes||[]).map((e:any)=>({
            id: `tmdb:tv:${tmdbCtx.id}:s${tvSeason}e${e.episode_number}`,
            title: e.name,
            overview: e.overview,
            image: tmdbImage(e.still_path,'w780'),
            duration: Math.round((e.runtime||0)),
            progress: 0,
          }));
          setEpisodes(eps);
        }
      } catch (e) { console.error(e); setEpisodes([]); }
      finally { setEpisodesLoading(false); }
    }
    loadEps();
  }, [seasonKey]);

  // Refresh episodes and onDeck when returning to the tab (progress updates)
  useEffect(() => {
    const onVis = async () => {
      if (document.visibilityState !== 'visible') return;
      try {
        if (activeTab === 'EPISODES' && seasonKey) {
          setEpisodesLoading(true);
          const ch: any = await plexBackendDir(`/library/metadata/${seasonKey}/children?nocache=${Date.now()}`);
          const eps = (ch?.MediaContainer?.Metadata||[]).map((e:any)=>({
            id: `plex:${e.ratingKey}`,
            title: e.title,
            overview: e.summary,
            image: apiClient.getPlexImageNoToken((e.thumb || e.parentThumb) || ''),
            duration: Math.round((e.duration||0)/60000),
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
  }, [activeTab, seasonKey, kind, showKey]);

  const tabsData = seasons.length > 0
    ? [
        { id: 'EPISODES', label: 'Episodes', count: episodes.length || undefined },
        { id: 'SUGGESTED', label: 'Suggested' },
        { id: 'EXTRAS', label: 'Extras' },
        { id: 'DETAILS', label: 'Details' }
      ]
    : [
        { id: 'SUGGESTED', label: 'Suggested' },
        { id: 'EXTRAS', label: 'Extras' },
        { id: 'DETAILS', label: 'Details' }
      ];
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
    // Otherwise go through in-app player for the item (movie or fallback)
    const targetId = (plexMappedId || id)!;
    const ver = activeVersion ? `?v=${encodeURIComponent(activeVersion)}` : '';
    nav(`/player/${encodeURIComponent(targetId)}${ver}`);
    } catch (e) { console.error(e); }
  };

  return (
    <div className="min-h-screen bg-home-gradient">
      {toast && <Toast message={toast} onClose={() => setToast('')} />}

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
        moodTags={moodTags}
        kind={kind}
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
          if (kind !== 'tv') return undefined;
          const cont = onDeck?.id || (episodes.find(e => (e.progress||0) > 0)?.id) || (episodes.find(e => (e.progress||0) < 100)?.id);
          return cont ? (() => nav(`/player/${encodeURIComponent(cont)}`)) : undefined;
        })()}
        continueLabel={kind==='tv' ? 'Continue Watching' : undefined}
        watchlistProps={{
          itemId: id!,
          itemType: (kind==='tv'?'show':'movie') as any,
          tmdbId: tmdbCtx?.id || watchIds.tmdbId,
        }}
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

      {/* Tabs Navigation */}
      <DetailsTabs
        tabs={tabsData}
        activeTab={activeTab}
        onTabChange={setActiveTab}
      />
      {/* Content Section Below Hero */}
      <div className="page-gutter-left py-8">
        {/* Season Selector */}
        {activeTab === 'EPISODES' && seasons.length > 0 && (
          <div className="mb-6">
            <select
              className="px-4 py-2 bg-white/10 text-white rounded-lg backdrop-blur-sm border border-white/20 hover:bg-white/20 transition-colors"
              value={seasonKey}
              onChange={(e) => setSeasonKey(e.target.value)}
            >
              {seasons.map(s => (
                <option key={s.key} value={s.key} className="bg-black">
                  {s.title}
                </option>
              ))}
            </select>
          </div>
        )}

        {/* Tab Content */}
        {activeTab === 'EPISODES' && seasons.length > 0 && (
          <section className="space-y-4">
            {episodesLoading ? (
              <EpisodeSkeletonList />
            ) : episodes.length ? (
              episodes.map((e: any, idx: number) => (
                <EpisodeItem
                  key={e.id || idx}
                  ep={{ ...e, index: idx + 1 }}
                  onClick={(eid) => nav(`/player/${encodeURIComponent(eid)}`)}
                />
              ))
            ) : (
              <div className="text-white/60 text-center py-10">{badges.includes('No local source') ? 'No source found' : 'No episodes found'}</div>
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

        {activeTab === 'EXTRAS' && (
          <section className="text-white/50 text-center py-12">
            <p>No extras available</p>
          </section>
        )}

        {activeTab === 'DETAILS' && (
          <section className="space-y-8">
            {/* Technical Details */}
            <div>
              <h3 className="text-lg font-semibold text-white mb-4">Technical Details</h3>
              <TechnicalChips
                info={{
                  rating: meta.rating,
                  runtimeMin: meta.runtime,
                  videoCodec: tech.videoCodec,
                  videoProfile: tech.videoProfile,
                  resolution: tech.resolution,
                  bitrateKbps: tech.bitrateKbps,
                  audioCodec: tech.audioCodec,
                  audioChannels: tech.audioChannels,
                  fileSizeMB: tech.fileSizeMB,
                  subsCount: tech.subsCount,
                }}
              />
            </div>

            {/* Full Cast */}
            {cast.length > 0 && (
              <div>
                <h3 className="text-lg font-semibold text-white mb-4">Cast & Crew</h3>
                <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
                  {cast.map((c, i) => (
                    <button
                      key={i}
                      onClick={() => {
                        setPersonId(c.id);
                        setPersonName(c.name);
                        setPersonOpen(true);
                      }}
                      className="text-center hover:opacity-80 transition-opacity"
                    >
                      <div className="aspect-square rounded-lg overflow-hidden bg-white/10 mb-2">
                        {c.img ? (
                          <SmartImage url={c.img} alt={c.name} width={120} className="w-full h-full" imgClassName="object-cover" />
                        ) : (
                          <div className="w-full h-full flex items-center justify-center text-white/20">
                            <svg className="w-12 h-12" fill="currentColor" viewBox="0 0 24 24">
                              <path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z" />
                            </svg>
                          </div>
                        )}
                      </div>
                      <p className="text-sm text-white/80">{c.name}</p>
                    </button>
                  ))}
                </div>
              </div>
            )}
          </section>
        )}
      </div>
      <PersonModal open={personOpen} onClose={()=> setPersonOpen(false)} personId={personId} name={personName} tmdbKey={loadSettings().tmdbBearer} />
      <BrowseModal />
    </div>
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
