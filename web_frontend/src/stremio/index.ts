/**
 * Stremio addon platform contract (package P2). Other packages import from here,
 * so keep these signatures stable.
 */
import * as addons from './addons';
import type { StremioAddon } from './types';

export * from './types';

export { resolveContentIdentity, buildContentKey } from './identity';
export { getStreams, getSubtitles, fetchSubtitleText, prepareStreamForPlayback, streamProxyBase } from './streams';
export { getCatalogs, getCatalogItems, searchCatalogs, catalogDisplayName } from './catalogs';
export { classifyPlayability, hasServerConversion, setServerConversion } from './playability';
export {
  rankStreams,
  rankedPlayable,
  resolutionBucket,
  findBestMatch,
  firstAddonWithPlayable,
  isSameAddonTier,
  NEXT_EPISODE_TIERS,
  type MatchTier,
} from './ranking';
export { addonOrderSettled, findAutomaticSource, type AutoPickAction, type AutoPickOutcome } from './autoPick';
export { getCachedStream, saveCachedStream, removeCachedStream, clearStreamCache } from './streamCache';
export { getResumeState, saveResumeState, clearResumeState, type StreamResumeState } from './resumeStore';
export {
  getLocalHistory,
  getLocalHistoryEntry,
  recordLocalProgress,
  removeLocalHistory,
  clearLocalHistory,
  subscribeLocalHistory,
  isLocallyWatched,
  markLocallyWatched,
  unmarkLocallyWatched,
  type LocalHistoryEntry,
  type LocalHistoryItem,
  type LocalWatchedRef,
} from './localHistory';
export { getNextEpisode, type StreamEpisodeInfo } from './episodes';
export { subscribeAddons, ensureDefaultAddons } from './addons';

/** Installed addons in the user's priority order. */
export async function getInstalledAddons(): Promise<StremioAddon[]> {
  return addons.listInstalledAddons();
}

export async function installAddon(manifestUrl: string): Promise<StremioAddon> {
  return addons.installAddon(manifestUrl);
}

export async function removeAddon(installationId: string): Promise<void> {
  addons.removeAddon(installationId);
}

export async function reorderAddons(installationIds: string[]): Promise<void> {
  addons.reorderAddons(installationIds);
}
