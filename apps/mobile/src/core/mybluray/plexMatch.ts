/**
 * The Plex movie for a disc, by title and year. Blu-ray.com titles carry
 * extras like "4K" or "(Steelbook)" and no IMDb id.
 * macOS reference: PlexDiscMatcher in Views/Library/PhysicalCollectionView.swift
 */
import { getFlixorCore } from '../index';

/** "The Dark Knight 4K (Steelbook)" → "The Dark Knight". */
export function cleanedDiscTitle(title: string): string {
  let text = title;
  const open = text.indexOf('(');
  if (open >= 0) text = text.slice(0, open);
  text = text.trim();
  for (const suffix of [' 4K', ' 3D', ' Blu-ray', ' Ultra HD']) {
    if (text.endsWith(suffix)) text = text.slice(0, -suffix.length);
  }
  return text.trim();
}

function normalized(title: string): string {
  let text = title.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
  if (text.startsWith('the ')) text = text.slice(4);
  return text.replace(/[^\p{L}\p{N}]/gu, '');
}

export async function matchPlexMovie(rawTitle?: string | null, year?: number | null): Promise<{ ratingKey: string; title: string } | null> {
  const title = cleanedDiscTitle(rawTitle ?? '');
  if (!title) return null;
  try {
    const hits: any[] = await getFlixorCore().plexServer.search(title, 1);
    const wanted = normalized(title);
    const best = hits.find((hit) => {
      if (normalized(String(hit?.title ?? '')) !== wanted) return false;
      if (!year || !hit?.year) return true;
      return Math.abs(Number(hit.year) - year) <= 1;
    });
    return best ? { ratingKey: String(best.ratingKey), title: String(best.title ?? title) } : null;
  } catch {
    return null;
  }
}
