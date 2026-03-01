import { useCallback, useMemo, useState } from 'react';
import type { SubtitleCue, StremioSubtitleCandidate } from '../../../stremio/types';
import { appLogger } from '../../../core/AppLogger';
import { parseSubtitleContent } from '../utils/subtitleParser';

export function useCustomSubtitles() {
  const [selectedExternalSubtitleId, setSelectedExternalSubtitleId] = useState<string | null>(null);
  const [loadedSubtitle, setLoadedSubtitle] = useState<StremioSubtitleCandidate | null>(null);
  const [cues, setCues] = useState<SubtitleCue[]>([]);
  const [currentTimeMs, setCurrentTimeMs] = useState(0);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const currentCue = useMemo(
    () =>
      cues.find(
        (cue) =>
          currentTimeMs / 1000 >= cue.startTime && currentTimeMs / 1000 <= cue.endTime
      ) || null,
    [cues, currentTimeMs]
  );

  const clear = useCallback(() => {
    setSelectedExternalSubtitleId(null);
    setLoadedSubtitle(null);
    setCues([]);
    setError(null);
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
    currentText: currentCue?.text || '',
    selectedExternalSubtitleId,
    loadedSubtitle,
    isLoading,
    error,
    setCurrentTimeMs,
    loadSubtitle,
    clear,
  };
}
