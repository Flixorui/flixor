import { useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import Row from '@/components/Row';
import SkeletonRow from '@/components/SkeletonRow';
import { resolvePlayRoute } from '@/components/cards/cardMedia';
import { appToast } from '@/components/cards/cardActions';
import type { CardItem, CardMenuAction } from '@/components/cards/cardTypes';
import { markWatched, removeFromContinueWatching, startOver } from '@/services/watchState';
import type { ContinueWatchingItem } from '@/services/continueWatching';
import { useContinueWatching } from './useContinueWatching';
import { HomeRowErrorCard } from './HomeRowView';

function toCardItem(item: ContinueWatchingItem): CardItem {
  return {
    id: item.id,
    title: item.title,
    subtitle: item.subtitle,
    image: item.image,
    progress: Math.round(item.progress * 100),
    viewOffset: item.positionMs,
    duration: item.durationMs,
    isNextUp: item.isNextUp,
    target: item.target,
    mediaType: item.target.kind,
  };
}

export default function ContinueWatchingRow({
  title,
  continueWatching,
  onOpen,
}: {
  title: string;
  continueWatching: ReturnType<typeof useContinueWatching>;
  onOpen: (item: CardItem) => void;
}) {
  const nav = useNavigate();
  const { items, status, error, retry, refresh, removeOptimistically } = continueWatching;
  const cards = useMemo(() => items.map(toCardItem), [items]);

  const mutate = async (item: CardItem, change: () => Promise<{ message: string }>) => {
    const restore = removeOptimistically(item.id);
    try {
      appToast((await change()).message);
      refresh();
    } catch (error: any) {
      restore();
      appToast(error?.message || `Could not update ${item.title}`);
    }
  };

  const menuActions = (item: CardItem): CardMenuAction[] => {
    const target = item.target!;
    const resume = async () => nav(await resolvePlayRoute(item.id, item.mediaType));
    const actions: CardMenuAction[] = [{ label: item.isNextUp ? 'Play' : 'Resume', onSelect: resume }];
    if ((item.progress ?? 0) > 0) {
      actions.push({
        label: 'Start Over',
        onSelect: async () => {
          try {
            await startOver(target);
            await resume();
          } catch (error: any) {
            appToast(error?.message || `Could not start ${item.title} over`);
          }
        },
      });
    }
    actions.push(
      { label: 'Mark as Watched', onSelect: () => mutate(item, () => markWatched(target)) },
      { label: 'Remove from Continue Watching', danger: true, onSelect: () => mutate(item, () => removeFromContinueWatching(target)) },
    );
    return actions;
  };

  if (status === 'empty') return null;
  if (status === 'loading') return <SkeletonRow title={title} />;
  if (status === 'error') {
    return <HomeRowErrorCard title={title} source="Continue Watching" message={error || 'Could not load this row'} onRetry={retry} />;
  }
  return <Row title={title} items={cards} variant="continue" onItemClick={(_id, item) => onOpen(item)} menuActions={menuActions} />;
}
