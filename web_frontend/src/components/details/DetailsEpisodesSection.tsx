import { useState } from 'react';
import EpisodeItem from '@/components/EpisodeItem';
import EpisodeLandscapeCard from '@/components/EpisodeLandscapeCard';
import EpisodeSkeletonList from '@/components/EpisodeSkeletonList';
import SeasonSelector from '@/components/SeasonSelector';
import { useSettings } from '@/state/settings';
import DetailsSectionHeading, { DetailsHorizontalRow } from './DetailsSectionHeading';
import type { DetailsEpisode, useDetailsData } from './useDetailsData';

export default function DetailsEpisodesSection({
  data,
  onPlay,
  onToggleWatched,
  canPlayUnmapped,
}: {
  data: ReturnType<typeof useDetailsData>;
  onPlay: (episode: DetailsEpisode) => void;
  onToggleWatched: (episode: DetailsEpisode) => void;
  /** TMDB-only episodes can be played through addons. */
  canPlayUnmapped: boolean;
}) {
  const settings = useSettings();
  const { seasons, seasonKey, setSeasonKey, episodes, episodesLoading, badges } = data;
  const [revealed, setRevealed] = useState<Set<string>>(new Set());

  if (!seasons.length) return null;

  const horizontal = settings.episodeLayout === 'horizontal';
  const emptyText = badges.includes('No local source') ? 'No source found' : 'No episodes found';

  const rowProps = (episode: DetailsEpisode) => {
    const spoilerHidden = settings.detailsHideEpisodeSpoilers && !episode.watched && !revealed.has(episode.id);
    return {
      ep: { ...episode, rating: settings.detailsShowEpisodeRatings ? episode.rating : undefined },
      onClick: () => onPlay(episode),
      disabled: episode.id.startsWith('tmdb:') && !canPlayUnmapped,
      spoilerHidden,
      onReveal: () => setRevealed((current) => new Set(current).add(episode.id)),
      onToggleWatched: () => onToggleWatched(episode),
    };
  };

  return (
    <section>
      <DetailsSectionHeading className="mb-4">Episodes</DetailsSectionHeading>
      <div className="pr-[var(--page-gutter)]">
        <SeasonSelector seasons={seasons} seasonKey={seasonKey} onChange={setSeasonKey} variant={settings.detailsSeasonPickerStyle} />
      </div>

      {horizontal ? (
        <div className="mt-4">
          <DetailsHorizontalRow gapClass="gap-4">
            {episodesLoading && !episodes.length ? (
              Array.from({ length: 5 }).map((_, index) => (
                <div key={index} className="aspect-[16/10] w-[300px] flex-shrink-0 animate-pulse rounded-xl bg-white/10 md:w-[420px]" />
              ))
            ) : episodes.length ? (
              episodes.map((episode) => <EpisodeLandscapeCard key={episode.id} {...rowProps(episode)} />)
            ) : (
              <div className="py-8 text-white/60">{emptyText}</div>
            )}
          </DetailsHorizontalRow>
        </div>
      ) : (
        <div className="mt-4 space-y-4 pr-[var(--page-gutter)]">
          {episodesLoading && !episodes.length ? (
            <EpisodeSkeletonList />
          ) : episodes.length ? (
            episodes.map((episode) => <EpisodeItem key={episode.id} {...rowProps(episode)} />)
          ) : (
            <div className="py-10 text-center text-white/60">{emptyText}</div>
          )}
        </div>
      )}
    </section>
  );
}
