/**
 * Library screen data fetchers using FlixorCore
 * Replaces the old api/data.ts functions for Library screen
 */

import { getFlixorCore } from './index';
import type { PlexLibrary, PlexMediaItem } from '@flixor/core';

export type LibraryItem = {
  ratingKey: string;
  title: string;
  type: 'movie' | 'show' | 'episode';
  thumb?: string;
  year?: number;
};

export type LibrarySections = {
  show?: string;
  movie?: string;
};

// Sort options for library items
export type LibrarySortOption = {
  label: string;
  value: string;
};

export const LIBRARY_SORT_OPTIONS: LibrarySortOption[] = [
  { label: 'Date Added', value: 'addedAt:desc' },
  { label: 'Title', value: 'titleSort:asc' },
  { label: 'Year (Newest)', value: 'year:desc' },
  { label: 'Year (Oldest)', value: 'year:asc' },
  { label: 'Rating', value: 'rating:desc' },
  { label: 'Release Date', value: 'originallyAvailableAt:desc' },
];

// ============================================
// Library Sections
// ============================================

export async function fetchLibrarySections(): Promise<LibrarySections> {
  try {
    const core = getFlixorCore();
    const libraries = await core.plexServer.getLibraries();

    const showLib = libraries.find((lib: PlexLibrary) => lib.type === 'show');
    const movieLib = libraries.find((lib: PlexLibrary) => lib.type === 'movie');

    return {
      show: showLib?.key ? String(showLib.key) : undefined,
      movie: movieLib?.key ? String(movieLib.key) : undefined,
    };
  } catch (e) {
    console.log('[LibraryData] fetchLibrarySections error:', e);
    return {};
  }
}

// ============================================
// Library Items
// ============================================

export async function fetchLibraryItems(
  sectionKey: string,
  options?: {
    type?: 'movie' | 'show' | 'all';
    offset?: number;
    limit?: number;
    sort?: string;
    genreKey?: string;
  }
): Promise<{ items: LibraryItem[]; hasMore: boolean }> {
  try {
    const core = getFlixorCore();
    const { type = 'all', offset = 0, limit = 40, sort = 'addedAt:desc', genreKey } = options || {};

    // Type filter: 1 = movie, 2 = show
    const typeNumber = type === 'movie' ? 1 : type === 'show' ? 2 : undefined;

    console.log('[LibraryData] fetchLibraryItems:', { sectionKey, type, typeNumber, offset, limit, sort, genreKey });

    let items: PlexMediaItem[];

    if (genreKey) {
      // Use genre filtering
      items = await core.plexServer.getItemsByGenre(sectionKey, genreKey, {
        start: offset,
        size: limit,
        sort,
      });
    } else {
      items = await core.plexServer.getLibraryItems(sectionKey, {
        type: typeNumber,
        offset,
        limit,
        sort,
      });
    }

    console.log('[LibraryData] Received', items.length, 'items from offset', offset);

    const mapped: LibraryItem[] = items.map((m: PlexMediaItem) => ({
      ratingKey: String(m.ratingKey),
      title: m.title || m.grandparentTitle || 'Untitled',
      type: m.type as 'movie' | 'show' | 'episode',
      thumb: m.thumb || m.parentThumb || m.grandparentThumb,
      year: m.year,
    }));

    // Determine if there are more items
    const hasMore = mapped.length === limit;
    console.log('[LibraryData] hasMore:', hasMore, '(received', mapped.length, 'of limit', limit, ')');

    return { items: mapped, hasMore };
  } catch (e) {
    console.log('[LibraryData] fetchLibraryItems error:', e);
    return { items: [], hasMore: false };
  }
}

// ============================================
// Image URLs
// ============================================

export function getLibraryImageUrl(thumb: string | undefined, width: number = 300): string {
  if (!thumb) return '';
  try {
    const core = getFlixorCore();
    return core.plexServer.getImageUrl(thumb, width);
  } catch {
    return '';
  }
}

// ============================================
// User Info
// ============================================

export async function getLibraryUsername(): Promise<string> {
  try {
    const core = getFlixorCore();
    const token = (core as any).plexToken;
    if (token) {
      const user = await core.plexAuth.getUser(token);
      return user?.username || 'You';
    }
    return 'You';
  } catch {
    return 'You';
  }
}
