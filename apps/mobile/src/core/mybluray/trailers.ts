/**
 * Trailers: Apple TV first (direct HLS from MyBluray, up to 4K HDR, no
 * YouTube involved), then TMDB's YouTube trailers. Each Apple trailer carries
 * the best YouTube trailer as its fallback if its stream fails.
 * macOS reference: Services/TrailerService.swift, Services/Trailers/TrailerPlayer.swift
 *
 * Unlike macOS, the stream isn't rewritten to SDR / 1080p: AVPlayer on iOS
 * won't open a rewritten local master playlist (it stalls without an error),
 * picks the variant for the screen itself, and shows HDR correctly.
 */
import type { AppSettings } from '../SettingsData';
import { isMyBlurayOn } from './options';
import type { MBTitle } from './types';

export interface MergedTrailer {
  key: string;
  name: string;
  site: string;
  type: string;
  official?: boolean;
  publishedAt?: string;
  /** Apple's HLS stream; absent for YouTube trailers. */
  streamUrl?: string;
  thumbnailUrl?: string;
  durationSeconds?: number;
  /** YouTube key to play if the stream fails. */
  fallbackYouTubeKey?: string;
}

function typeRank(type?: string): number {
  switch ((type ?? '').toLowerCase()) {
    case 'trailer': return 0;
    case 'teaser': return 1;
    case 'clip': return 2;
    case 'featurette': return 3;
    case 'behind the scenes': return 4;
    default: return 5;
  }
}

/** Apple's direct HLS videos, one per URL and per cut (Apple can list one trailer under two products). */
function directAppleVideos(title: MBTitle) {
  const urls = new Set<string>();
  const cuts = new Set<string>();
  return title.videos.filter((v) => {
    if (v.host !== 'apple-tv' || v.playback !== 'direct-hls' || !v.playbackUrl || urls.has(v.playbackUrl)) return false;
    urls.add(v.playbackUrl);
    if (v.durationSeconds != null) {
      const cut = `${v.kind ?? ''}:${v.durationSeconds.toFixed(2)}`;
      if (cuts.has(cut)) return false;
      cuts.add(cut);
    }
    return true;
  });
}

export function appleTrailers(title: MBTitle | null, includeBonus: boolean): MergedTrailer[] {
  if (!title) return [];
  const ranked = directAppleVideos(title).flatMap((v, offset) => {
    const kind = (v.kind ?? 'trailer').toLowerCase();
    const label = (v.title ?? '').trim();
    // Apple names some trailers after the film, and labels some teasers as trailers
    const type = label.toLowerCase() === 'teaser' ? 'Teaser' : kind[0].toUpperCase() + kind.slice(1);
    const rank = typeRank(type);
    if (!includeBonus && rank > 1) return [];
    const name = !label || label.toLowerCase() === (title.title ?? '').toLowerCase() ? type : label;
    const id = v.providerId ?? v.playbackUrl!;
    return [{
      rank,
      offset,
      trailer: {
        key: `apple:${id}`,
        name,
        site: 'Apple TV',
        type,
        official: true,
        streamUrl: v.playbackUrl!,
        thumbnailUrl: v.thumbnailUrl ?? undefined,
        durationSeconds: v.durationSeconds ?? undefined,
      } as MergedTrailer,
    }];
  });
  // Trailers before teasers before bonus videos; Apple's order within each
  return ranked.sort((a, b) => a.rank - b.rank || a.offset - b.offset).map((r) => r.trailer);
}

/** Apple trailers ahead of YouTube ones, each with the best YouTube trailer as its fallback. */
export function mergeTrailers(title: MBTitle | null, youtube: MergedTrailer[], settings: AppSettings): MergedTrailer[] {
  if (!isMyBlurayOn('appleTrailers', settings)) return youtube;
  const apple = appleTrailers(title, isMyBlurayOn('bonusVideos', settings));
  const fallback = youtube.find((t) => t.site?.toLowerCase() === 'youtube' && t.type === 'Trailer')?.key ?? youtube[0]?.key;
  return [...apple.map((t) => ({ ...t, fallbackYouTubeKey: fallback })), ...youtube];
}

export function formatDuration(seconds?: number): string | undefined {
  if (!seconds || seconds <= 0) return undefined;
  const s = Math.round(seconds);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}
