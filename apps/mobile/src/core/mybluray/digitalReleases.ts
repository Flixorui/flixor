/**
 * Digital Releases on Details: where to stream, rent or buy a title in the US,
 * from MyBluray's store offers (Apple TV and JustWatch) and, for films,
 * Blu-ray.com's US digital release (its full store list, prices and specs).
 * One pill per store and kind, with official logos from TMDB's watch-provider
 * list (the same ids as JustWatch).
 * macOS reference: WhereToWatchBuilder and StoreLogos in Services/MyBluray/MyBlurayService.swift
 */
import { useEffect, useState } from 'react';
import { currentTmdbApiKey } from '../index';
import { isMyBlurayOn } from './options';
import { normalized } from './plexMatch';
import { getDigitalEdition, getDigitalEditions, getOffers, resolveMovie } from './service';
import type { MBDigitalEdition, MBOffer } from './types';
import type { AppSettings } from '../SettingsData';

export type StoreQuality = '4K' | 'HD' | 'SD';

export interface DigitalStore {
  /** One id per store across sources: apple, amazon, vudu, google-play… */
  id: string;
  name: string;
  /** JustWatch's provider id, which TMDB shares. */
  providerId?: number;
  logo?: string;
  /** True for TMDB's square app icons, which fill the tile; Apple's glyph sits inside it. */
  logoIsIcon?: boolean;
  url?: string;
  price?: number;
  priceText?: string;
  quality?: StoreQuality;
}

export interface DigitalSpec {
  title: string;
  detail?: string;
}

export interface DigitalReleases {
  stream: DigitalStore[];
  rent: DigitalStore[];
  buy: DigitalStore[];
  specs: DigitalSpec[];
}

interface DigitalRelease {
  edition: MBDigitalEdition | null;
  moviesAnywhere: boolean;
}

// MARK: Merging

/** The Apple TV app and iTunes are one store, as are Fandango at Home and Vudu. */
export function canonicalStore(name: string): { id: string; name: string } {
  const lower = name.toLowerCase().trim();
  if (lower.includes('apple tv+') || lower.includes('apple tv plus')) return { id: 'apple-tv-plus', name: 'Apple TV+' };
  if (['itunes', 'apple tv', 'apple tv store', 'apple itunes'].includes(lower)) return { id: 'apple', name: 'Apple TV' };
  if (lower.includes('fandango') || lower === 'vudu') return { id: 'vudu', name: 'Fandango at Home' };
  // "Prime Video" alone is Blu-ray.com's name for Amazon's store ("Amazon Prime Video" is the subscription)
  if (lower === 'amazon' || lower === 'amazon video' || lower === 'prime video') return { id: 'amazon', name: 'Amazon' };
  if (lower === 'comcast' || lower.startsWith('xfinity')) return { id: 'xfinity', name: 'Xfinity' };
  if (lower.startsWith('verizon')) return { id: 'verizon-fios', name: 'Verizon Fios' };
  if (lower.includes('google play') || lower === 'google-play' || lower === 'google tv') return { id: 'google-play', name: 'Google Play' };
  if (lower.includes('microsoft')) return { id: 'microsoft', name: 'Microsoft Store' };
  if (lower === 'youtube') return { id: 'youtube', name: 'YouTube' };
  return { id: lower.replace(/ /g, '-'), name };
}

export function normalizedQuality(raw?: string | null): StoreQuality | undefined {
  if (!raw) return undefined;
  const q = raw.toUpperCase();
  if (q.includes('4K') || q.includes('UHD') || q.includes('2160')) return q.includes('BLURAY') ? undefined : '4K';
  if (q === 'HD' || q.includes('1080') || q.includes('720')) return 'HD';
  if (q === 'SD') return 'SD';
  return undefined;
}

const rank = (q?: StoreQuality) => (q === '4K' ? 3 : q === 'HD' ? 2 : q === 'SD' ? 1 : 0);
const amount = (raw?: string | null) => {
  const n = raw == null ? NaN : Number(raw);
  return Number.isFinite(n) ? n : undefined;
};

/** Keeps the cheapest price per store, and the best quality at that price. */
function merge(store: DigitalStore, into: Map<string, DigitalStore>) {
  const existing = into.get(store.id);
  if (!existing) {
    into.set(store.id, { ...store });
    return;
  }
  existing.url ??= store.url;
  existing.logo ??= store.logo;
  existing.providerId ??= store.providerId;
  const next = store.price;
  const old = existing.price;
  if (next != null && old != null && next < old) {
    Object.assign(existing, { price: next, priceText: store.priceText, quality: store.quality });
  } else if (next != null && old != null && next === old && rank(store.quality) > rank(existing.quality)) {
    existing.quality = store.quality;
  } else if (next != null && old == null) {
    Object.assign(existing, { price: next, priceText: store.priceText, quality: store.quality });
  } else if (next == null && old == null && rank(store.quality) > rank(existing.quality)) {
    existing.quality = store.quality;
  }
}

/** "HBO Max Amazon Channel" is dropped when HBO Max itself is listed. */
function dropChannels(stores: DigitalStore[]): DigitalStore[] {
  const names = new Set(stores.map((s) => s.name.toLowerCase()));
  return stores.filter((store) => {
    const lower = store.name.toLowerCase();
    return ![' amazon channel', ' apple tv channel', ' roku premium channel'].some(
      (suffix) => lower.endsWith(suffix) && names.has(lower.slice(0, -suffix.length))
    );
  });
}

/** Priced stores first (cheapest first), then the big stores, then the rest. */
function sorted(stores: DigitalStore[]): DigitalStore[] {
  const preferred = ['apple', 'amazon', 'google-play', 'vudu', 'microsoft', 'youtube'];
  const index = (id: string) => (preferred.includes(id) ? preferred.indexOf(id) : preferred.length);
  return [...stores].sort((a, b) => {
    if (a.price != null && b.price != null && a.price !== b.price) return a.price - b.price;
    if (a.price != null && b.price == null) return -1;
    if (a.price == null && b.price != null) return 1;
    return index(a.id) - index(b.id) || a.name.localeCompare(b.name);
  });
}

/** Apple's logo glyph, as png: jpg turns its transparency into a white box. */
function appleGlyph(offer: MBOffer): string | undefined {
  const image = offer.provider?.images?.find((i) => i?.kind === 'provider-logo');
  if (!image) return undefined;
  const { urlTemplate, originalWidth: w0, originalHeight: h0 } = image;
  if (urlTemplate && w0 && h0) {
    const w = Math.min(120, w0);
    const h = Math.round((w * h0) / w0);
    return urlTemplate.replace('{w}', String(w)).replace('{h}', String(h)).replace('{f}', 'png');
  }
  return image.url ?? undefined;
}

export function buildDigitalReleases(offers: MBOffer[], digital: DigitalRelease | null): DigitalReleases {
  const stream = new Map<string, DigitalStore>();
  const rent = new Map<string, DigitalStore>();
  const buy = new Map<string, DigitalStore>();
  const logos = new Map<string, string>();

  for (const offer of offers) {
    const name = offer.provider?.name;
    if (!name) continue;
    const quality = normalizedQuality(offer.quality);
    // Discs are covered by Physical Releases
    const raw = (offer.quality ?? '').toUpperCase();
    if (!quality && ['BLURAY', 'DVD', '4K_BLURAY'].includes(raw)) continue;
    if (/dvd|barnes/i.test(name)) continue;
    const { id, name: display } = canonicalStore(name);
    const logo = appleGlyph(offer);
    if (logo && !logos.has(id)) logos.set(id, logo);
    const providerId = offer.provenance?.provider === 'justwatch' ? Number(offer.provider?.id) || undefined : undefined;
    const store: DigitalStore = {
      id, name: display, providerId, logo, url: offer.url ?? undefined,
      price: amount(offer.price?.amount), priceText: offer.priceText ?? undefined, quality,
    };
    switch ((offer.type ?? '').toLowerCase()) {
      case 'rent': merge(store, rent); break;
      case 'buy': merge(store, buy); break;
      case 'subscription': case 'free': case 'ad-supported': case 'free-ad-supported-tv': case 'ads': merge(store, stream); break;
    }
  }

  const specs: DigitalSpec[] = [];
  const edition = digital?.edition;
  if (edition) {
    for (const item of edition.stores ?? []) {
      if (!item?.id || item.id === 'movies-anywhere' || !item.name) continue;
      const { id, name: display } = canonicalStore(item.id === 'itunes' ? 'iTunes' : item.name);
      const cheapest = (edition.prices ?? [])
        .filter((p) => (p.offer ?? '').toLowerCase() === 'buy' && canonicalStore(p.storeName ?? '').id === id)
        .map((p) => ({ value: amount(p.amount), p }))
        .filter((x): x is { value: number; p: typeof x.p } => x.value != null)
        .sort((a, b) => a.value - b.value)[0];
      merge({
        id, name: display, logo: logos.get(id), url: item.url ?? undefined,
        price: cheapest?.value, priceText: cheapest?.p.text ?? undefined, quality: normalizedQuality(cheapest?.p.quality),
      }, buy);
    }
    const video = edition.video;
    if (video) {
      const resolutions = [...(video.resolutions ?? []), ...(video.resolution ? [video.resolution] : [])];
      const is4K = resolutions.some((r) => /4K/i.test(r) || r.includes('2160'));
      const hdr = (video.hdrFormats ?? []).join(' · ');
      if (is4K) specs.push({ title: 'Digital 4K', detail: hdr || undefined });
      else if (hdr) specs.push({ title: hdr });
    }
    if ((edition.audio ?? []).some((a) => /atmos/i.test(a))) specs.push({ title: 'Dolby Atmos' });
  }
  if (digital?.moviesAnywhere) specs.push({ title: 'Movies Anywhere', detail: 'buy once, play in every linked store' });

  // Blu-ray.com stores carry no logo; borrow one from the same store in another kind
  const withLogos = (stores: Map<string, DigitalStore>) =>
    [...stores.values()].map((s) => (s.logo ? s : { ...s, logo: logos.get(s.id) }));
  return {
    stream: sorted(dropChannels(withLogos(stream))),
    rent: sorted(withLogos(rent)),
    buy: sorted(withLogos(buy)),
    specs,
  };
}

export const isEmptyDigital = (d: DigitalReleases) => !d.stream.length && !d.rent.length && !d.buy.length && !d.specs.length;

// MARK: Official logos (TMDB watch providers, US)

const LOGO_ALIASES: Record<string, string[]> = {
  apple: ['Apple TV Store', 'Apple TV'],
  amazon: ['Amazon Video'],
  vudu: ['Fandango At Home'],
  'google-play': ['Google Play Movies'],
  microsoft: ['Microsoft Store'],
  youtube: ['YouTube'],
  xfinity: ['Xfinity Stream'],
  'verizon-fios': ['Verizon On Demand', 'Verizon Fios TV'],
  kaleidescape: ['Kaleidescape'],
};
const logoKey = (name: string) => name.toLowerCase().replace(/[^\p{L}\p{N}]/gu, '');

let logoTable: Promise<{ byId: Map<number, string>; byName: Map<string, string> }> | null = null;

/** TMDB's US watch-provider logos for movies and TV, fetched once per launch (retried if empty). */
function storeLogos() {
  if (!logoTable) {
    logoTable = (async () => {
      const byId = new Map<number, string>();
      const byName = new Map<string, string>();
      const lists = await Promise.all(['movie', 'tv'].map(async (type) => {
        try {
          const res = await fetch(`https://api.themoviedb.org/3/watch/providers/${type}?watch_region=US&api_key=${currentTmdbApiKey()}`);
          return res.ok ? ((await res.json())?.results ?? []) : [];
        } catch {
          return [];
        }
      }));
      for (const p of lists.flat()) {
        if (!p?.logo_path) continue;
        const url = `https://image.tmdb.org/t/p/w92${p.logo_path}`;
        if (!byId.has(p.provider_id)) byId.set(p.provider_id, url);
        if (p.provider_name && !byName.has(logoKey(p.provider_name))) byName.set(logoKey(p.provider_name), url);
      }
      if (!byId.size) logoTable = null;
      return { byId, byName };
    })();
  }
  return logoTable;
}

async function withOfficialLogos(content: DigitalReleases): Promise<DigitalReleases> {
  const { byId, byName } = await storeLogos();
  const resolve = (store: DigitalStore): DigitalStore => {
    const names = [...(LOGO_ALIASES[store.id] ?? []), store.name];
    const official = (store.providerId != null ? byId.get(store.providerId) : undefined)
      ?? names.map((n) => byName.get(logoKey(n))).find(Boolean);
    return official ? { ...store, logo: official, logoIsIcon: true } : store;
  };
  return { ...content, stream: content.stream.map(resolve), rent: content.rent.map(resolve), buy: content.buy.map(resolve) };
}

// MARK: Loading

/** The film's US digital release on Blu-ray.com, and whether it's on Movies Anywhere. */
async function digitalRelease(imdbId: string): Promise<DigitalRelease | null> {
  const movie = await resolveMovie(imdbId).catch(() => null);
  if (!movie?.id) return null;
  const [list, anywhere] = await Promise.all([
    getDigitalEditions(movie.id, 'digital').catch(() => []),
    getDigitalEditions(movie.id, 'movies-anywhere').catch(() => []),
  ]);
  const wanted = normalized(movie.title ?? '');
  const candidates = list.filter((e) => e.country?.code === 'US' && e.bundle !== true && !(e.title ?? '').includes('3D'));
  const pick = candidates.find((e) => normalized(e.title ?? '') === wanted) ?? candidates[0];
  const edition = pick ? await getDigitalEdition(pick.id).catch(() => null) : null;
  const onAnywhere = anywhere.some((e) => e.country?.code === 'US' && e.bundle !== true);
  return edition || onAnywhere ? { edition, moviesAnywhere: onAnywhere } : null;
}

/** Stream, rent and buy options for a title, or null when MyBluray has none. */
export async function loadDigitalReleases(imdbId: string, isMovie: boolean): Promise<DigitalReleases | null> {
  const [offers, digital] = await Promise.all([
    getOffers(imdbId).catch(() => [] as MBOffer[]),
    isMovie ? digitalRelease(imdbId) : Promise.resolve(null),
  ]);
  const merged = buildDigitalReleases(offers, digital);
  if (isEmptyDigital(merged)) return null;
  return withOfficialLogos(merged);
}

/** Digital Releases for a film or show page; null while loading, with no data, or when switched off. */
export function useDigitalReleases(imdbId: string | null | undefined, isMovie: boolean, enabled: boolean, settings: AppSettings) {
  const on = enabled && !!imdbId && isMyBlurayOn('digitalReleases', settings);
  const [data, setData] = useState<DigitalReleases | null>(null);
  useEffect(() => {
    setData(null);
    if (!on || !imdbId) return;
    let cancelled = false;
    loadDigitalReleases(imdbId, isMovie).then((d) => !cancelled && setData(d)).catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, [on, imdbId, isMovie]);
  return on ? data : null;
}
