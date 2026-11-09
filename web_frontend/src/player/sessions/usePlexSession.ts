import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { apiClient } from '@/services/api';
import {
  PlexConfig,
  plexKillAllTranscodeSessions,
  plexPartUrl,
  plexPlayQueue,
  plexStreamUrl,
  plexTimelineUpdate,
  plexTranscodeImageUrl,
  plexUniversalDecision,
  plexUpdateAudioStream,
  plexUpdateSubtitleStream,
  resetPlexSessionId,
} from '@/services/plex';
import { plexBackendDir, plexBackendMetadata } from '@/services/plex_backend';
import { backendUpdateProgress } from '@/services/plex_backend_player';
import {
  canDirectPlay,
  getAudioOptions,
  getExternalSubtitleUrl,
  getQualityOptions,
  getStreamDecision,
  getSubtitleOptions,
  hasDolbyVision,
} from '@/services/plex_decision';
import { tmdbDetails } from '@/services/tmdb';
import { traktScrobbler } from '@/services/traktScrobble';
import { getSettings } from '@/state/settings';
import { useCommunitySegments } from '../hooks/useCommunitySegments';
import { useEpisodeBrowserState } from '../hooks/useEpisodeBrowserState';
import { episodeLabel, withDeadline } from '../format';
import { mergeMarkers } from '../markers';
import { detailsPath } from '../playerId';
import { isClientRenderable, pickAudioTrack, pickSubtitleTrack, saveTrackPreference } from '../tracks/trackPreferences';
import type { SkipSegmentRequest } from '@/services/skipSegments';
import type {
  EpisodeEntry,
  PlayerChapter,
  PlayerClock,
  PlayerMarker,
  PlayerSession,
  SessionError,
  SubtitleOption,
  TrackOption,
} from '../types';

type Quality = string | number;
type Decision = 'directplay' | 'copy' | 'transcode';

interface Options {
  plexConfig: PlexConfig;
  itemId: string;
  clock: PlayerClock;
  onPlayItem: (ratingKey: string) => void;
  onNavigate: (path: string) => void;
  onBack: () => void;
}

interface TrackSelection {
  quality: Quality;
  audio?: string;
  subtitle?: string;
  forceTranscode?: boolean;
}

function savedQuality(): Quality {
  const saved = localStorage.getItem('player_quality');
  if (saved && saved !== 'original' && !isNaN(Number(saved))) return Number(saved);
  return saved || 'original';
}

function guidIds(meta: any): { imdbId?: string; tmdbId?: number } {
  const ids: { imdbId?: string; tmdbId?: number } = {};
  for (const guid of meta?.Guid ?? []) {
    const id = String(guid?.id ?? '');
    if (id.startsWith('imdb://')) ids.imdbId = id.slice(7);
    else if (id.startsWith('tmdb://')) ids.tmdbId = Number(id.slice(7)) || undefined;
  }
  return ids;
}

function toEntry(ep: any, currentKey: string): EpisodeEntry {
  return {
    key: String(ep.ratingKey),
    season: Number(ep.parentIndex ?? 0),
    episode: Number(ep.index ?? 0),
    title: ep.title ?? '',
    summary: ep.summary,
    thumb: ep.thumb ? apiClient.getPlexImageNoToken(ep.thumb) : undefined,
    progress: ep.viewOffset && ep.duration ? Math.min(1, ep.viewOffset / ep.duration) : undefined,
    isCurrent: String(ep.ratingKey) === currentKey,
  };
}

function dynamicRange(media: any, videoStream: any): string {
  const profile = media?.videoProfile?.toLowerCase() || '';
  const colorTrc = (media?.colorTrc || videoStream?.colorTrc || '').toLowerCase();
  const colorSpace = (media?.colorSpace || videoStream?.colorSpace || '').toLowerCase();
  if (profile.includes('dv') || profile.includes('dolby')) return 'Dolby Vision';
  if (colorTrc.includes('smpte2084') || colorTrc.includes('pq')) return colorSpace.includes('bt2020') ? 'HDR10' : 'HDR';
  if (colorTrc.includes('arib-std-b67') || colorTrc.includes('hlg')) return 'HLG';
  if (profile.includes('hdr10+')) return 'HDR10+';
  if (profile.includes('hdr')) return 'HDR10';
  return 'SDR';
}

export function usePlexSession({ plexConfig, itemId, clock, onPlayItem, onNavigate, onBack }: Options): PlayerSession {
  const [meta, setMeta] = useState<any>(null);
  const [src, setSrc] = useState('');
  const [startAt, setStartAt] = useState<number | undefined>(undefined);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<SessionError | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [quality, setQuality] = useState<Quality>(savedQuality);
  const [qualityOptions, setQualityOptions] = useState<any[]>([]);
  const [audioOptions, setAudioOptions] = useState<TrackOption[]>([]);
  const [selectedAudio, setSelectedAudio] = useState<string | null>(null);
  const [subtitles, setSubtitles] = useState<SubtitleOption[]>([]);
  const [burnedSubtitle, setBurnedSubtitle] = useState('0');
  const [initialSubtitleId, setInitialSubtitleId] = useState<string | null>(null);
  const [plexMarkers, setPlexMarkers] = useState<PlayerMarker[]>([]);
  const [chapters, setChapters] = useState<PlayerChapter[]>([]);
  const [queue, setQueue] = useState<any[]>([]);
  const [seasonEpisodes, setSeasonEpisodes] = useState<any[]>([]);
  const [showIds, setShowIds] = useState<{ imdbId?: string; tmdbId?: number } | null>(null);
  const [markerDuration, setMarkerDuration] = useState(0);

  const closed = useRef(false);
  const exited = useRef(false);
  const navigated = useRef(false);
  const retriedHeader = useRef(false);
  const retriedCodec = useRef(false);
  const isTranscoding = useRef(false);

  const selection = useRef({ quality, audio: selectedAudio, burned: burnedSubtitle });
  selection.current = { quality, audio: selectedAudio, burned: burnedSubtitle };
  const metaRef = useRef<any>(null);
  metaRef.current = meta;
  const srcRef = useRef(src);
  srcRef.current = src;

  const reportStopped = useCallback(async () => {
    const current = metaRef.current;
    const duration = clock.duration.current;
    if (!current || duration <= 0) return;
    const time = clock.time.current;
    try {
      await backendUpdateProgress(current.ratingKey, time * 1000, duration * 1000, 'stopped', isTranscoding.current);
    } catch {
      try { await plexTimelineUpdate(plexConfig, current.ratingKey, time * 1000, duration * 1000, 'stopped'); } catch {}
    }
  }, [clock, plexConfig]);

  const buildUrl = useCallback(async (item: any, chosen: TrackSelection) => {
    const hasDV = hasDolbyVision(item);
    const directRequested = chosen.quality === 'original' && !hasDV && !chosen.forceTranscode;
    const decision = getStreamDecision(item, {
      quality: chosen.quality,
      directPlay: directRequested,
      audioStreamId: chosen.audio,
      subtitleStreamId: chosen.subtitle,
    });
    const maxVideoBitrate = chosen.quality === 'original' ? undefined : Number(chosen.quality);
    const plexDecision = await plexUniversalDecision(plexConfig, itemId, {
      maxVideoBitrate,
      protocol: 'dash',
      autoAdjustQuality: false,
      directPlay: decision.directPlay,
      directStream: decision.directStream,
      audioStreamID: chosen.audio,
      subtitleStreamID: chosen.subtitle,
    });

    const part = item.Media?.[0]?.Part?.[0];
    const fileAudio = getAudioOptions(item).find((a: any) => a.default) ?? getAudioOptions(item)[0];
    // A direct file always plays its own default audio and cannot burn subtitles.
    const needsServer = (chosen.subtitle && chosen.subtitle !== '0') || (chosen.audio && chosen.audio !== String(fileAudio?.id));
    if (plexDecision.canDirectPlay && part?.key && !hasDV && !needsServer && !chosen.forceTranscode) {
      isTranscoding.current = false;
      return plexPartUrl(plexConfig.baseUrl, plexConfig.token, part.key);
    }
    isTranscoding.current = chosen.quality !== 'original' || Boolean(chosen.forceTranscode);
    return plexStreamUrl(plexConfig, itemId, {
      maxVideoBitrate,
      protocol: 'dash',
      autoAdjustQuality: false,
      directPlay: false,
      directStream: chosen.forceTranscode ? false : plexDecision.willDirectStream || false,
      audioStreamID: chosen.audio,
      subtitleStreamID: chosen.subtitle,
      forceReload: chosen.forceTranscode ? true : undefined,
    } as any);
  }, [itemId, plexConfig]);

  const restartStream = useCallback(async (changes: Partial<TrackSelection> & { persist?: () => Promise<unknown> }) => {
    const item = metaRef.current;
    if (!item) return;
    const position = clock.time.current;
    const chosen: TrackSelection = {
      quality: changes.quality ?? selection.current.quality,
      audio: changes.audio ?? selection.current.audio ?? undefined,
      subtitle: changes.subtitle ?? selection.current.burned,
      forceTranscode: changes.forceTranscode,
    };
    try {
      await reportStopped();
      await plexKillAllTranscodeSessions(plexConfig);
      resetPlexSessionId();
      await changes.persist?.();
      setSrc('');
      setLoading(true);
      await new Promise((resolve) => setTimeout(resolve, 300));
      const url = await buildUrl(item, chosen);
      if (closed.current) return;
      setStartAt(position);
      setSrc(url);
      setLoading(false);
    } catch (err) {
      console.error('Failed to restart Plex stream:', err);
      if (!closed.current) {
        setLoading(false);
        setError({ message: 'Could not change the stream settings.' });
      }
    }
  }, [buildUrl, clock, plexConfig, reportStopped]);

  // Load the item and start the first stream.
  useEffect(() => {
    let cancelled = false;
    closed.current = false;
    (async () => {
      try {
        const response = await plexBackendMetadata(itemId);
        const item = response.MediaContainer.Metadata[0];
        if (cancelled) return;
        if (!item?.Media?.[0]?.Part?.[0]) {
          setError({
            message: 'This title has no playable media. Open its details to choose an episode or version.',
            detailsPath: detailsPath(`plex:${itemId}`),
          });
          setLoading(false);
          return;
        }
        setMeta(item);

        const resume = item.viewOffset ? Math.max(0, Math.floor(item.viewOffset / 1000)) : undefined;
        const total = item.duration ? Math.floor(item.duration / 1000) : 0;
        // A fully watched title starts over.
        setStartAt(resume !== undefined && total > 0 && resume / total >= 0.95 ? 0 : resume);

        // Markers, chapters and external ids (backend session avoids token issues).
        let details = item;
        try {
          const extras: any = await plexBackendDir(`/library/metadata/${itemId}`, {
            includeMarkers: 1,
            includeChapters: 1,
            includeGuids: 1,
          });
          details = extras?.MediaContainer?.Metadata?.[0] ?? item;
        } catch {}
        if (cancelled) return;
        setPlexMarkers(
          (details.Marker ?? []).map((marker: any, index: number) => ({
            id: String(marker.id ?? `${marker.type}-${index}`),
            type: String(marker.type ?? '').toLowerCase(),
            start: (marker.startTimeOffset ?? 0) / 1000,
            end: (marker.endTimeOffset ?? 0) / 1000,
            final: marker.final,
          })),
        );
        setChapters(
          (details.Chapter ?? []).map((chapter: any, index: number) => ({
            id: String(chapter.id ?? index),
            title: chapter.tag || `Chapter ${chapter.index ?? index + 1}`,
            start: (chapter.startTimeOffset ?? 0) / 1000,
          })),
        );

        // Tracks.
        const itemKey = `plex:${item.ratingKey}`;
        const seriesKey = item.grandparentRatingKey ? `plex:${item.grandparentRatingKey}` : undefined;
        const qualities = getQualityOptions(item);
        const audio: TrackOption[] = getAudioOptions(item).map((option: any) => ({
          id: String(option.id),
          label: option.title,
          language: option.language,
          languageCode: option.languageTag || option.languageCode,
          default: Boolean(option.default || option.selected),
        }));
        const subtitleOptions: SubtitleOption[] = getSubtitleOptions(item)
          .filter((option: any) => String(option.id) !== '0')
          .map((option: any) => {
            const clientUrl = option.key && isClientRenderable(option.codec) ? getExternalSubtitleUrl(plexConfig, option.key) : null;
            return {
              id: String(option.id),
              label: option.title,
              language: option.language,
              languageCode: option.languageTag || option.languageCode,
              forced: option.forced,
              default: Boolean(option.selected),
              delivery: clientUrl ? 'client' : 'burn',
              url: clientUrl ?? undefined,
              format: option.codec,
            } as SubtitleOption;
          });
        setQualityOptions(qualities);
        setAudioOptions(audio);
        setSubtitles(subtitleOptions);

        const defaultAudio = audio.find((option) => option.default) ?? audio[0];
        let originalLanguage: string | null = null;
        if (getSettings().preferredAudioLanguage.trim().toLowerCase() === 'original') {
          const ids = guidIds(details);
          const showKey = item.type === 'episode' ? item.grandparentRatingKey : null;
          const sourceIds = showKey ? guidIds(await plexBackendDir(`/library/metadata/${showKey}`, { includeGuids: 1 }).then((r: any) => r?.MediaContainer?.Metadata?.[0]).catch(() => null)) : ids;
          if (sourceIds.tmdbId) {
            const found: any = await withDeadline(
              tmdbDetails('', item.type === 'movie' ? 'movie' : 'tv', sourceIds.tmdbId),
              4000,
              null,
            );
            originalLanguage = found?.original_language ?? null;
          }
        }
        if (cancelled) return;

        const pickedAudio = pickAudioTrack(audio, { itemKey, seriesKey, originalLanguage });
        const startingAudio = pickedAudio && pickedAudio.id !== defaultAudio?.id ? pickedAudio.id : undefined;
        setSelectedAudio(startingAudio ?? defaultAudio?.id ?? null);

        // Burning in forces a transcode, so that happens only for an explicit earlier
        // choice. A Plex-flagged default that needs burn-in stays off until picked.
        const rememberedSubtitle = pickSubtitleTrack(subtitleOptions, { itemKey, seriesKey, autoLanguage: false });
        const startingBurn = rememberedSubtitle && 'track' in rememberedSubtitle && rememberedSubtitle.track.delivery === 'burn'
          ? rememberedSubtitle.track.id
          : '0';
        setBurnedSubtitle(startingBurn);
        setInitialSubtitleId(startingBurn !== '0' ? startingBurn : null);

        // Dolby Vision cannot play direct in a browser.
        const hasDV = hasDolbyVision(item);
        let effectiveQuality: Quality = selection.current.quality;
        if (hasDV && effectiveQuality === 'original') {
          const transcoded = qualities.filter((option: any) => option.value !== 'original');
          effectiveQuality = transcoded[0]?.value || 20000;
          setQuality(effectiveQuality);
          localStorage.setItem('player_quality', String(effectiveQuality));
          setNotice('Dolby Vision detected - using transcoded quality for compatibility');
          setTimeout(() => setNotice(null), 5000);
        }

        const url = await buildUrl(item, { quality: effectiveQuality, audio: startingAudio, subtitle: startingBurn });
        if (cancelled) return;
        setSrc(url);
        setLoading(false);

        if (item.type === 'episode') {
          plexPlayQueue(plexConfig, itemId).then(
            (result: any) => { if (!cancelled) setQueue(result?.MediaContainer?.Metadata ?? []); },
            (err: unknown) => console.warn('Failed to load play queue:', err),
          );
          if (item.parentRatingKey) {
            plexBackendDir(`/library/metadata/${item.parentRatingKey}/children`).then((result: any) => {
              if (!cancelled) setSeasonEpisodes(result?.MediaContainer?.Metadata ?? []);
            });
          }
        }

        // Community segments need the show's ids, not the episode's.
        if (item.type === 'episode' && item.grandparentRatingKey) {
          plexBackendDir(`/library/metadata/${item.grandparentRatingKey}`, { includeGuids: 1 }).then((result: any) => {
            if (!cancelled) setShowIds(guidIds(result?.MediaContainer?.Metadata?.[0]));
          });
        } else {
          setShowIds(guidIds(details));
        }
      } catch (err) {
        console.error('Failed to load content:', err);
        if (!cancelled) {
          setError({ message: err instanceof Error ? err.message : 'Failed to load content' });
          setLoading(false);
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [itemId, plexConfig, buildUrl]);

  // Timeline updates.
  useEffect(() => {
    if (!meta) return;
    const interval = setInterval(() => {
      const duration = clock.duration.current;
      if (duration <= 0) return;
      const state = clock.buffering.current ? 'buffering' : clock.playing.current ? 'playing' : 'paused';
      backendUpdateProgress(meta.ratingKey, clock.time.current * 1000, duration * 1000, state as any, isTranscoding.current).catch(console.warn);
    }, 5000);
    return () => clearInterval(interval);
  }, [meta, clock]);

  // Report position and end the transcode when the player goes away.
  useEffect(() => {
    return () => {
      closed.current = true;
      if (exited.current) return;
      reportStopped();
      plexKillAllTranscodeSessions(plexConfig)
        .catch(() => {})
        // The next item must not reuse the session this stop request refers to.
        .finally(() => resetPlexSessionId());
    };
  }, [plexConfig, reportStopped]);

  // Community segments only fill in what Plex did not mark.
  const plexTypes = useMemo(() => new Set(plexMarkers.map((marker) => marker.type)), [plexMarkers]);
  const needsCommunity = Boolean(meta) && !(plexTypes.has('intro') && plexTypes.has('credits'));
  const segmentRequest: Omit<SkipSegmentRequest, 'animeSkipClientId'> | null = useMemo(() => {
    if (!needsCommunity || !showIds || !meta) return null;
    if (meta.type === 'episode') {
      return { imdbId: showIds.imdbId, tmdbId: showIds.tmdbId, isMovie: false, season: meta.parentIndex, episode: meta.index };
    }
    return showIds.imdbId ? { imdbId: showIds.imdbId, tmdbId: showIds.tmdbId, isMovie: true } : null;
  }, [needsCommunity, showIds, meta]);
  const community = useCommunitySegments(segmentRequest);
  const awaitsDuration = community.some((segment) => segment.end === null);
  useEffect(() => {
    if (!awaitsDuration || markerDuration > 0) return;
    const timer = setInterval(() => {
      if (clock.duration.current > 0) setMarkerDuration(clock.duration.current);
    }, 1000);
    return () => clearInterval(timer);
  }, [awaitsDuration, markerDuration, clock]);
  const markers = useMemo(() => mergeMarkers(plexMarkers, community, markerDuration), [plexMarkers, community, markerDuration]);

  const goToDetails = useCallback(async () => {
    const current = metaRef.current;
    if (exited.current) return;
    exited.current = true;
    await reportStopped();
    try { await plexKillAllTranscodeSessions(plexConfig); } catch {}
    resetPlexSessionId();
    if (!current) { onBack(); return; }
    const target = current.type === 'episode' && current.grandparentRatingKey ? current.grandparentRatingKey : current.ratingKey;
    onNavigate(detailsPath(`plex:${target}`));
  }, [onBack, onNavigate, plexConfig, reportStopped]);

  const exit = useCallback(() => {
    if (metaRef.current?.type === 'movie' || metaRef.current?.grandparentRatingKey) {
      goToDetails();
    } else {
      onBack();
    }
  }, [goToDetails, onBack]);

  const nextEpisode = useMemo(() => {
    if (queue[1]) return queue[1];
    if (meta?.type !== 'episode') return null;
    const index = seasonEpisodes.findIndex((ep) => String(ep.ratingKey) === String(meta.ratingKey));
    return index >= 0 ? seasonEpisodes[index + 1] ?? null : null;
  }, [queue, seasonEpisodes, meta]);

  const playItem = useCallback((ratingKey: string) => {
    if (navigated.current) return;
    navigated.current = true;
    onPlayItem(ratingKey);
  }, [onPlayItem]);

  const playNext = useCallback(() => {
    if (nextEpisode) playItem(String(nextEpisode.ratingKey));
  }, [nextEpisode, playItem]);

  const onEnded = useCallback(() => {
    if (metaRef.current?.type === 'movie') { goToDetails(); return; }
    if (nextEpisode && getSettings().autoPlayNext) { playItem(String(nextEpisode.ratingKey)); return; }
    goToDetails();
  }, [goToDetails, nextEpisode, playItem]);

  const onCodecError = useCallback(async (message: string) => {
    console.error('Codec error detected:', message);
    if (retriedCodec.current || !metaRef.current) {
      setError({ message });
      return;
    }
    retriedCodec.current = true;
    setNotice("This format can't play directly here. Switching to a transcoded stream...");
    const transcoded = qualityOptions.filter((option) => option.value !== 'original');
    const maxQuality: Quality = transcoded[0]?.value || 20000;
    setQuality(maxQuality);
    localStorage.setItem('player_quality', String(maxQuality));
    await restartStream({ quality: maxQuality, forceTranscode: true });
    setTimeout(() => setNotice(null), 5000);
  }, [qualityOptions, restartStream]);

  const onEngineError = useCallback(async (message: string) => {
    console.error('Player error:', message);
    if (exited.current || closed.current) return;
    const item = metaRef.current;
    const time = clock.time.current;
    const duration = clock.duration.current;
    // At the end of a movie, go to Details rather than retrying.
    if (item?.type === 'movie' && duration && (time / duration >= 0.95 || duration - time <= 30)) {
      goToDetails();
      return;
    }
    const lower = String(message || '').toLowerCase();
    // A stale PMS session: one clean retry, resuming where playback stopped.
    if (item && !retriedHeader.current && (lower.includes('header is not available') || (lower.includes('mpd') && lower.includes('header')))) {
      retriedHeader.current = true;
      await restartStream({ forceTranscode: true });
      return;
    }
    // A direct file the browser turned out not to support: let Plex transcode it.
    if (item && !retriedCodec.current && !srcRef.current.includes('/transcode/')) {
      await onCodecError(message);
      return;
    }
    setError({ message: message || 'Playback failed.' });
  }, [clock, goToDetails, onCodecError, restartStream]);

  const setQualityValue = useCallback((value: Quality) => {
    retriedCodec.current = false;
    setQuality(value);
    localStorage.setItem('player_quality', String(value));
    restartStream({ quality: value });
  }, [restartStream]);

  const selectAudio = useCallback((id: string) => {
    const item = metaRef.current;
    const partId = item?.Media?.[0]?.Part?.[0]?.id;
    if (!partId) return;
    const option = audioOptions.find((track) => track.id === id);
    if (option?.languageCode || option?.language) {
      const seriesKey = item.grandparentRatingKey ? `plex:${item.grandparentRatingKey}` : undefined;
      saveTrackPreference('audio', `plex:${item.ratingKey}`, seriesKey, option.languageCode || option.language || '');
    }
    setSelectedAudio(id);
    restartStream({ audio: id, persist: () => plexUpdateAudioStream(plexConfig, partId, id) });
  }, [audioOptions, plexConfig, restartStream]);

  const setBurned = useCallback((id: string) => {
    const partId = metaRef.current?.Media?.[0]?.Part?.[0]?.id;
    if (!partId || id === selection.current.burned) return;
    setBurnedSubtitle(id);
    restartStream({ subtitle: id, persist: () => plexUpdateSubtitleStream(plexConfig, partId, id) });
  }, [plexConfig, restartStream]);

  const currentKey = String(meta?.ratingKey ?? itemId);
  const currentEpisodes = useMemo(() => seasonEpisodes.map((ep) => toEntry(ep, currentKey)), [seasonEpisodes, currentKey]);

  const seasonKeys = useRef(new Map<number, string>());
  const browser = useEpisodeBrowserState({
    currentSeason: meta?.parentIndex ?? null,
    currentEpisodes,
    loadSeasons: async () => {
      const show = metaRef.current?.grandparentRatingKey;
      if (!show) return [];
      const result: any = await plexBackendDir(`/library/metadata/${show}/children`);
      const numbers: number[] = [];
      for (const season of result?.MediaContainer?.Metadata ?? []) {
        if (season.index === undefined) continue;
        seasonKeys.current.set(Number(season.index), String(season.ratingKey));
        numbers.push(Number(season.index));
      }
      return numbers.sort((a, b) => a - b);
    },
    loadEpisodes: async (season) => {
      const key = seasonKeys.current.get(season);
      if (!key) return [];
      const result: any = await plexBackendDir(`/library/metadata/${key}/children`);
      return (result?.MediaContainer?.Metadata ?? []).map((ep: any) => toEntry(ep, currentKey));
    },
    play: (entry) => playItem(entry.key),
  });

  const media = useMemo(() => {
    if (!meta) return null;
    return {
      kind: meta.type === 'episode' ? 'episode' : 'movie',
      title: meta.title ?? '',
      showTitle: meta.grandparentTitle,
      season: meta.parentIndex,
      episode: meta.index,
      poster: meta.thumb ? apiClient.getPlexImageNoToken(meta.thumb) : undefined,
      itemKey: `plex:${meta.ratingKey}`,
      seriesKey: meta.grandparentRatingKey ? `plex:${meta.grandparentRatingKey}` : undefined,
    } as PlayerSession['media'];
  }, [meta]);

  const quality_ = useMemo(() => {
    if (!meta) return null;
    const hasDV = hasDolbyVision(meta);
    const direct = canDirectPlay(meta);
    return {
      value: quality,
      set: setQualityValue,
      warning: hasDV ? 'Dolby Vision content. Direct play may not work, so a transcoded quality is safest.' : undefined,
      options: qualityOptions.map((option) => ({
        label: option.label,
        value: option.value,
        note: option.value === 'original'
          ? hasDV ? 'DV - may not play' : direct ? 'Direct Play' : 'Direct Stream/Original'
          : hasDV ? 'Compatible' : undefined,
        noteTone: (option.value === 'original' && hasDV ? 'warn' : option.value !== 'original' && hasDV ? 'good' : 'muted') as 'warn' | 'good' | 'muted',
      })),
    };
  }, [meta, quality, qualityOptions, setQualityValue]);

  const stats = useMemo(() => {
    const mediaInfo = meta?.Media?.[0];
    const streams = mediaInfo?.Part?.[0]?.Stream ?? [];
    const video = streams.find((s: any) => s.streamType === 1);
    const audio = streams.find((s: any) => s.streamType === 2 && s.selected);
    const transcodeUrl = src.includes('/transcode/');
    const isOriginal = quality === 'original';
    const audioCodec = mediaInfo?.audioCodec?.toLowerCase() || '';
    const videoDecision: Decision = !transcodeUrl ? 'directplay' : isOriginal ? 'copy' : 'transcode';
    const audioDecision: Decision = !transcodeUrl
      ? 'directplay'
      : isOriginal && !['dts', 'truehd', 'flac'].some((codec) => audioCodec.includes(codec)) ? 'copy' : 'transcode';
    return {
      videoCodec: mediaInfo?.videoCodec,
      videoProfile: mediaInfo?.videoProfile,
      resolution: mediaInfo?.width && mediaInfo?.height ? `${mediaInfo.width}x${mediaInfo.height}` : undefined,
      width: mediaInfo?.width,
      height: mediaInfo?.height,
      frameRate: mediaInfo?.videoFrameRate ? parseFloat(mediaInfo.videoFrameRate) : video?.frameRate,
      bitrate: mediaInfo?.bitrate,
      bitDepth: mediaInfo?.bitDepth || video?.bitDepth,
      colorSpace: mediaInfo?.colorSpace || video?.colorSpace,
      container: mediaInfo?.container,
      dynamicRange: dynamicRange(mediaInfo, video),
      audioCodec: mediaInfo?.audioCodec || audio?.codec,
      audioChannels: mediaInfo?.audioChannels || audio?.channels,
      audioSampleRate: audio?.samplingRate,
      isTranscoding: transcodeUrl && !isOriginal,
      videoDecision,
      audioDecision,
      audioBitrate: audio?.bitrate ? audio.bitrate * 1000 : undefined,
    };
  }, [meta, src, quality]);

  const previewUrl = useMemo(() => {
    const part = meta?.Media?.[0]?.Part?.[0];
    if (!part?.indexes) return undefined;
    return (ms: number) => plexTranscodeImageUrl(plexConfig, `/library/parts/${part.id}/indexes/sd/${Math.floor(ms)}`, 320, 180);
  }, [meta, plexConfig]);

  const scrobbleMedia = useMemo(() => (meta ? traktScrobbler.convertPlexToTraktMedia(meta) : null), [meta]);

  const next = useMemo(() => {
    if (!nextEpisode) return null;
    return {
      title: nextEpisode.title ?? '',
      label: episodeLabel(nextEpisode.parentIndex, nextEpisode.index),
      summary: nextEpisode.summary,
      thumb: nextEpisode.thumb ? apiClient.getPlexImageNoToken(nextEpisode.thumb) : undefined,
    };
  }, [nextEpisode]);

  return {
    kind: 'plex',
    media,
    src,
    crossOrigin: 'anonymous',
    startAt,
    loading,
    error,
    notice,
    status: null,
    markers,
    chapters,
    exitAtCredits: true,
    scrobbleMedia,
    quality: quality_,
    audio: { options: audioOptions, selected: selectedAudio, select: selectAudio },
    subtitles,
    initialSubtitleId,
    setBurnedSubtitle: setBurned,
    previewUrl,
    stats,
    next,
    playNext,
    browser: meta?.type === 'episode' ? browser : null,
    sourcesRequest: null,
    closeSources: () => {},
    onEngineError,
    onCodecError,
    onEnded,
    exit,
    goToDetails,
  };
}
