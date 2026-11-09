import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { tmdbExternalIds } from '@/services/tmdb';
import type { SkipSegmentRequest } from '@/services/skipSegments';
import { getSettings, useSettings } from '@/state/settings';
import {
  buildContentKey,
  classifyPlayability,
  clearResumeState,
  addonOrderSettled,
  findBestMatch,
  firstAddonWithPlayable,
  getCachedStream,
  getNextEpisode,
  getResumeState,
  getSubtitles,
  isSameAddonTier,
  NEXT_EPISODE_TIERS,
  prepareStreamForPlayback,
  rankedPlayable,
  recordLocalProgress,
  removeCachedStream,
  saveResumeState,
  streamProxyBase,
  type StreamEpisodeInfo,
  type StreamPlayerState,
  type StremioAddonStreams,
  type StremioContentIdentity,
  type StremioStream,
  type StremioSubtitle,
} from '@/stremio';
import { useCommunitySegments } from '../hooks/useCommunitySegments';
import { useEpisodeBrowserState } from '../hooks/useEpisodeBrowserState';
import { episodeLabel, withDeadline } from '../format';
import { mergeMarkers } from '../markers';
import { detectStreamKind, streamKindFromName } from '../streamKind';
import { pickAudioTrack, saveTrackPreference } from '../tracks/trackPreferences';
import { cinemetaMeta, StreamEpisode, streamSeasonEpisodes, streamSeasonNumbers } from './streamEpisodes';
import { lookupStreams } from './streamLookup';
import { checkServerConversion, conversionUrl, fetchConversionState, probeStream } from '../engine/api';
import { browserCaps, prefersHlsDelivery } from '../engine/capabilities';
import { decidePlayback, type AudioTrackInfo, type Decision, type MediaInfo } from '../engine/decide';
import { parseSubtitles, type SubtitleCue } from '../subtitles/parser';
import { streamAddonsFor } from '@/stremio/streams';
import type {
  EpisodeEntry,
  NextEpisode,
  PlayerClock,
  PlayerSession,
  SessionError,
  SourcesRequest,
  StreamKind,
  SubtitleOption,
  TraktMediaInfo,
  TrackOption,
} from '../types';

const MAX_RECOVERY_ATTEMPTS = 2;
const RECOVERY_LOOKUP_LIMIT_MS = 30_000;
const NEXT_EPISODE_LOOKUP_LIMIT_MS = 15_000;
const NEXT_EPISODE_SUBTITLE_WAIT_MS = 2_000;
const PROBE_LIMIT_MS = 25_000;
const CONVERSION_POLL_MS = 1_000;

/** How the engine plays the current source (player/engine). */
interface EngineState {
  /** Backend proxy address for the source: `.../stremio/stream/<token>`. */
  base: string;
  info: MediaInfo;
  decision: Exclude<Decision, { path: 'unsupported' }>;
  /** Seconds of real time at the start of the current conversion (0 for direct play). */
  offset: number;
  /** URL for direct play. */
  directUrl: string;
  audioIndex: number | null;
  subtitleIndex: number | null;
  /** Image subtitle drawn into the picture (conversion only). */
  burnIndex: number | null;
  avoidDirect: boolean;
  avoidRemux: boolean;
}

interface EngineOptions {
  base?: string;
  info?: MediaInfo;
  audioIndex?: number | null;
  subtitleIndex?: number | null;
  burnIndex?: number | null;
  avoidDirect?: boolean;
  avoidRemux?: boolean;
}

type EngineResult = 'handled' | 'direct' | 'none';

function audioLabel(track: AudioTrackInfo): string {
  const language = track.language && track.language !== 'und' ? track.language.toUpperCase() : 'Unknown';
  const layout = track.channels >= 8 ? '7.1' : track.channels >= 6 ? '5.1' : track.channels === 1 ? 'Mono' : 'Stereo';
  const name = track.title ? ` • ${track.title}` : '';
  return `${language}${name} • ${track.codec.toUpperCase()} ${layout}`;
}

type Outcome =
  | { kind: 'playable'; state: StreamPlayerState }
  | { kind: 'picker'; identity: StremioContentIdentity; title: string }
  | { kind: 'unavailable'; message: string };

interface Options {
  identity: StremioContentIdentity;
  initialState: StreamPlayerState | null;
  clock: PlayerClock;
  onPlayStream: (state: StreamPlayerState) => void;
  onBack: () => void;
}

function episodeIdentity(identity: StremioContentIdentity, season: number, episode: number): StremioContentIdentity {
  return { ...identity, requestId: `${identity.baseId}:${season}:${episode}`, seasonNumber: season, episodeNumber: episode };
}

function subtitleOption(subtitle: StremioSubtitle): SubtitleOption {
  const language = subtitle.lang.toUpperCase();
  return {
    id: subtitle.url,
    label: subtitle.addonName ? `${language} • ${subtitle.addonName}` : language,
    language: subtitle.lang,
    languageCode: subtitle.lang,
    delivery: 'client',
    url: subtitle.url,
    format: subtitle.format,
    addonName: subtitle.addonName,
    addonSubtitle: subtitle,
  };
}

/** Groups known streams by addon, keeping addon order. */
function groupByAddon(streams: StremioStream[]): StremioAddonStreams[] {
  const groups = new Map<string, StremioAddonStreams>();
  for (const stream of streams) {
    let group = groups.get(stream.installationId);
    if (!group) {
      group = { installationId: stream.installationId, addonId: stream.addonId, addonName: stream.addonName, streams: [] };
      groups.set(stream.installationId, group);
    }
    group.streams.push(stream);
  }
  return [...groups.values()];
}

function mergeSubtitles(a: StremioSubtitle[] = [], b: StremioSubtitle[] = []): StremioSubtitle[] {
  const seen = new Set<string>();
  return [...a, ...b].filter((subtitle) => {
    if (seen.has(subtitle.url)) return false;
    seen.add(subtitle.url);
    return true;
  });
}

export function useStreamSession({ identity, initialState, clock, onPlayStream, onBack }: Options): PlayerSession {
  const { stremioSubtitleAddonsEnabled } = useSettings();
  const [stream, setStream] = useState<StremioStream | null>(initialState?.stream ?? null);
  const [title, setTitle] = useState(initialState?.title ?? '');
  const [src, setSrc] = useState('');
  const [streamKind, setStreamKind] = useState<StreamKind>('direct');
  const [startAt, setStartAt] = useState<number | undefined>(undefined);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<SessionError | null>(null);
  const [status, setStatus] = useState<PlayerSession['status']>(null);
  const [addonSubtitles, setAddonSubtitles] = useState<StremioSubtitle[]>([]);
  const [sourcesRequest, setSourcesRequest] = useState<SourcesRequest | null>(null);
  const [seasonEpisodes, setSeasonEpisodes] = useState<StreamEpisode[]>([]);
  const [nextEpisode, setNextEpisode] = useState<StreamEpisodeInfo | null>(null);
  const [hlsAudio, setHlsAudio] = useState<TrackOption[]>([]);
  const [hlsAudioSelected, setHlsAudioSelected] = useState<string | null>(null);
  const [imdbId, setImdbId] = useState(identity.imdbId);
  const [markerDuration, setMarkerDuration] = useState(0);
  const [engine, setEngineState] = useState<EngineState | null>(null);
  const [embeddedCues, setEmbeddedCues] = useState<SubtitleCue[]>([]);
  const engineRef = useRef<EngineState | null>(null);
  const setEngine = useCallback((next: EngineState | null) => {
    engineRef.current = next;
    setEngineState(next);
  }, []);
  // Identifies this player to the backend, which runs one conversion per player.
  const playerId = useRef(`p${Math.random().toString(36).slice(2, 12)}`);

  const isEpisode = identity.requestType === 'series' && identity.seasonNumber !== undefined;
  const closed = useRef(false);
  const streamRef = useRef(stream);
  streamRef.current = stream;
  const titleRef = useRef(title);
  titleRef.current = title;
  const episodeTitleRef = useRef<string | undefined>(undefined);
  const loadToken = useRef(0);
  const startAtRef = useRef(0);

  // Recovery.
  const recovering = useRef(false);
  const attempts = useRef(0);
  const failedUrls = useRef(new Set<string>());
  const recoveryResults = useRef<StremioAddonStreams[] | null>(null);
  const knownStreams = useRef<StremioStream[]>(initialState?.alternatives ?? []);
  const audioApplied = useRef(false);

  // Next episode.
  const resolvingNext = useRef(false);
  const nextWaitToken = useRef(0);
  const sourceTask = useRef<{ key: string; promise: Promise<Outcome> } | null>(null);
  const resumeOnSourcesClose = useRef(false);

  const onPrepareFailed = useRef<() => void>(() => {});

  /**
   * Probes the source and plays it the way the engine decides. 'direct' leaves direct
   * play to the caller; 'none' means no engine (no FFmpeg on the server, or no probe).
   */
  const playWithEngine = useCallback(async (
    token: number,
    prepared: StremioStream,
    directUrl: string,
    at: number,
    options: EngineOptions,
  ): Promise<EngineResult> => {
    if (!(await checkServerConversion())) return 'none';
    let { base, info } = options;
    try {
      base ??= await streamProxyBase(prepared, identity);
      info ??= (await withDeadline(probeStream(base), PROBE_LIMIT_MS, null)) ?? undefined;
    } catch {
      return 'none';
    }
    if (token !== loadToken.current || closed.current) return 'handled';
    if (!base || !info) return 'none';

    let audioIndex = options.audioIndex;
    if (audioIndex === undefined && info.audio.length > 1) {
      const tracks: TrackOption[] = info.audio.map((track) => ({
        id: String(track.index), label: audioLabel(track), language: track.language, languageCode: track.language, default: track.isDefault,
      }));
      const preferred = pickAudioTrack(tracks, { itemKey: `stream:${identity.requestId}`, seriesKey: isEpisode ? `stream:${identity.baseId}` : undefined });
      if (preferred) audioIndex = Number(preferred.id);
    }
    const subtitleIndex = options.subtitleIndex ?? null;
    const burnIndex = options.burnIndex ?? null;
    const decision = decidePlayback(info, browserCaps(), {
      audioIndex,
      embeddedSubtitle: subtitleIndex !== null,
      burnSubtitle: burnIndex !== null,
      avoidDirect: options.avoidDirect,
      avoidRemux: options.avoidRemux,
    });
    if (decision.path === 'unsupported') {
      setEngine(null);
      setSrc('');
      setStatus(null);
      setLoading(false);
      setError({ message: decision.reason, canChooseSource: true });
      return 'handled';
    }

    const state: EngineState = {
      base, info, decision, offset: 0, directUrl,
      audioIndex: decision.audioIndex,
      subtitleIndex,
      burnIndex,
      avoidDirect: Boolean(options.avoidDirect),
      avoidRemux: Boolean(options.avoidRemux),
    };
    if (decision.path === 'direct') {
      setEngine(state);
      return 'direct';
    }
    // Until the backend reports the real start (a key frame for remux), assume `at`.
    const start = Math.max(0, at);
    setEngine({ ...state, offset: start });
    setEmbeddedCues([]);
    setStartAt(undefined);
    const hls = prefersHlsDelivery();
    setStreamKind(hls ? 'hls' : 'direct');
    // A changing nonce remounts the video element, even for a restart at the same place.
    setSrc(conversionUrl(base, { decision, start, player: playerId.current, subtitleIndex, burnIndex }, { hls, nonce: token }));
    setLoading(false);
    return 'handled';
  }, [identity, isEpisode, setEngine]);

  const loadStream = useCallback(async (next: StremioStream, at: number, engineOptions: EngineOptions = {}) => {
    const token = ++loadToken.current;
    const verdict = classifyPlayability(next);
    if (!verdict.playable || !next.url) {
      setSrc('');
      setStatus(null);
      setLoading(false);
      setError({ message: verdict.label || 'This source cannot play in a browser.', canChooseSource: true });
      return;
    }
    setError(null);
    setLoading(true);
    setSrc('');
    setHlsAudio([]);
    setEngine(null);
    setEmbeddedCues([]);
    audioApplied.current = false;
    startAtRef.current = at;

    // The sheet prepares what it hands over. Everything else is prepared here.
    let prepared: StremioStream;
    let url: string;
    try {
      prepared = next.playbackUrl ? next : await prepareStreamForPlayback(next, identity);
      url = prepared.playbackUrl ?? next.url;
    } catch {
      if (token === loadToken.current && !closed.current) onPrepareFailed.current();
      return;
    }
    if (token !== loadToken.current || closed.current) return;

    // Files go through the engine; adaptive streams (HLS, DASH) play as they are.
    const named = streamKindFromName(url) ?? streamKindFromName(next.behaviorHints?.filename ?? '');
    if (named !== 'hls' && named !== 'dash') {
      setStatus({ message: 'Preparing the video…' });
      const result = await playWithEngine(token, prepared, url, at, engineOptions);
      if (token !== loadToken.current || closed.current) return;
      setStatus(null);
      if (result === 'handled') return;
    }
    const kind = await detectStreamKind(url, next.behaviorHints?.filename);
    if (token !== loadToken.current || closed.current) return;
    setStartAt(at > 0 ? at : undefined);
    setStreamKind(kind);
    setSrc(url);
    setLoading(false);
  }, [identity, playWithEngine, setEngine]);

  /** Starts the current source again at `at` through the engine, e.g. after a seek. */
  const restartEngine = useCallback((at: number, changes: EngineOptions) => {
    const current = engineRef.current;
    const playing = streamRef.current;
    if (!current || !playing || closed.current) return;
    const token = ++loadToken.current;
    startAtRef.current = at;
    setError(null);
    setLoading(true);
    setSrc('');
    const options: EngineOptions = {
      base: current.base,
      info: current.info,
      audioIndex: current.audioIndex,
      subtitleIndex: current.subtitleIndex,
      burnIndex: current.burnIndex,
      avoidDirect: current.avoidDirect,
      avoidRemux: current.avoidRemux,
      ...changes,
    };
    playWithEngine(token, playing, current.directUrl, at, options).then((result) => {
      if (token !== loadToken.current || closed.current || result === 'handled') return;
      setEngine(result === 'direct' ? engineRef.current : null);
      setStartAt(at > 0 ? at : undefined);
      setStreamKind('direct');
      setSrc(current.directUrl);
      setLoading(false);
    });
  }, [playWithEngine, setEngine]);

  // First stream, from router state or by looking the title up.
  useEffect(() => {
    let cancelled = false;
    closed.current = false;
    const saved = getResumeState(buildContentKey(identity));
    const resume = saved && saved.positionMs / Math.max(1, saved.durationMs) < 0.95 ? saved.positionMs / 1000 : 0;
    (async () => {
      if (initialState?.stream) {
        loadStream(initialState.stream, resume);
        return;
      }
      setStatus({ message: 'Finding a source…' });
      const { results } = await lookupStreams(identity, { limitMs: RECOVERY_LOOKUP_LIMIT_MS });
      if (cancelled) return;
      const ranked = rankedPlayable(results);
      knownStreams.current = ranked;
      setStatus(null);
      if (ranked.length === 0) {
        setLoading(false);
        setError({ message: 'No source that plays in a browser was found for this title.', canChooseSource: true });
        return;
      }
      setStream(ranked[0]);
      loadStream(ranked[0], resume);
    })();
    return () => {
      cancelled = true;
    };
    // The identity is fixed for one mount: the route remounts per stream id.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Title when opened without router state.
  useEffect(() => {
    if (title || !identity.imdbId) return;
    cinemetaMeta(isEpisode ? 'series' : 'movie', identity.imdbId).then((meta) => {
      if (!closed.current && meta?.name) setTitle(meta.name);
    });
  }, [title, identity.imdbId, isEpisode]);

  // Addon subtitles.
  useEffect(() => {
    if (!stremioSubtitleAddonsEnabled) return;
    const controller = new AbortController();
    // Passing the stream lets addons return subtitles matched to this release.
    getSubtitles(identity, { signal: controller.signal, stream: stream ?? undefined }).then(
      (found) => { if (!controller.signal.aborted) setAddonSubtitles(found); },
      () => {},
    );
    return () => controller.abort();
  }, [identity, stream, stremioSubtitleAddonsEnabled]);

  // Episode list and next episode.
  useEffect(() => {
    if (!isEpisode) return;
    const controller = new AbortController();
    streamSeasonEpisodes(identity, identity.seasonNumber as number).then(
      (episodes) => { if (!controller.signal.aborted) setSeasonEpisodes(episodes); },
      () => {},
    );
    getNextEpisode(identity, { signal: controller.signal }).then(
      (next) => { if (!controller.signal.aborted) setNextEpisode(next); },
      () => {},
    );
    return () => controller.abort();
  }, [identity, isEpisode]);

  // Remember the position, for resume and for Continue Watching.
  useEffect(() => {
    const contentKey = buildContentKey(identity);
    const save = (force: boolean) => {
      const positionMs = clock.time.current * 1000;
      const durationMs = clock.duration.current * 1000;
      if (durationMs <= 0 || positionMs < 5000) return;
      if (positionMs / durationMs >= 0.95) clearResumeState(contentKey);
      else saveResumeState({ contentKey, positionMs, durationMs });
      if (!titleRef.current) return;
      recordLocalProgress(
        {
          contentKey,
          mediaType: identity.requestType === 'series' ? 'episode' : 'movie',
          title: titleRef.current,
          episodeTitle: episodeTitleRef.current,
          seasonNumber: identity.seasonNumber,
          episodeNumber: identity.episodeNumber,
          imdbId: identity.imdbId,
          tmdbId: identity.tmdbId,
        },
        positionMs,
        durationMs,
        { force },
      );
    };
    const interval = setInterval(() => save(false), 10_000);
    const onPageHide = () => save(true);
    window.addEventListener('pagehide', onPageHide);
    return () => {
      clearInterval(interval);
      window.removeEventListener('pagehide', onPageHide);
      closed.current = true;
      save(true);
    };
  }, [identity, clock]);

  // Skip segments.
  useEffect(() => {
    if (imdbId || !identity.tmdbId) return;
    tmdbExternalIds('', isEpisode ? 'tv' : 'movie', identity.tmdbId).then(
      (ids: any) => { if (!closed.current && ids?.imdb_id) setImdbId(ids.imdb_id); },
      () => {},
    );
  }, [imdbId, identity.tmdbId, isEpisode]);

  const segmentRequest: Omit<SkipSegmentRequest, 'animeSkipClientId'> | null = useMemo(() => {
    const kitsuId = identity.baseId.startsWith('kitsu:') ? identity.baseId.slice(6) : undefined;
    const malId = identity.baseId.startsWith('mal:') ? identity.baseId.slice(4) : undefined;
    if (isEpisode) {
      return { imdbId, tmdbId: identity.tmdbId, isMovie: false, season: identity.seasonNumber, episode: identity.episodeNumber, kitsuId, malId };
    }
    return imdbId ? { imdbId, tmdbId: identity.tmdbId, isMovie: true } : null;
  }, [identity, imdbId, isEpisode]);
  const community = useCommunitySegments(segmentRequest);
  const awaitsDuration = community.some((segment) => segment.end === null);
  useEffect(() => {
    if (!awaitsDuration || markerDuration > 0) return;
    const timer = setInterval(() => {
      if (clock.duration.current > 0) setMarkerDuration(clock.duration.current);
    }, 1000);
    return () => clearInterval(timer);
  }, [awaitsDuration, markerDuration, clock]);
  const markers = useMemo(() => mergeMarkers([], community, markerDuration), [community, markerDuration]);

  const failPlayback = useCallback((message: string) => {
    setSrc('');
    setStatus(null);
    setLoading(false);
    setError({ message, canChooseSource: true });
  }, []);

  /** Starts a replacement for a failed source. False means no attempt is possible. */
  const attemptRecovery = useCallback((early: boolean): boolean => {
    const failed = streamRef.current;
    if (!failed?.url || closed.current) return false;
    if (recovering.current) return true; // A second failure event for the same file.
    if (attempts.current >= MAX_RECOVERY_ATTEMPTS) return false;

    attempts.current += 1;
    failedUrls.current.add(failed.url);
    const resumeAt = clock.time.current > 1 ? clock.time.current : startAtRef.current;
    recovering.current = true;
    setError(null);
    setLoading(true);
    setSrc('');
    setStatus({ message: `Source stopped working. Finding a replacement (${attempts.current} of ${MAX_RECOVERY_ATTEMPTS})…` });

    if (getCachedStream(identity)?.stream.url === failed.url) removeCachedStream(identity);

    (async () => {
      if (!recoveryResults.current) {
        const { results } = await lookupStreams(identity, { limitMs: RECOVERY_LOOKUP_LIMIT_MS });
        recoveryResults.current = results;
      }
      if (closed.current || streamRef.current !== failed) {
        recovering.current = false;
        return;
      }
      const fresh = recoveryResults.current;
      const pool = rankedPlayable(fresh).length > 0 ? fresh : groupByAddon(knownStreams.current);
      const match = findBestMatch(failed, pool, { excludingUrls: failedUrls.current });
      if (!match) {
        recovering.current = false;
        failPlayback(early
          ? "This source couldn't be loaded and no working replacement was found. Choose another source."
          : 'The stream stopped and no working replacement was found. Choose another source.');
        return;
      }
      streamRef.current = match.stream;
      setStream(match.stream);
      // From here a failure belongs to the replacement, so it may start the next attempt.
      recovering.current = false;
      // The status clears in onReady, once the replacement has actually loaded.
      await loadStream(match.stream, resumeAt);
    })();
    return true;
  }, [clock, failPlayback, identity, loadStream]);

  const onEngineError = useCallback((message: string) => {
    console.error('Stream playback error');
    if (closed.current) return;
    // Before trying another source, play this one the next way down: direct, remux, convert.
    const current = engineRef.current;
    if (current) {
      const at = clock.time.current > 1 ? clock.time.current : startAtRef.current;
      if (current.decision.path === 'direct') {
        restartEngine(at, { avoidDirect: true });
        return;
      }
      if (current.decision.path === 'remux' && !current.avoidRemux) {
        restartEngine(at, { avoidDirect: true, avoidRemux: true });
        return;
      }
    }
    const early = clock.time.current < 1;
    if (!attemptRecovery(early)) {
      failPlayback(message.toLowerCase().includes('network')
        ? 'The source stopped responding. Choose another source.'
        : "This source can't be played in this browser. Choose another source.");
    }
  }, [attemptRecovery, clock, failPlayback, restartEngine]);

  onPrepareFailed.current = () => {
    if (!attemptRecovery(clock.time.current < 1)) {
      failPlayback('This source could not be prepared. Choose another source.');
    }
  };

  const onReady = useCallback(() => {
    setStatus((current) => (current && !current.onCancel ? null : current));
  }, []);

  /** A user-chosen source: resets the recovery budget and keeps the position. */
  const switchStream = useCallback((next: StremioStream) => {
    setSourcesRequest(null);
    if (next.sourceType === 'externalUrl' && next.externalUrl) {
      window.open(next.externalUrl, '_blank', 'noopener');
      return;
    }
    const position = clock.time.current > 1 ? clock.time.current : startAtRef.current;
    recovering.current = false;
    attempts.current = 0;
    failedUrls.current.clear();
    recoveryResults.current = null;
    streamRef.current = next;
    setStream(next);
    setStatus(null);
    loadStream(next, position);
  }, [clock, loadStream]);

  const openSources = useCallback(() => {
    setSourcesRequest({
      identity,
      title: titleRef.current || identity.requestId,
      onSelect: switchStream,
      currentUrl: streamRef.current?.url,
    });
  }, [identity, switchStream]);

  const closeSources = useCallback(() => {
    setSourcesRequest(null);
    if (resumeOnSourcesClose.current) {
      resumeOnSourcesClose.current = false;
      clock.resume.current();
    }
  }, [clock]);

  const resolveEpisodeSource = useCallback(async (season: number, episode: number): Promise<Outcome> => {
    const target = episodeIdentity(identity, season, episode);
    const reference = streamRef.current;
    const showTitle = titleRef.current;
    // Stop as soon as the addon in use returns a match, so a slow addon elsewhere
    // does not hold up the next episode.
    // With "Follow addon order", the highest-priority addon with this episode wins,
    // even when the current episode came from a lower one.
    const followAddonOrder = getSettings().stremioPlayAction === 'addonOrder';
    const order = streamAddonsFor(target).map((addon) => addon.installationId);
    const { results } = await lookupStreams(target, {
      limitMs: NEXT_EPISODE_LOOKUP_LIMIT_MS,
      stopWhen: (partial) =>
        followAddonOrder
          ? addonOrderSettled(order, partial, new Set(order.filter((id) => !partial.some((result) => result.installationId === id))))
          : isSameAddonTier(findBestMatch(reference ?? undefined, partial, { tiers: NEXT_EPISODE_TIERS })?.tier),
    });
    const match = findBestMatch(reference ?? undefined, followAddonOrder ? firstAddonWithPlayable(results) : results, {
      tiers: NEXT_EPISODE_TIERS,
      followAddonOrder: false,
    });
    if (!match) return { kind: 'picker', identity: target, title: showTitle };

    let prepared: StremioStream;
    try {
      prepared = await prepareStreamForPlayback(match.stream, target);
    } catch {
      return { kind: 'picker', identity: target, title: showTitle };
    }

    // The new player asks subtitle addons again, so a slow one must not delay the switch.
    const subtitles = getSettings().stremioSubtitleAddonsEnabled
      ? await withDeadline(getSubtitles(target), NEXT_EPISODE_SUBTITLE_WAIT_MS, [] as StremioSubtitle[])
      : [];
    return {
      kind: 'playable',
      state: {
        stream: { ...prepared, subtitles: mergeSubtitles(prepared.subtitles, subtitles) },
        identity: target,
        title: showTitle,
        alternatives: rankedPlayable(results),
      },
    };
  }, [identity]);

  /** One shared lookup per episode, reused by the prefetch and by play-next. */
  const episodeSourceTask = useCallback((season: number, episode: number) => {
    const key = `${season}:${episode}`;
    if (sourceTask.current?.key === key) return sourceTask.current.promise;
    const promise = resolveEpisodeSource(season, episode).catch((): Outcome => ({
      kind: 'unavailable',
      message: 'Could not look up a source for that episode.',
    }));
    sourceTask.current = { key, promise };
    return promise;
  }, [resolveEpisodeSource]);

  const cancelNextLookup = useCallback(() => {
    if (!resolvingNext.current) return;
    nextWaitToken.current += 1; // Stops waiting. The lookup continues, so Next can reuse it.
    resolvingNext.current = false;
    setStatus(null);
    setLoading(false);
    clock.resume.current();
  }, [clock]);

  const playEpisode = useCallback(async (season: number, episode: number) => {
    if (resolvingNext.current || closed.current) return;
    resolvingNext.current = true;
    const waitToken = ++nextWaitToken.current;
    setStatus({ message: `Finding a source for ${episodeLabel(season, episode)}…`, onCancel: cancelNextLookup });
    setLoading(true);
    clock.pause.current();

    const outcome = await episodeSourceTask(season, episode);
    if (waitToken !== nextWaitToken.current || closed.current) return;
    resolvingNext.current = false;
    setStatus(null);
    setLoading(false);

    switch (outcome.kind) {
      case 'playable':
        onPlayStream(outcome.state);
        break;
      case 'picker':
        resumeOnSourcesClose.current = true;
        setSourcesRequest({
          identity: outcome.identity,
          title: outcome.title,
          onSelect: (picked) => {
            resumeOnSourcesClose.current = false;
            setSourcesRequest(null);
            onPlayStream({ stream: picked, identity: outcome.identity, title: outcome.title });
          },
        });
        break;
      case 'unavailable':
        setError({ message: outcome.message });
        break;
    }
  }, [cancelNextLookup, clock, episodeSourceTask, onPlayStream]);

  const playNext = useCallback(() => {
    if (nextEpisode) playEpisode(nextEpisode.season, nextEpisode.episode);
  }, [nextEpisode, playEpisode]);

  const prefetchNext = useCallback(() => {
    if (nextEpisode) episodeSourceTask(nextEpisode.season, nextEpisode.episode);
  }, [nextEpisode, episodeSourceTask]);

  const onEnded = useCallback(() => {
    if (nextEpisode && getSettings().autoPlayNext) { playNext(); return; }
    onBack();
  }, [nextEpisode, onBack, playNext]);

  const toEntry = useCallback((episode: StreamEpisode): EpisodeEntry => ({
    key: `${episode.season}:${episode.episode}`,
    season: episode.season,
    episode: episode.episode,
    title: episode.title,
    summary: episode.overview,
    thumb: episode.still,
    isCurrent: episode.season === identity.seasonNumber && episode.episode === identity.episodeNumber,
  }), [identity]);

  const currentEpisodes = useMemo(() => seasonEpisodes.map(toEntry), [seasonEpisodes, toEntry]);
  const browser = useEpisodeBrowserState({
    currentSeason: identity.seasonNumber ?? null,
    currentEpisodes,
    loadSeasons: () => streamSeasonNumbers(identity),
    loadEpisodes: async (season) => (await streamSeasonEpisodes(identity, season)).map(toEntry),
    play: (entry) => playEpisode(entry.season, entry.episode),
  });

  const currentEpisode = seasonEpisodes.find((episode) => episode.episode === identity.episodeNumber);
  episodeTitleRef.current = currentEpisode?.title;
  const media = useMemo<PlayerSession['media']>(() => ({
    kind: isEpisode ? 'episode' : 'movie',
    title: isEpisode ? currentEpisode?.title ?? '' : title,
    showTitle: isEpisode ? title : undefined,
    season: identity.seasonNumber,
    episode: identity.episodeNumber,
    itemKey: `stream:${identity.requestId}`,
    seriesKey: isEpisode ? `stream:${identity.baseId}` : undefined,
  }), [isEpisode, currentEpisode, title, identity]);

  const subtitles = useMemo(() => {
    // Text tracks stream as cues; image tracks (PGS, VobSub) are drawn into a conversion.
    const embedded: SubtitleOption[] = (engine?.info.subtitles ?? []).map((track) => {
      const language = track.language && track.language !== 'und' ? track.language.toUpperCase() : 'Unknown';
      const kind = track.isText ? '' : ' • Image';
      return {
        id: track.isText ? `embedded:${track.index}` : `burn:${track.index}`,
        label: `${language} • In file${track.title ? ` • ${track.title}` : ''}${track.forced ? ' • Forced' : ''}${kind}`,
        language: track.language,
        languageCode: track.language,
        forced: track.forced,
        default: track.isDefault,
        delivery: track.isText ? 'embedded' : 'burn',
      };
    });
    return [...embedded, ...mergeSubtitles(stream?.subtitles, addonSubtitles).map(subtitleOption)];
  }, [stream, addonSubtitles, engine?.info]);

  /** Draws an embedded image subtitle into a conversion (`burn:<index>`), or stops ('0'). */
  const setBurnedSubtitle = useCallback((id: string) => {
    const current = engineRef.current;
    if (!current) return;
    const index = id.startsWith('burn:') ? Number(id.slice(5)) : null;
    if (index === current.burnIndex) return;
    restartEngine(clock.time.current, { burnIndex: index, subtitleIndex: index !== null ? null : current.subtitleIndex });
  }, [clock, restartEngine]);

  /** Shows an embedded subtitle by restarting the conversion with it, or hides it. */
  const setEmbeddedSubtitle = useCallback((id: string | null) => {
    const current = engineRef.current;
    if (!current) return;
    const index = id ? Number(id.replace('embedded:', '')) : null;
    if (index === current.subtitleIndex) return;
    if (index === null) {
      setEngine({ ...current, subtitleIndex: null });
      setEmbeddedCues([]);
      return;
    }
    // A text subtitle replaces a burned one.
    restartEngine(clock.time.current, { subtitleIndex: index, burnIndex: null });
  }, [clock, restartEngine, setEngine]);

  // While a conversion runs: learn where it really starts (the clock offset), and
  // collect embedded subtitle cues, which already use the film's timeline.
  const conversionSrc = engine && engine.decision.path !== 'direct' ? src : '';
  useEffect(() => {
    const current = engineRef.current;
    if (!conversionSrc || !current) return;
    const controller = new AbortController();
    const wantsCues = current.subtitleIndex !== null;
    let startKnown = false;
    let text = '';
    let from = 0;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const poll = async () => {
      try {
        const state = await fetchConversionState(current.base, playerId.current, from, controller.signal);
        if (controller.signal.aborted) return;
        if (!startKnown && typeof state.start === 'number') {
          startKnown = true;
          const latest = engineRef.current;
          if (latest && latest.base === current.base && Math.abs(latest.offset - state.start) > 0.01) {
            setEngine({ ...latest, offset: state.start });
          }
        }
        if (wantsCues && state.text) {
          text += state.text;
          from = state.next;
          setEmbeddedCues(parseSubtitles(text, 'vtt'));
        }
        const more = !startKnown || (wantsCues && (!state.done || state.missing));
        if (more) timer = setTimeout(poll, wantsCues && startKnown ? CONVERSION_POLL_MS * 2 : CONVERSION_POLL_MS);
      } catch {
        if (!controller.signal.aborted) timer = setTimeout(poll, CONVERSION_POLL_MS * 3);
      }
    };
    timer = setTimeout(poll, 500);
    return () => {
      controller.abort();
      clearTimeout(timer);
    };
  }, [conversionSrc, setEngine]);

  const scrobbleMedia = useMemo<TraktMediaInfo | null>(() => {
    if (!identity.imdbId && !identity.tmdbId) return null;
    return {
      type: isEpisode ? 'episode' : 'movie',
      title,
      imdbId: imdbId ?? identity.imdbId,
      tmdbId: identity.tmdbId,
      season: identity.seasonNumber,
      episode: identity.episodeNumber,
      episodeTitle: currentEpisode?.title,
    };
  }, [identity, imdbId, isEpisode, title, currentEpisode]);

  const next = useMemo<NextEpisode | null>(() => nextEpisode && ({
    title: nextEpisode.title,
    label: episodeLabel(nextEpisode.season, nextEpisode.episode),
    summary: nextEpisode.overview,
    thumb: nextEpisode.stillUrl,
  }), [nextEpisode]);

  const onAudioTracks = useCallback((tracks: TrackOption[]) => {
    setHlsAudio(tracks);
    if (tracks.length === 0) return;
    if (audioApplied.current) return;
    audioApplied.current = true;
    const preferred = pickAudioTrack(tracks, { itemKey: `stream:${identity.requestId}`, seriesKey: isEpisode ? `stream:${identity.baseId}` : undefined });
    setHlsAudioSelected((preferred ?? tracks.find((track) => track.default) ?? tracks[0]).id);
  }, [identity, isEpisode]);

  const engineAudio = useMemo<TrackOption[]>(() => (engine?.info.audio ?? []).map((track) => ({
    id: String(track.index),
    label: audioLabel(track),
    language: track.language,
    languageCode: track.language,
    default: track.isDefault,
  })), [engine?.info]);

  const selectAudio = useCallback((id: string) => {
    const current = engineRef.current;
    if (current && current.info.audio.length > 0) {
      const track = engineAudio.find((option) => option.id === id);
      if (track) {
        saveTrackPreference('audio', `stream:${identity.requestId}`, isEpisode ? `stream:${identity.baseId}` : undefined, track.languageCode || track.language || '');
      }
      if (Number(id) !== current.audioIndex) restartEngine(clock.time.current, { audioIndex: Number(id) });
      return;
    }
    const track = hlsAudio.find((option) => option.id === id);
    if (track) {
      saveTrackPreference('audio', `stream:${identity.requestId}`, isEpisode ? `stream:${identity.baseId}` : undefined, track.languageCode || track.language || '');
    }
    setHlsAudioSelected(id);
  }, [clock, engineAudio, hlsAudio, identity, isEpisode, restartEngine]);

  const stats = useMemo(() => {
    if (!engine) return { videoDecision: 'directplay', audioDecision: 'directplay', isTranscoding: false };
    const { decision, info } = engine;
    return {
      videoDecision: decision.path === 'compatible' ? 'transcode' : decision.path === 'remux' ? 'copy' : 'directplay',
      audioDecision: decision.path === 'direct' || decision.copyAudio ? 'directplay' : 'transcode',
      isTranscoding: decision.path === 'compatible',
      engine: decision.path,
      engineReason: decision.reason,
      container: info.container,
      videoCodec: info.video ? `${info.video.codec} ${info.video.bitDepth}-bit${info.video.hdr ? ` ${info.video.hdr.toUpperCase()}` : ''}${info.video.dolbyVisionProfile !== null ? ` DV${info.video.dolbyVisionProfile}` : ''}` : 'none',
    };
  }, [engine]);

  const timeline = useMemo<PlayerSession['timeline']>(() => {
    if (!engine) return undefined;
    if (engine.decision.path === 'direct') return { offset: 0, duration: engine.info.duration };
    return { offset: engine.offset, duration: engine.info.duration, seek: (seconds: number) => restartEngine(seconds, {}) };
  }, [engine, restartEngine]);

  return {
    kind: 'stream',
    media,
    src,
    streamKind,
    crossOrigin: null,
    startAt,
    loading,
    error,
    notice: null,
    status,
    markers,
    chapters: [],
    exitAtCredits: false,
    scrobbleMedia,
    quality: null,
    audio: engineAudio.length > 0
      ? { options: engineAudio, selected: engine?.audioIndex !== null && engine?.audioIndex !== undefined ? String(engine.audioIndex) : null, select: selectAudio }
      : { options: hlsAudio, selected: hlsAudioSelected, select: selectAudio },
    subtitles,
    embeddedCues,
    setEmbeddedSubtitle,
    timeline,
    initialSubtitleId: null,
    setBurnedSubtitle,
    stats,
    next,
    playNext,
    prefetchNext,
    browser: isEpisode ? browser : null,
    openSources,
    sourcesRequest,
    closeSources,
    onEngineError,
    onCodecError: onEngineError,
    onEnded,
    onReady,
    onAudioTracks,
    audioTrackIndex: engine ? undefined : hlsAudioSelected !== null ? Number(hlsAudioSelected) : undefined,
    exit: onBack,
    goToDetails: onBack,
  };
}
