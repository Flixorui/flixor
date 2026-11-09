import { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate, useParams, useSearchParams } from 'react-router-dom';
import BrowseModal from '@/components/BrowseModal';
import DetailsHero from '@/components/DetailsHero';
import EpisodeItem from '@/components/EpisodeItem';
import PersonModal from '@/components/PersonModal';
import Toast from '@/components/Toast';
import TrailerModal from '@/components/TrailerModal';
import VersionPickerModal, { type VersionDetail } from '@/components/VersionPickerModal';
import SourcesSheet from '@/components/stremio/SourcesSheet';
import DetailsAboutSection from '@/components/details/DetailsAboutSection';
import DetailsCastSection, { type DetailsCastMember } from '@/components/details/DetailsCastSection';
import DetailsCollectionSection, { useDetailsCollection } from '@/components/details/DetailsCollectionSection';
import DetailsCommentsSection from '@/components/details/DetailsCommentsSection';
import DetailsEpisodesSection from '@/components/details/DetailsEpisodesSection';
import DetailsMediaRow from '@/components/details/DetailsMediaRow';
import DetailsPersistentBackdrop from '@/components/details/DetailsPersistentBackdrop';
import DetailsSectionsContainer from '@/components/details/DetailsSectionsContainer';
import DetailsTrailersSection from '@/components/details/DetailsTrailersSection';
import AddToTraktList from '@/components/details/AddToTraktList';
import { DetailsRateControl, DetailsWatchedControl } from '@/components/details/DetailsWatchActions';
import { useDetailsData, type DetailsEpisode } from '@/components/details/useDetailsData';
import { useDetailsTitleActions } from '@/components/details/useDetailsTitleActions';
import { streamPlayerId } from '@/player/playerId';
import { markUnwatched, markWatched, WatchStateError } from '@/services/watchState';
import { resolveContentIdentity, type StremioContentIdentity, type StremioContentRef, type StremioStream, type StreamPlayerState } from '@/stremio';
import { loadSettings, useSettings } from '@/state/settings';

function toggleMute() {
  const video = document.getElementById('hero-trailer-video') as HTMLVideoElement | null;
  const setMuted = (window as any).reactSetTrailerMuted as ((value: boolean) => void) | undefined;
  if (video) {
    video.muted = !video.muted;
    setMuted?.(video.muted);
    return;
  }
  const iframe = document.getElementById('hero-trailer-iframe') as HTMLIFrameElement | null;
  if (!iframe?.contentWindow) return;
  const muted = !(window as any)._ytMuted;
  (window as any)._ytMuted = muted;
  iframe.contentWindow.postMessage(JSON.stringify({ event: 'command', func: muted ? 'mute' : 'unMute', args: [] }), '*');
  setMuted?.(muted);
}

function formatRemaining(ms: number): string {
  const minutes = Math.round(ms / 60000);
  return minutes >= 60 ? `Resume · ${Math.floor(minutes / 60)}h ${minutes % 60}m left` : `Resume · ${minutes}m left`;
}

/** The page is keyed by id, so moving to another title starts from clean state. */
export default function Details() {
  const { id } = useParams();
  const decoded = id ? decodeURIComponent(id) : '';
  return decoded ? <DetailsPage key={decoded} id={decoded} /> : null;
}

function DetailsPage({ id }: { id: string }) {
  const nav = useNavigate();
  const settings = useSettings();
  const data = useDetailsData(id);
  const {
    title, overview, backdrop, poster, logoUrl, year, meta, badges, cast, director, moodTags, kind, tech, versions,
    versionDetails, infoVersion, setInfoVersion, setActiveVersion, activeVersion, setAudioTracks, setSubtitleTracks,
    plexMappedId, onDeck, episodes, movieViewOffset, movieDuration, isEpisode, ratings, watchIds, tmdbCtx, imdbId,
    trailers, trailerKey, plexTrailerUrl, trailerMuted, showTrailer, hasCC, hasSDH, hasAD, showTitle, episodeInfo,
    showRatingKey, seasons, related, similar, collectionId, titleTarget, episodeTarget, seasonTarget, numberOfEpisodes,
  } = data;

  const [toast, setToast] = useState('');
  const [showMediaInfo, setShowMediaInfo] = useState(false);
  const [showVersionPicker, setShowVersionPicker] = useState(false);
  const [person, setPerson] = useState<DetailsCastMember | null>(null);
  const [selectedTrailerKey, setSelectedTrailerKey] = useState<string | undefined>(undefined);
  const [sources, setSources] = useState<{ title: string; identity: StremioContentIdentity } | null>(null);

  const collection = useDetailsCollection(kind === 'movie' ? collectionId : undefined);
  const actions = useDetailsTitleActions(titleTarget, { episodeTotal: numberOfEpisodes, onMessage: setToast });

  const hasPlexCopy = id.startsWith('plex:') || !!plexMappedId;
  const canPlayUnmapped = settings.stremioPlaybackEnabled && settings.stremioShowOnTmdbDetails
    && !!(tmdbCtx?.id || imdbId);

  const openDetails = useCallback((target: string) => nav(`/details/${encodeURIComponent(target)}`), [nav]);
  const play = useCallback((target: string, query = '') => nav(`/player/${encodeURIComponent(target)}${query}`), [nav]);

  /** Opens the sheet only once an addon can serve the title, so it's never empty. */
  const openSources = useCallback(async (sheetTitle: string, ref: StremioContentRef) => {
    try {
      const identity = await resolveContentIdentity(ref);
      if (identity) setSources({ title: sheetTitle, identity });
      else setToast('No installed addon can play this title');
    } catch {
      setToast("Couldn't look up sources for this title");
    }
  }, []);

  // Ids are the show's for episodes: tmdbCtx and imdbId always describe the title.
  const contentRef = useCallback((episode?: DetailsEpisode): StremioContentRef => ({
    mediaType: episode ? 'episode' : kind === 'movie' ? 'movie' : 'show',
    imdbId,
    tmdbId: tmdbCtx?.id ? Number(tmdbCtx.id) : undefined,
    seasonNumber: episode?.seasonNumber,
    episodeNumber: episode?.index,
  }), [kind, imdbId, tmdbCtx]);

  const playEpisode = (episode: DetailsEpisode) => {
    if (!episode.id.startsWith('tmdb:')) play(episode.id);
    else if (canPlayUnmapped) openSources(`${title} · ${episode.title}`, contentRef(episode));
  };

  const selectStream = (stream: StremioStream) => {
    if (!sources?.identity) return;
    const state: StreamPlayerState = { stream, identity: sources.identity, title: sources.title };
    setSources(null);
    nav(`/player/${encodeURIComponent(streamPlayerId(sources.identity))}`, { state });
  };

  const playSelected = () => {
    if (kind === 'tv') {
      if (onDeck?.id) { play(onDeck.id); return; }
      const next = episodes.find((episode) => !episode.watched) ?? episodes[0];
      if (next) { playEpisode(next); return; }
    }
    if (!hasPlexCopy) {
      if (canPlayUnmapped) openSources(title, contentRef());
      else if (!settings.stremioPlaybackEnabled) setToast('Turn on Addon playback in Settings › Stremio to play this title');
      else setToast('This title has no TMDB or IMDb id to look up sources');
      return;
    }
    if (versionDetails.length > 1) { setShowVersionPicker(true); return; }
    play(plexMappedId || id, activeVersion ? `?v=${encodeURIComponent(activeVersion)}` : '');
  };

  // `?play=1` (Play on a hover card for a title not in Plex) opens the sources once the
  // title's ids are known.
  const [searchParams, setSearchParams] = useSearchParams();
  const autoPlayReady = !!title && (hasPlexCopy || !!tmdbCtx?.id || !!imdbId) && (kind !== 'tv' || episodes.length > 0 || !!onDeck?.id || !hasPlexCopy);
  useEffect(() => {
    if (searchParams.get('play') !== '1' || !autoPlayReady) return;
    setSearchParams((params) => { params.delete('play'); return params; }, { replace: true });
    playSelected();
    // Runs once per request; playSelected reads the latest render's data.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [searchParams, autoPlayReady]);

  const playWithVersion = (version: VersionDetail) => {
    setShowVersionPicker(false);
    play(plexMappedId || id, `?v=${encodeURIComponent(version.id)}`);
  };

  const toggleEpisodeWatched = async (episode: DetailsEpisode) => {
    try {
      const result = await (episode.watched ? markUnwatched : markWatched)(episodeTarget(episode));
      setToast(result.message);
    } catch (error) {
      setToast(error instanceof WatchStateError ? error.message : "Couldn't update watched status");
    }
  };

  const openPerson = (member: { id?: string; name: string }) => {
    if (member.id) nav(`/person/${encodeURIComponent(member.id)}`);
    else setPerson({ name: member.name });
  };

  const resume = useMemo(() => {
    const resumable = (kind === 'movie' || isEpisode) && !!movieViewOffset && !!movieDuration
      && (movieViewOffset / movieDuration) * 100 < 95;
    if (kind === 'tv' && !isEpisode) {
      const target = onDeck?.id
        || episodes.find((episode) => episode.progress > 0 && episode.progress < 100)?.id
        || episodes.find((episode) => episode.id.startsWith('plex:') && episode.progress < 100)?.id;
      return target ? { target, label: 'Continue Watching' } : null;
    }
    if (resumable) return { target: plexMappedId || id, label: formatRemaining(movieDuration! - movieViewOffset!) };
    return null;
  }, [kind, isEpisode, movieViewOffset, movieDuration, onDeck, episodes, plexMappedId, id]);

  const hdr = (() => {
    const profile = (tech.videoProfile || '').toLowerCase();
    if (profile.includes('dv') || profile.includes('dolby vision')) return 'dolby vision';
    if (profile.includes('hdr10+')) return 'hdr10+';
    if (profile.includes('hdr10') || profile.includes('hdr')) return 'hdr10';
    return profile.includes('hlg') ? 'hlg' : undefined;
  })();

  const seasonOptions = useMemo(
    () => (titleTarget?.kind === 'show' ? seasons.map((season) => ({ key: season.key, title: season.title, target: seasonTarget(season) })) : []),
    [titleTarget?.kind, seasons, seasonTarget],
  );

  useEffect(() => { window.scrollTo(0, 0); }, []);

  const tmdbMedia = tmdbCtx?.id ? `${tmdbCtx.media}:${tmdbCtx.id}` : undefined;

  return (
    <div className="relative isolate min-h-screen">
      <DetailsPersistentBackdrop imageUrl={backdrop || undefined} />
      {toast && <Toast message={toast} onClose={() => setToast('')} />}
      <TrailerModal
        isOpen={!!selectedTrailerKey}
        onClose={() => setSelectedTrailerKey(undefined)}
        youtubeKey={selectedTrailerKey}
        title={title}
      />
      <VersionPickerModal
        open={showVersionPicker}
        onClose={() => setShowVersionPicker(false)}
        title={title}
        versions={versionDetails as VersionDetail[]}
        onSelect={playWithVersion}
      />
      <SourcesSheet
        open={!!sources}
        identity={sources?.identity ?? null}
        title={sources?.title ?? title}
        onClose={() => setSources(null)}
        onSelect={selectStream}
      />

      <div className="relative z-[1]">
        <DetailsHero
          title={title}
          overview={overview}
          backdrop={backdrop}
          poster={poster}
          logo={logoUrl}
          year={year}
          rating={meta.rating}
          runtime={meta.runtime}
          genres={meta.genres}
          badges={badges}
          ratings={ratings}
          cast={cast}
          director={director}
          moodTags={moodTags}
          kind={kind}
          techInfo={{ resolution: tech.resolution, hdr, videoCodec: tech.videoCodec, audioCodec: tech.audioCodec }}
          hasMediaInfo={versions.length > 0}
          onToggleMediaInfo={() => setShowMediaInfo((value) => !value)}
          showMediaInfo={showMediaInfo}
          versionDetails={versionDetails}
          infoVersion={infoVersion}
          onVersionChange={(versionId) => {
            setInfoVersion(versionId);
            setActiveVersion(versionId);
            const version = versionDetails.find((candidate) => candidate.id === versionId);
            if (version) {
              setAudioTracks(version.audios);
              setSubtitleTracks(version.subs);
            }
          }}
          playable={hasPlexCopy || canPlayUnmapped}
          onPlay={playSelected}
          onContinue={resume ? () => play(resume.target) : undefined}
          continueLabel={resume?.label}
          watchlistProps={{ itemId: id, itemType: kind === 'tv' ? 'show' : 'movie', tmdbId: tmdbCtx?.id || watchIds.tmdbId }}
          requestProps={tmdbCtx?.id ? { tmdbId: Number(tmdbCtx.id), mediaType: tmdbCtx.media || 'movie' } : undefined}
          watchActions={(
            <>
              <DetailsWatchedControl actions={actions} seasonOptions={seasonOptions} />
              <DetailsRateControl actions={actions} title={title} />
              <AddToTraktList target={titleTarget} onMessage={setToast} />
            </>
          )}
          onPersonClick={openPerson}
          trailerUrl={plexTrailerUrl}
          trailerKey={trailerKey}
          trailerMuted={trailerMuted}
          showTrailer={showTrailer}
          onToggleMute={toggleMute}
          hasCC={hasCC}
          hasSDH={hasSDH}
          hasAD={hasAD}
          isEpisode={isEpisode}
          showTitle={showTitle}
          episodeInfo={episodeInfo}
          onViewShow={showRatingKey ? () => openDetails(`plex:${showRatingKey}`) : undefined}
        />

        {kind === 'tv' && onDeck && (
          <div className="page-gutter mt-4">
            <div className="overflow-hidden rounded-xl bg-white/5 ring-1 ring-white/10">
              <div className="px-4 py-3 font-semibold text-white/90">Continue watching</div>
              <div className="px-3 pb-3">
                <EpisodeItem ep={onDeck} onClick={(episodeId) => play(episodeId)} />
              </div>
            </div>
          </div>
        )}

        <DetailsSectionsContainer
          initialKey={seasons.length > 0 ? 'episodes' : 'suggested'}
          sections={{
            episodes: {
              available: seasons.length > 0,
              count: episodes.length || undefined,
              render: () => (
                <DetailsEpisodesSection data={data} onPlay={playEpisode} onToggleWatched={toggleEpisodeWatched} canPlayUnmapped={canPlayUnmapped} />
              ),
            },
            suggested: {
              available: settings.showRelatedContent && (related.length > 0 || similar.length > 0),
              render: () => (
                <div className="space-y-10">
                  <DetailsMediaRow title="Recommendations" items={related} browseKey={tmdbMedia ? `tmdb:recs:${tmdbMedia}` : undefined} onSelect={openDetails} />
                  <DetailsMediaRow title="More Like This" items={similar} browseKey={tmdbMedia ? `tmdb:similar:${tmdbMedia}` : undefined} onSelect={openDetails} />
                </div>
              ),
            },
            collection: {
              available: !!collection,
              render: () => collection && (
                <DetailsCollectionSection collection={collection} currentMovieId={tmdbCtx?.id} onSelect={openDetails} />
              ),
            },
            cast: {
              available: settings.showCastCrew && cast.length > 0,
              render: () => <DetailsCastSection cast={cast} onSelect={openPerson} />,
            },
            trailers: {
              available: trailers.length > 0,
              render: () => <DetailsTrailersSection trailers={trailers} onSelect={(trailer) => setSelectedTrailerKey(trailer.key)} />,
            },
            comments: {
              available: !!titleTarget,
              render: () => <DetailsCommentsSection target={titleTarget} />,
            },
            about: {
              available: true,
              render: () => <DetailsAboutSection data={data} />,
            },
          }}
        />
      </div>

      <PersonModal open={!!person} onClose={() => setPerson(null)} name={person?.name} tmdbKey={loadSettings().tmdbBearer} />
      <BrowseModal />
    </div>
  );
}
