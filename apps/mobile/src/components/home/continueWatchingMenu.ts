import type { ContinueWatchingEntry } from '../../core/TraktContinueWatching';

export type ContinueWatchingMenuAction = 'info' | 'startOver' | 'markWatched' | 'remove';

interface MenuItem {
  action: ContinueWatchingMenuAction;
  title: string;
  systemIcon: string;
  destructive?: boolean;
}

/** Start Over is left out for cards with no progress to reset. */
export function continueWatchingMenuItems(entry: ContinueWatchingEntry): MenuItem[] {
  return [
    { action: 'info', title: 'Info', systemIcon: 'info.circle' },
    ...(entry.progress > 0
      ? [{ action: 'startOver' as const, title: 'Start Over', systemIcon: 'arrow.counterclockwise' }]
      : []),
    { action: 'markWatched', title: 'Mark as Watched', systemIcon: 'checkmark.circle' },
    { action: 'remove', title: 'Remove', systemIcon: 'trash', destructive: true },
  ];
}

export function continueWatchingEpisodeLabel(entry: ContinueWatchingEntry): string | null {
  if (entry.mediaType !== 'episode' || !entry.seasonNumber || !entry.episodeNumber) return null;
  return `S${entry.seasonNumber}, E${entry.episodeNumber}`;
}

/** Time left, or the percentage when the runtime is unknown. "Up Next" for unstarted episodes. */
export function continueWatchingStatus(entry: ContinueWatchingEntry): string {
  if (entry.isUpNext) return 'Up Next';
  if (!entry.durationMs) return entry.progress > 0 ? `${Math.round(entry.progress)}%` : '';
  const minutes = Math.floor((entry.durationMs - (entry.positionMs || 0)) / 60000);
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest > 0 ? `${hours}h ${rest}m` : `${hours}h`;
}
