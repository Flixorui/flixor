import type { StremioSubtitleCandidate } from '../../../stremio/types';

type Track = {
  id: number;
  name: string;
  language?: string;
  languageCode?: string;
};

const LANGUAGE_ALIASES: Record<string, string[]> = {
  en: ['en', 'eng', 'english'],
  es: ['es', 'spa', 'spanish', 'espanol', 'español'],
  fr: ['fr', 'fre', 'fra', 'french', 'francais', 'français'],
  ja: ['ja', 'jpn', 'japanese'],
};

export function normalizeLanguageCode(input?: string): string {
  const normalized = (input || '').trim().toLowerCase();
  for (const [code, aliases] of Object.entries(LANGUAGE_ALIASES)) {
    if (aliases.includes(normalized)) {
      return code;
    }
  }
  return normalized;
}

export function trackMatchesLanguage(track: Track, preferredLanguage?: string): boolean {
  const preferred = normalizeLanguageCode(preferredLanguage);
  if (!preferred) {
    return false;
  }

  const candidates = [
    normalizeLanguageCode(track.languageCode),
    normalizeLanguageCode(track.language),
    normalizeLanguageCode(track.name),
  ];

  return candidates.includes(preferred);
}

export function findBestAudioTrack(tracks: Track[], preferredLanguage?: string): number | null {
  if (!preferredLanguage) {
    return null;
  }
  const match = tracks.find((track) => trackMatchesLanguage(track, preferredLanguage));
  return match ? match.id : null;
}

export function findBestSubtitleTrack(
  internalTracks: Track[],
  externalSubtitles: StremioSubtitleCandidate[],
  settings: {
    preferredSubtitleLanguage?: string;
    subtitleSourcePreference?: 'internal' | 'external' | 'any';
    enableSubtitleAutoSelect?: boolean;
  }
): {
  type: 'internal' | 'external' | 'none';
  internalTrackId?: number;
  externalSubtitle?: StremioSubtitleCandidate;
} {
  if (settings.enableSubtitleAutoSelect === false) {
    return { type: 'none' };
  }

  const preferredLanguage = normalizeLanguageCode(settings.preferredSubtitleLanguage);
  const internalMatch = internalTracks.find((track) => trackMatchesLanguage(track, preferredLanguage));
  const externalMatch = externalSubtitles.find(
    (subtitle) => normalizeLanguageCode(subtitle.lang) === preferredLanguage
  );

  switch (settings.subtitleSourcePreference) {
    case 'external':
      if (externalMatch) {
        return { type: 'external', externalSubtitle: externalMatch };
      }
      if (internalMatch) {
        return { type: 'internal', internalTrackId: internalMatch.id };
      }
      break;
    case 'any':
      if (internalMatch) {
        return { type: 'internal', internalTrackId: internalMatch.id };
      }
      if (externalMatch) {
        return { type: 'external', externalSubtitle: externalMatch };
      }
      break;
    case 'internal':
    default:
      if (internalMatch) {
        return { type: 'internal', internalTrackId: internalMatch.id };
      }
      if (externalMatch) {
        return { type: 'external', externalSubtitle: externalMatch };
      }
      break;
  }

  return { type: 'none' };
}
