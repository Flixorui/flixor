import { useCallback, useMemo, useState } from 'react';
import type { SubtitleCue, StremioSubtitleCandidate } from '../../../stremio/types';
import { appLogger } from '../../../core/AppLogger';
import { parseSubtitleContent } from '../utils/subtitleParser';
import { removeHearingImpairedText } from '../utils/subtitleFilters';

export function useCustomSubtitles(options?: { filterHearingImpaired?: boolean }) {
  const filterHearingImpaired = Boolean(options?.filterHearingImpaired);
  // Positive delays subtitles, negative shows them earlier. Applies to addon subtitles only.
  const [delayMs, setDelayMs] = useState(0);
  const [selectedExternalSubtitleId, setSelectedExternalSubtitleId] = useState<string | null>(null);
  const [loadedSubtitle, setLoadedSubtitle] = useState<StremioSubtitleCandidate | null>(null);
  const [cues, setCues] = useState<SubtitleCue[]>([]);
  const [currentTimeMs, setCurrentTimeMs] = useState(0);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const currentCue = useMemo(() => {
    const cueTime = (currentTimeMs - delayMs) / 1000;
    return cues.find((cue) => cueTime >= cue.startTime && cueTime <= cue.endTime) || null;
  }, [cues, currentTimeMs, delayMs]);

  const currentText = useMemo(() => {
    const text = currentCue?.text || '';
    return filterHearingImpaired ? removeHearingImpairedText(text) : text;
  }, [currentCue, filterHearingImpaired]);

  const clear = useCallback(() => {
    setSelectedExternalSubtitleId(null);
    setLoadedSubtitle(null);
    setCues([]);
    setError(null);
    setDelayMs(0);
  }, []);

  const loadSubtitle = useCallback(async (subtitle: StremioSubtitleCandidate) => {
    setIsLoading(true);
    setError(null);
    try {
      const response = await fetch(subtitle.url);
      if (!response.ok) {
        throw new Error(`${response.status} ${response.statusText}`);
      }
      const content = await response.text();
      const parsed = parseSubtitleContent(content, subtitle.url);
      setLoadedSubtitle(subtitle);
      setSelectedExternalSubtitleId(subtitle.id);
      setCues(parsed);
      appLogger.info('[Stremio] External subtitle loaded', {
        subtitleId: subtitle.id,
        language: subtitle.lang,
        cueCount: parsed.length,
      });
    } catch (loadError: any) {
      setError(loadError?.message || 'Failed to load subtitle file');
      setSelectedExternalSubtitleId(null);
      setLoadedSubtitle(null);
      setCues([]);
      appLogger.warn('[Stremio] External subtitle failed', {
        subtitleId: subtitle.id,
        language: subtitle.lang,
        error: loadError?.message || String(loadError),
      });
    } finally {
      setIsLoading(false);
    }
  }, []);

  return {
    cues,
    currentCue,
    currentText,
    currentTimeMs,
    delayMs,
    setDelayMs,
    selectedExternalSubtitleId,
    loadedSubtitle,
    isLoading,
    error,
    setCurrentTimeMs,
    loadSubtitle,
    clear,
  };
}
