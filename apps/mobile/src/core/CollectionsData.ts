/**
 * Collections data fetchers using FlixorCore
 * Fetches Plex collections for library browsing
 */

import { getFlixorCore } from './index';
import type { PlexMediaItem } from '@flixor/core';

export type CollectionItem = {
  ratingKey: string;
  title: string;
  thumb?: string;
  art?: string;
  childCount?: number;
  type: string;
};

export type CollectionMediaItem = {
  ratingKey: string;
  title: string;
  type: 'movie' | 'show';
  thumb?: string;
  year?: number;
};

// ============================================
// Fetch Collections
// ============================================

export async function fetchCollections(
  libraryType?: 'movie' | 'show'
): Promise<CollectionItem[]> {
  try {
    const core = getFlixorCore();
    const collections = await core.plexServer.getAllCollections(libraryType);

    return collections.map((c: PlexMediaItem) => ({
      ratingKey: String(c.ratingKey),
      title: c.title || 'Untitled',
      thumb: c.thumb,
      art: c.art,
      childCount: (c as any).childCount,
      type: c.type || 'collection',
    }));
  } catch (e) {
    console.log('[CollectionsData] fetchCollections error:', e);
    return [];
  }
}

// ============================================
// Fetch Collection Items
// ============================================

export async function fetchCollectionItems(
  collectionRatingKey: string,
  options?: {
    offset?: number;
    limit?: number;
  }
): Promise<{ items: CollectionMediaItem[]; hasMore: boolean }> {
  try {
    const core = getFlixorCore();
    const { offset = 0, limit = 40 } = options || {};

    const items = await core.plexServer.getCollectionItems(collectionRatingKey, {
      start: offset,
      size: limit,
    });

    const mapped: CollectionMediaItem[] = items.map((m: PlexMediaItem) => ({
      ratingKey: String(m.ratingKey),
      title: m.title || 'Untitled',
      type: m.type as 'movie' | 'show',
      thumb: m.thumb,
      year: m.year,
    }));

    return {
      items: mapped,
      hasMore: mapped.length === limit,
    };
  } catch (e) {
    console.log('[CollectionsData] fetchCollectionItems error:', e);
    return { items: [], hasMore: false };
  }
}

// ============================================
// Image URLs
// ============================================

export function getCollectionImageUrl(
  thumb: string | undefined,
  width: number = 300
): string {
  if (!thumb) return '';
  try {
    const core = getFlixorCore();
    return core.plexServer.getImageUrl(thumb, width);
  } catch {
    return '';
  }
}
