import type { SkipSegment } from '@/services/skipSegments';
import type { PlayerChapter, PlayerMarker } from './types';

export const SKIPPABLE_TYPES = new Set(['intro', 'recap', 'credits', 'preview']);

export function isSkippable(marker: PlayerMarker): boolean {
  return SKIPPABLE_TYPES.has(marker.type);
}

export function skipLabel(marker: PlayerMarker): string {
  const names: Record<string, string> = { intro: 'Intro', recap: 'Recap', credits: 'Credits', preview: 'Preview' };
  return `Skip ${names[marker.type] ?? 'Marker'}`;
}

function segmentToMarker(segment: SkipSegment, duration: number): PlayerMarker | null {
  const end = segment.end !== null ? (duration > 0 ? Math.min(segment.end, duration) : segment.end) : duration > 0 ? duration : null;
  if (end === null || end <= segment.start) return null;
  return {
    id: `community-${segment.provider}-${segment.type}-${Math.round(segment.start * 1000)}`,
    type: segment.type,
    start: segment.start,
    end,
  };
}

/** Plex markers, plus community segments for the types Plex did not provide. */
export function mergeMarkers(plex: PlayerMarker[], community: SkipSegment[], duration: number): PlayerMarker[] {
  const plexTypes = new Set(plex.map((marker) => marker.type));
  const extra = community
    .filter((segment) => !plexTypes.has(segment.type))
    .map((segment) => segmentToMarker(segment, duration))
    .filter((marker): marker is PlayerMarker => marker !== null);
  return [...plex, ...extra].sort((a, b) => a.start - b.start);
}

export function findCreditsChapter(chapters: PlayerChapter[], duration: number): PlayerChapter | null {
  if (duration <= 0) return null;
  // A "credits" chapter in the first half is more likely an opening title sequence.
  return chapters.find((chapter) => /credits/i.test(chapter.title) && chapter.start >= duration * 0.5) ?? null;
}

/** When the next-episode countdown starts: credits marker, credits chapter, then a fallback. */
export function nextEpisodeTrigger(
  markers: PlayerMarker[],
  chapters: PlayerChapter[],
  duration: number,
  fallbackSeconds: number,
): number {
  const buffer = 3;
  const credits = markers.find((marker) => marker.type === 'credits');
  if (credits) {
    const scene = markers.find((marker) => marker.type === 'postcredits' && marker.start >= credits.start);
    return Math.max(0, (scene ? scene.end : credits.start) - buffer);
  }
  const chapter = findCreditsChapter(chapters, duration);
  if (chapter) return Math.max(0, chapter.start - buffer);
  return Math.max(0, duration - fallbackSeconds);
}
