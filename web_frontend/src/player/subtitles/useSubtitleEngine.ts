import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useSettings } from '@/state/settings';
import { fetchSubtitleText } from '@/stremio';
import { applySdhFilter, decodeSubtitles, parseSubtitles, SubtitleCue } from './parser';
import { pickSubtitleTrack, saveTrackPreference, SUBTITLES_OFF } from '../tracks/trackPreferences';
import type { PlayerClock, PlayerSession, SubtitleOption } from '../types';

export const SUBTITLE_DELAY_LIMIT = 3600;

export interface SubtitleEngine {
  options: SubtitleOption[];
  /** The selected option's id. Null means off. */
  selectedId: string | null;
  loading: boolean;
  loadError: string | null;
  /** Cues after the SDH filter. Empty for burned-in tracks. */
  cues: SubtitleCue[];
  /** Seconds. Positive shows a cue later. */
  delay: number;
  setDelay: (seconds: number) => void;
  /** Makes this cue appear at the current playback position. */
  syncToCue: (cue: SubtitleCue) => void;
  select: (option: SubtitleOption | null) => void;
}

async function loadCues(option: SubtitleOption): Promise<SubtitleCue[]> {
  if (option.addonSubtitle) return parseSubtitles(await fetchSubtitleText(option.addonSubtitle), option.format);
  // Plex URLs carry the server token, so they are only ever fetched directly.
  const res = await fetch(option.url as string, { credentials: 'omit' });
  if (!res.ok) throw new Error(String(res.status));
  return parseSubtitles(decodeSubtitles(await res.arrayBuffer()), option.format);
}

export function useSubtitleEngine(session: PlayerSession, clock: PlayerClock): SubtitleEngine {
  const { subtitleFilterSDH } = useSettings();
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [rawCues, setRawCues] = useState<SubtitleCue[]>([]);
  const [loading, setLoading] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [delay, setDelayState] = useState(0);

  const options = session.subtitles;
  const selectedRef = useRef<SubtitleOption | null>(null);
  const loadToken = useRef(0);
  const userChose = useRef(false);
  const sessionRef = useRef(session);
  sessionRef.current = session;

  const applySelection = useCallback((option: SubtitleOption | null) => {
    const previous = selectedRef.current;
    selectedRef.current = option;
    setSelectedId(option?.id ?? null);
    setLoadError(null);
    setDelayState(0);
    const token = ++loadToken.current;

    if (previous?.delivery === 'burn' && option?.delivery !== 'burn') {
      sessionRef.current.setBurnedSubtitle('0');
    }
    if (!option) {
      setRawCues([]);
      setLoading(false);
      return;
    }
    if (option.delivery === 'burn') {
      setRawCues([]);
      setLoading(false);
      sessionRef.current.setBurnedSubtitle(option.id);
      return;
    }

    setRawCues([]);
    setLoading(true);
    loadCues(option).then(
      (cues) => {
        if (token !== loadToken.current) return;
        setRawCues(cues);
        setLoading(false);
        if (cues.length === 0) setLoadError('This subtitle file is empty or in an unsupported format.');
      },
      () => {
        if (token !== loadToken.current) return;
        setLoading(false);
        setLoadError("This subtitle couldn't be loaded.");
      },
    );
  }, []);

  const select = useCallback((option: SubtitleOption | null) => {
    userChose.current = true;
    const media = sessionRef.current.media;
    if (media) {
      const language = option ? option.languageCode || option.language || '' : SUBTITLES_OFF;
      saveTrackPreference('subtitle', media.itemKey, media.seriesKey, language);
    }
    applySelection(option);
  }, [applySelection]);

  // Applies remembered and preferred tracks. Addon subtitles arrive after playback
  // starts, so this re-runs as options appear, until something is selected or chosen.
  const initialId = session.initialSubtitleId;
  const itemKey = session.media?.itemKey;
  const seriesKey = session.media?.seriesKey;
  useEffect(() => {
    if (userChose.current || !itemKey) return;
    if (initialId) {
      const initial = options.find((option) => option.id === initialId);
      if (initial && selectedRef.current?.id !== initial.id) {
        // Plex is already burning this track in: just reflect it.
        selectedRef.current = initial;
        setSelectedId(initial.id);
      }
      return;
    }
    if (selectedRef.current || options.length === 0) return;

    const isPlex = sessionRef.current.kind === 'plex';
    const candidates = options.filter((option) => option.delivery === 'client');
    if (candidates.length === 0) return;
    // Plex: only when this item already has subtitles on, as on macOS.
    const autoLanguage = !isPlex || options.some((option) => option.default);
    const choice = pickSubtitleTrack(candidates, { itemKey, seriesKey, autoLanguage });
    if (choice && 'track' in choice) {
      applySelection(choice.track);
    } else if (!choice && isPlex) {
      const flagged = candidates.find((option) => option.default);
      if (flagged) applySelection(flagged);
    }
  }, [options, initialId, itemKey, seriesKey, applySelection]);

  const cues = useMemo(() => (subtitleFilterSDH ? applySdhFilter(rawCues) : rawCues), [rawCues, subtitleFilterSDH]);

  const setDelay = useCallback((seconds: number) => {
    const limited = Math.min(SUBTITLE_DELAY_LIMIT, Math.max(-SUBTITLE_DELAY_LIMIT, seconds));
    setDelayState(Math.round(limited * 1000) / 1000);
  }, []);

  const syncToCue = useCallback((cue: SubtitleCue) => {
    setDelay(clock.time.current - cue.start);
  }, [clock, setDelay]);

  return { options, selectedId, loading, loadError, cues, delay, setDelay, syncToCue, select };
}
