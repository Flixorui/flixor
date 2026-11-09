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
  return sections;
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
