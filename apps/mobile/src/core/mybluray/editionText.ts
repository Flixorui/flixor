/** Text for Blu-ray.com editions, shared by Details, the edition page and Library. */
import type { MBEditionSummary } from './types';
import { isUHD } from './collectionStore';

/**
 * The edition's own name: "Bat-Pod Display Case | Limited Edition" from
 * "The Dark Knight (Bat-Pod Display Case | Limited Edition)", else the title
 * (which may say "4K"), else "Standard Edition".
 */
export function editionName(e: Pick<MBEditionSummary, 'title'>): string {
  const raw = e.title ?? '';
  const open = raw.indexOf('(');
  if (open >= 0 && raw.endsWith(')')) {
    const inner = raw.slice(open + 1, -1).trim();
    if (inner) return inner;
  }
  return raw || 'Standard Edition';
}

/** The film's title without the edition: "The Dark Knight Trilogy 4K". */
export function baseTitle(e: Pick<MBEditionSummary, 'title'>): string {
  const raw = e.title ?? '';
  const open = raw.indexOf('(');
  return open >= 0 ? raw.slice(0, open).trim() : raw;
}

export function formatName(e: Pick<MBEditionSummary, 'format' | 'title'>): string {
  return isUHD(e) ? '4K' : 'Blu-ray';
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/**
 * "Dec 19, 2017". A release date is a day, not a moment: it's shown as given,
 * never moved into the local time zone (which turned Dec 19 into Dec 18 in the US).
 */
export function releaseDateText(date?: string | null): string | undefined {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(date ?? '');
  if (!m) return undefined;
  const month = MONTHS[Number(m[2]) - 1];
  return month ? `${month} ${Number(m[3])}, ${m[1]}` : undefined;
}

/** "4K · Dec 19, 2017 · GB · Box set" */
export function editionCaption(e: MBEditionSummary, showsCountry: boolean): string {
  const parts = [formatName(e)];
  const date = releaseDateText(e.releaseDate);
  if (date) parts.push(date);
  if (showsCountry && e.country?.code) parts.push(e.country.code);
  if (e.bundle) parts.push('Box set');
  return parts.join(' · ');
}
