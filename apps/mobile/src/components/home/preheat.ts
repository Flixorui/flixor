import { InteractionManager } from 'react-native';
import FastImage from '@d11/react-native-fast-image';
import { IMAGE_PRELOAD_CAP } from '../../core/PerformanceConfig';

const MAX_TRACKED_URLS = 400;
const preheated = new Set<string>();

/** Starts downloading artwork about to be shown, at most IMAGE_PRELOAD_CAP new images per call. */
export function preheatArtwork(uris: Array<string | undefined>): void {
  if (preheated.size > MAX_TRACKED_URLS) preheated.clear();
  const fresh: string[] = [];
  for (const uri of uris) {
    if (fresh.length >= IMAGE_PRELOAD_CAP) break;
    if (!uri || preheated.has(uri)) continue;
    preheated.add(uri);
    fresh.push(uri);
  }
  if (fresh.length === 0) return;
  InteractionManager.runAfterInteractions(() => {
    FastImage.preload(
      fresh.map((uri) => ({ uri, priority: FastImage.priority.normal, cache: FastImage.cacheControl.immutable }))
    );
  });
}
