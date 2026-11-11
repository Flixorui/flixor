/**
 * Person page data: TMDB details, external links and combined credits, shaped the way the
 * macOS Person page uses them.
 * macOS reference: Views/Person/PersonDetailViewModel.swift and FlixorKit TMDBPersonProfile
 */

import type { TMDBPersonCreditItem } from '@flixor/core';
import { getFlixorCore } from './index';

export type PersonDepartment = 'acting' | 'crew';
export type PersonMediaFilter = 'all' | 'movies' | 'tv';
export type PersonCreditOrder = 'popularity' | 'newest' | 'oldest';

export interface PersonCreditEntry {
  /** "tmdb:movie:<id>" or "tmdb:tv:<id>", the id format Details uses. */
  key: string;
  id: number;
  mediaType: 'movie' | 'tv';
  title: string;
  posterUrl?: string;
  backdropUrl?: string;
  /** "YYYY-MM-DD" or undefined when unknown. */
  date?: string;
  character?: string;
  job?: string;
  department?: string;
  episodeCount?: number;
  genreIds: number[];
  popularity: number;
  voteCount: number;
}

export interface PersonProfile {
  id: number;
  name: string;
  biography?: string;
  birthday?: string;
  deathday?: string;
  placeOfBirth?: string;
  profileUrl?: string;
  profilePath?: string;
  knownForDepartment?: string;
  imdbId?: string;
  instagramId?: string;
  homepage?: string;
  cast: PersonCreditEntry[];
  crew: PersonCreditEntry[];
}

/** Merges TMDB's one-row-per-character (or job) into one entry per title. */
function dedupe(items: TMDBPersonCreditItem[], field: 'character' | 'job'): PersonCreditEntry[] {
  const core = getFlixorCore();
  const order: string[] = [];
  const merged = new Map<string, PersonCreditEntry>();
  for (const item of items) {
    if (item.media_type !== 'movie' && item.media_type !== 'tv') continue;
    const key = `tmdb:${item.media_type}:${item.id}`;
    const value = String(item[field] || '').trim();
    const existing = merged.get(key);
    if (existing) {
      const current = existing[field];
      if (value && !current?.split(', ').includes(value)) existing[field] = current ? `${current}, ${value}` : value;
      existing.episodeCount = (existing.episodeCount || 0) + (item.episode_count || 0) || undefined;
      continue;
    }
    order.push(key);
    merged.set(key, {
      key,
      id: item.id,
      mediaType: item.media_type,
      title: item.title || item.name || 'Untitled',
      posterUrl: item.poster_path ? core.tmdb.getPosterUrl(item.poster_path, 'w342') : undefined,
      backdropUrl: item.backdrop_path ? core.tmdb.getBackdropUrl(item.backdrop_path, 'w1280') : undefined,
      date: item.release_date || item.first_air_date || undefined,
      character: field === 'character' ? value || undefined : undefined,
      job: field === 'job' ? value || undefined : undefined,
      department: item.department,
      episodeCount: item.episode_count || undefined,
      genreIds: item.genre_ids ?? [],
      popularity: item.popularity ?? 0,
      voteCount: item.vote_count ?? 0,
    });
  }
  return order.map((key) => merged.get(key)!);
}

export async function fetchPersonProfile(personId: number): Promise<PersonProfile> {
  const core = getFlixorCore();
  const [person, credits, externalIds] = await Promise.all([
    core.tmdb.getPersonDetails(personId),
    core.tmdb.getPersonCredits(personId),
    core.tmdb.getPersonExternalIds(personId).catch(() => null),
  ]);
  return {
    id: person.id,
    name: person.name,
    biography: person.biography?.trim() || undefined,
    birthday: person.birthday || undefined,
    deathday: person.deathday || undefined,
    placeOfBirth: person.place_of_birth || undefined,
    profilePath: person.profile_path || undefined,
    profileUrl: person.profile_path ? core.tmdb.getProfileUrl(person.profile_path, 'h632') : undefined,
    knownForDepartment: person.known_for_department || undefined,
    imdbId: externalIds?.imdb_id || person.imdb_id || undefined,
    instagramId: externalIds?.instagram_id || undefined,
    homepage: person.homepage || undefined,
    cast: dedupe(credits.cast ?? [], 'character'),
    crew: dedupe(credits.crew ?? [], 'job'),
  };
}

/** Popular: by popularity then votes. Newest: undated (upcoming) first. Oldest: undated last. */
export function sortCredits(credits: PersonCreditEntry[], order: PersonCreditOrder): PersonCreditEntry[] {
  return [...credits].sort((a, b) => {
    if (order === 'popularity') {
      return b.popularity - a.popularity || b.voteCount - a.voteCount;
    }
    if (!a.date || !b.date) {
      if (!a.date && !b.date) return 0;
      const undatedFirst = order === 'newest';
      return !a.date ? (undatedFirst ? -1 : 1) : undatedFirst ? 1 : -1;
    }
    return order === 'newest' ? b.date.localeCompare(a.date) : a.date.localeCompare(b.date);
  });
}

export function filterCredits(credits: PersonCreditEntry[], filter: PersonMediaFilter): PersonCreditEntry[] {
  if (filter === 'all') return credits;
  return credits.filter((c) => (filter === 'tv' ? c.mediaType === 'tv' : c.mediaType === 'movie'));
}

/** The tab a person opens on: crew for directors and writers, acting otherwise. */
export function defaultDepartment(profile: PersonProfile): PersonDepartment {
  const prefersCrew = (profile.knownForDepartment ?? 'Acting') !== 'Acting';
  if (prefersCrew && profile.crew.length) return 'crew';
  if (!profile.cast.length && profile.crew.length) return 'crew';
  return 'acting';
}

/** Talk shows, news and reality ("Self") crowd out the roles people are known for. */
const NON_FICTION_GENRES = new Set([10763, 10764, 10767]);

/** Up to 12 titles with posters, ranked by vote count (lasting recognition), as on macOS. */
export function knownForCredits(profile: PersonProfile): { department: PersonDepartment; credits: PersonCreditEntry[] } {
  const prefersCrew = (profile.knownForDepartment ?? 'Acting') !== 'Acting';
  const department: PersonDepartment = prefersCrew
    ? profile.crew.length ? 'crew' : 'acting'
    : profile.cast.length ? 'acting' : 'crew';
  const source = department === 'crew' ? profile.crew : profile.cast;
  const credits = source
    .filter((c) => {
      if (!c.posterUrl) return false;
      if (c.genreIds.some((g) => NON_FICTION_GENRES.has(g))) return false;
      const role = (c.character || '').toLowerCase();
      return !(role === 'self' || role.startsWith('self ') || role.startsWith('himself') || role.startsWith('herself'));
    })
    .sort((a, b) => b.voteCount - a.voteCount)
    .slice(0, 12);
  return { department, credits };
}

/** "Raleigh Becket" or "Jax Teller · 92 eps" (acting), "Director" (crew). */
export function creditSubtitle(credit: PersonCreditEntry, department: PersonDepartment): string | undefined {
  const parts: string[] = [];
  const role = department === 'acting' ? credit.character : credit.job || credit.department;
  if (role) parts.push(role);
  if (credit.mediaType === 'tv' && credit.episodeCount) parts.push(credit.episodeCount === 1 ? '1 ep' : `${credit.episodeCount} eps`);
  return parts.length ? parts.join(' · ') : undefined;
}

/** "34 movies · 21 shows", counting each title once across cast and crew. */
export function creditSummary(profile: PersonProfile): string | undefined {
  const keys = new Set([...profile.cast, ...profile.crew].map((c) => c.key));
  const shows = [...keys].filter((k) => k.startsWith('tmdb:tv:')).length;
  const movies = keys.size - shows;
  const parts: string[] = [];
  if (movies) parts.push(`${movies} ${movies === 1 ? 'movie' : 'movies'}`);
  if (shows) parts.push(`${shows} ${shows === 1 ? 'show' : 'shows'}`);
  return parts.length ? parts.join(' · ') : undefined;
}

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/** Parses "YYYY-MM-DD" as a calendar date, so no time zone can move it to the day before. */
function calendarDate(value?: string): { y: number; m: number; d: number } | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value || '');
  return match ? { y: Number(match[1]), m: Number(match[2]), d: Number(match[3]) } : null;
}

/** "April 10, 1980". */
export function formatPersonDate(value?: string): string | undefined {
  const date = calendarDate(value);
  return date ? `${MONTHS[date.m - 1]} ${date.d}, ${date.y}` : undefined;
}

/** Whole years between two calendar dates; `to` defaults to today. */
export function ageInYears(from?: string, to?: string): number | undefined {
  const start = calendarDate(from);
  if (!start) return undefined;
  const now = new Date();
  const end = calendarDate(to) ?? { y: now.getFullYear(), m: now.getMonth() + 1, d: now.getDate() };
  let age = end.y - start.y;
  if (end.m < start.m || (end.m === start.m && end.d < start.d)) age -= 1;
  return age >= 0 ? age : undefined;
}
