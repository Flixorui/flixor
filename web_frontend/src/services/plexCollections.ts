/** Plex libraries, collections and the mapping of Plex items to cards. */
import { apiClient } from '@/services/api';
import { plexBackendCollections, plexBackendDir, plexBackendLibraries } from '@/services/plex_backend';
import type { CardItem, CardMediaType } from '@/components/cards/cardTypes';

export interface PlexLibrary {
  key: string;
  title: string;
  type: 'movie' | 'show';
}

export interface PlexCollection {
  ratingKey: string;
  title: string;
  libraryKey: string;
  libraryTitle: string;
  image?: string;
  count: number;
}

export function plexImage(path?: string) {
  return path ? apiClient.getPlexImageNoToken(path) : undefined;
}

export function plexItemToCard(m: any): CardItem {
  const type = String(m.type || '') as CardMediaType;
  const isEpisode = type === 'episode';
  return {
    id: `plex:${m.ratingKey}`,
    title: (isEpisode ? m.grandparentTitle : m.title) || m.title || m.grandparentTitle || 'Title',
    subtitle: isEpisode && m.parentIndex && m.index ? `S${m.parentIndex} E${m.index} · ${m.title}` : undefined,
    image: plexImage(m.thumb || m.parentThumb || m.grandparentThumb || m.art),
    backdrop: plexImage(m.art || m.grandparentArt),
    mediaType: type || undefined,
    year: m.year,
    rating: m.rating || m.audienceRating || undefined,
    overview: m.summary || undefined,
  };
}

export async function getPlexLibraries(): Promise<PlexLibrary[]> {
  const res: any = await plexBackendLibraries();
  return (res?.MediaContainer?.Directory || [])
    .filter((d: any) => d.type === 'movie' || d.type === 'show')
    .map((d: any) => ({ key: String(d.key), title: d.title, type: d.type }));
}

/** `enabledLibraryKeys` is empty when every library is enabled. */
export function filterEnabledLibraries(libraries: PlexLibrary[], enabledKeys: string[]) {
  if (enabledKeys.length === 0) return libraries;
  const enabled = new Set(enabledKeys);
  const filtered = libraries.filter((library) => enabled.has(library.key));
  return filtered.length > 0 ? filtered : libraries;
}

export async function getLibraryCollections(library: PlexLibrary): Promise<PlexCollection[]> {
  const res: any = await plexBackendCollections(library.key);
  return (res?.MediaContainer?.Metadata || []).map((c: any) => ({
    ratingKey: String(c.ratingKey),
    title: c.title || 'Untitled Collection',
    libraryKey: library.key,
    libraryTitle: library.title,
    image: plexImage(c.thumb || c.art),
    count: Number(c.childCount) || 0,
  }));
}

/** Every collection in the given libraries. A library that fails is left out. */
export async function getAllCollections(libraries: PlexLibrary[]): Promise<PlexCollection[]> {
  const results = await Promise.all(libraries.map((library) => getLibraryCollections(library).catch(() => [])));
  return results.flat();
}

export function collectionChildrenPath(ratingKey: string) {
  return `/library/collections/${ratingKey}/children`;
}

export async function getCollectionItems(ratingKey: string, size?: number): Promise<CardItem[]> {
  const params = size ? { 'X-Plex-Container-Start': 0, 'X-Plex-Container-Size': size } : undefined;
  const res: any = await plexBackendDir(collectionChildrenPath(ratingKey), params);
  return (res?.MediaContainer?.Metadata || []).map(plexItemToCard);
}
