import { getSettings } from '@/state/settings';
import { bestLanguageMatch, sameLanguage } from './languageMatcher';
import type { SubtitleOption, TrackOption } from '../types';

type Kind = 'audio' | 'subtitle';

const STORAGE: Record<Kind, string> = {
  audio: 'player.audioTrackPreferences',
  subtitle: 'player.subtitleTrackPreferences',
};
const MAX_ENTRIES = 500;

/** Marks a title whose subtitles the user turned off. */
export const SUBTITLES_OFF = 'none';

function read(kind: Kind): Record<string, string> {
  try {
    const parsed = JSON.parse(localStorage.getItem(STORAGE[kind]) || '{}');
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch {
    return {};
  }
}

function write(kind: Kind, prefs: Record<string, string>) {
  try {
    const keys = Object.keys(prefs);
    for (const key of keys.slice(0, Math.max(0, keys.length - MAX_ENTRIES))) delete prefs[key];
    localStorage.setItem(STORAGE[kind], JSON.stringify(prefs));
  } catch {
    // Storage full or blocked: the choice just isn't remembered.
  }
}

export function saveTrackPreference(kind: Kind, itemKey: string, seriesKey: string | undefined, language: string) {
  if (!getSettings().rememberTrackSelections || !language) return;
  const prefs = read(kind);
  // Re-insert so the entry counts as newest when the map is trimmed.
  delete prefs[itemKey];
  prefs[itemKey] = language;
  if (seriesKey) {
    delete prefs[`series:${seriesKey}`];
    prefs[`series:${seriesKey}`] = language;
  }
  write(kind, prefs);
}

/** The language saved for this title, else for its series. Never a global guess. */
export function rememberedLanguage(kind: Kind, itemKey: string, seriesKey?: string): string | null {
  if (!getSettings().rememberTrackSelections) return null;
  const prefs = read(kind);
  return prefs[itemKey] ?? (seriesKey ? prefs[`series:${seriesKey}`] : undefined) ?? null;
}

/** Remembered audio language, then the preferred one. `original` needs `originalLanguage`. */
export function pickAudioTrack(
  tracks: TrackOption[],
  context: { itemKey: string; seriesKey?: string; originalLanguage?: string | null },
): TrackOption | null {
  const describe = (track: TrackOption) => ({
    lang: track.languageCode || track.language,
    title: track.label,
    isDefault: track.default,
  });
  const remembered = rememberedLanguage('audio', context.itemKey, context.seriesKey);
  if (remembered) {
    const match = tracks.find((track) => sameLanguage(track.languageCode || track.language, remembered));
    if (match) return match;
  }
  const preferred = getSettings().preferredAudioLanguage.trim();
  if (!preferred) return null;
  const language = preferred.toLowerCase() === 'original' ? context.originalLanguage : preferred;
  return language ? bestLanguageMatch(tracks, language, describe) : null;
}

export type SubtitleChoice = { track: SubtitleOption } | { off: true } | null;

/**
 * Remembered choice first, then the preferred language.
 * `autoLanguage` is false when only remembered choices may apply.
 */
export function pickSubtitleTrack(
  tracks: SubtitleOption[],
  context: { itemKey: string; seriesKey?: string; autoLanguage: boolean },
): SubtitleChoice {
  const remembered = rememberedLanguage('subtitle', context.itemKey, context.seriesKey);
  if (remembered === SUBTITLES_OFF) return { off: true };
  if (remembered) {
    const match = tracks.find((track) => sameLanguage(track.languageCode || track.language, remembered));
    if (match) return { track: match };
  }
  const settings = getSettings();
  const preferred = settings.preferredSubtitleLanguage.trim();
  if (!context.autoLanguage || !settings.enableSubtitleAutoSelect || !preferred) return null;
  const match = bestLanguageMatch(tracks, preferred, (track) => ({
    lang: track.languageCode || track.language,
    title: track.label,
    forced: track.forced,
    isDefault: track.default,
  }));
  return match ? { track: match } : null;
}

/** Text formats the browser engine can parse. Anything else needs a Plex burn-in. */
export function isClientRenderable(codec?: string): boolean {
  return ['srt', 'subrip', 'ass', 'ssa', 'vtt', 'webvtt', 'text', 'mov_text'].includes((codec || '').toLowerCase());
}
