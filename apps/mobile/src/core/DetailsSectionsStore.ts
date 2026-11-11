/**
 * Order and visibility of the sections below the details hero.
 * macOS reference: Services/DetailsSectionsStore.swift, Extensions/UserDefaults+DetailsSections.swift
 */

import type { Ionicons } from '@expo/vector-icons';
import { DEFAULT_APP_SETTINGS, type DetailsSectionKey, type DetailsSectionPreference } from './SettingsData';

export const DETAILS_SECTION_KEYS: DetailsSectionKey[] = [
  'episodes',
  'suggested',
  'collection',
  'cast',
  'trailers',
  'comments',
  'about',
];

export interface DetailsSectionMeta {
  title: string;
  tabLabel: string;
  subtitle: string;
  icon: keyof typeof Ionicons.glyphMap;
}

export const DETAILS_SECTION_META: Record<DetailsSectionKey, DetailsSectionMeta> = {
  episodes: { title: 'Episodes', tabLabel: 'Episodes', subtitle: 'Seasons and episodes (TV shows)', icon: 'list-outline' },
  suggested: { title: 'More Like This', tabLabel: 'Suggested', subtitle: 'Related and similar titles', icon: 'albums-outline' },
  collection: { title: 'Collection', tabLabel: 'Collection', subtitle: 'Other movies in the franchise', icon: 'layers-outline' },
  cast: { title: 'Cast & Crew', tabLabel: 'Cast & Crew', subtitle: 'Cast, crew and creators', icon: 'people-outline' },
  trailers: { title: 'Trailers & Videos', tabLabel: 'Videos', subtitle: 'Trailers, teasers and featurettes', icon: 'play-circle-outline' },
  comments: { title: 'Comments', tabLabel: 'Comments', subtitle: 'Trakt comments and reviews', icon: 'chatbubble-outline' },
  about: { title: 'Details', tabLabel: 'Details', subtitle: 'Production, technical info and ratings', icon: 'information-circle-outline' },
};

/**
 * The mobile default before it matched macOS (Suggested second, Comments off). A saved list
 * that is exactly this was never customised, so it follows the new default.
 * macOS does the same with DetailsSectionKey.previousDefaultOrder.
 */
const PREVIOUS_DEFAULT: DetailsSectionPreference[] = [
  { key: 'episodes', enabled: true },
  { key: 'suggested', enabled: true },
  { key: 'collection', enabled: true },
  { key: 'cast', enabled: true },
  { key: 'trailers', enabled: true },
  { key: 'comments', enabled: false },
  { key: 'about', enabled: true },
];

function isPreviousDefault(sections: DetailsSectionPreference[]): boolean {
  return (
    sections.length === PREVIOUS_DEFAULT.length &&
    sections.every((s, i) => s.key === PREVIOUS_DEFAULT[i].key && s.enabled === PREVIOUS_DEFAULT[i].enabled)
  );
}

export function defaultDetailsSections(): DetailsSectionPreference[] {
  return DEFAULT_APP_SETTINGS.detailsSectionPreferences.map((section) => ({ ...section }));
}

/**
 * The saved list with unknown keys and duplicates dropped, and any section added in a
 * later version appended, so a stored list can never hide or lose a section.
 */
export function normalizeDetailsSections(saved?: DetailsSectionPreference[] | null): DetailsSectionPreference[] {
  const seen = new Set<DetailsSectionKey>();
  const sections: DetailsSectionPreference[] = [];
  for (const entry of saved ?? []) {
    if (!entry || !DETAILS_SECTION_KEYS.includes(entry.key) || seen.has(entry.key)) continue;
    seen.add(entry.key);
    sections.push({ key: entry.key, enabled: entry.enabled !== false });
  }
  for (const section of defaultDetailsSections()) {
    if (!seen.has(section.key)) sections.push(section);
  }
  return isPreviousDefault(sections) ? defaultDetailsSections() : sections;
}

export function orderedEnabledSections(saved?: DetailsSectionPreference[] | null): DetailsSectionKey[] {
  return normalizeDetailsSections(saved)
    .filter((section) => section.enabled)
    .map((section) => section.key);
}

/** Moves a section one step up (-1) or down (+1). Returns the list unchanged at either end. */
export function moveDetailsSection(
  sections: DetailsSectionPreference[],
  key: DetailsSectionKey,
  offset: -1 | 1
): DetailsSectionPreference[] {
  const from = sections.findIndex((section) => section.key === key);
  const to = from + offset;
  if (from < 0 || to < 0 || to >= sections.length) return sections;
  const next = [...sections];
  [next[from], next[to]] = [next[to], next[from]];
  return next;
}
