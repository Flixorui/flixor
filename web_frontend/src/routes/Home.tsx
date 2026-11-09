import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import BrowseModal from '@/components/BrowseModal';
import HeroCarousel from '@/components/HeroCarousel';
import HomeHero from '@/components/HomeHero';
import SectionBanner from '@/components/SectionBanner';
import UltraBlurBackground from '@/components/UltraBlurBackground';
import { appToast } from '@/components/cards/cardActions';
import { detailsPath, resolveDetailsId, resolvePlayRoute } from '@/components/cards/cardMedia';
import type { CardItem } from '@/components/cards/cardTypes';
import ContinueWatchingRow from '@/components/home/ContinueWatchingRow';
import HomeRowView from '@/components/home/HomeRowView';
import { heroMetadata, heroTrailer, resolveHeroItems, type HeroMetadata } from '@/components/home/heroData';
import type { HomeRowSpec } from '@/components/home/rowSpecs';
import { useContinueWatching } from '@/components/home/useContinueWatching';
import { useHomeRowSpecs } from '@/components/home/useHomeRowSpecs';
import { apiClient, checkAuth } from '@/services/api';
import {
  CONTINUE_WATCHING_ROW_ID,
  homeRowTitle,
  orderHomeRows,
  registerHomeRows,
  type HomeRowDescriptor,
} from '@/state/homeRows';
import { loadSettings, saveSettings, useSettings } from '@/state/settings';

type DisplayRow =
  | { kind: 'continue'; id: string; title: string }
  | { kind: 'row'; id: string; title: string; caption?: string; spec: HomeRowSpec };

function descriptor(spec: HomeRowSpec): HomeRowDescriptor {
  return { id: spec.id, defaultTitle: spec.defaultTitle, kind: spec.kind, group: spec.group, detail: spec.detail };
}

export default function Home() {
  const nav = useNavigate();
  const settings = useSettings();
  const [ready, setReady] = useState(false);
  const [emptyRows, setEmptyRows] = useState<ReadonlySet<string>>(new Set());
  const [heroItems, setHeroItems] = useState<CardItem[] | null>(null);
  const [activeBackdrop, setActiveBackdrop] = useState<string | undefined>(undefined);

  const showContinue = settings.showContinueWatchingRow !== false;
  const continueWatching = useContinueWatching(ready && showContinue);
  const { specs, enabledSpecs, groups, connected } = useHomeRowSpecs(ready);

  useEffect(() => {
    let alive = true;
    (async () => {
      if (!(await checkAuth())) {
        nav('/login');
        return;
      }
      try {
        const servers: any[] = await apiClient.getServers();
        const current = loadSettings().plexServer;
        const server = servers.find((candidate) => candidate.clientIdentifier === current?.clientIdentifier) || servers[0];
        if (server && (server.clientIdentifier !== current?.clientIdentifier || server.baseUrl !== current?.baseUrl)) {
          saveSettings({
            plexBaseUrl: server.baseUrl,
            plexToken: server.token,
            plexServer: {
              name: server.name,
              clientIdentifier: server.clientIdentifier,
              baseUrl: server.baseUrl,
              token: server.token,
            },
          });
        }
      } catch (err) {
        console.error('Failed to get servers:', err);
      }
      // TMDB requests go through the backend, which holds the key. Screens still
      // check for this value before they ask for TMDB data.
      if (!loadSettings().tmdbBearer) saveSettings({ tmdbBearer: 'backend-proxy' });
      if (alive) setReady(true);
    })();
    return () => {
      alive = false;
    };
  }, [nav]);

  useEffect(() => {
    const handler = () => window.location.reload();
    window.addEventListener('plex-server-changed', handler);
    return () => window.removeEventListener('plex-server-changed', handler);
  }, []);

  // Tell Rows Settings which rows exist, once each group's list is known.
  useEffect(() => {
    if (!ready) return;
    registerHomeRows(
      showContinue
        ? [{ id: CONTINUE_WATCHING_ROW_ID, defaultTitle: 'Continue Watching', kind: 'continueWatching', group: 'continueWatching' }]
        : [],
      'continueWatching',
    );
  }, [ready, showContinue]);

  useEffect(() => {
    if (!ready) return;
    const usable = (list: HomeRowSpec[]) =>
      enabledSpecs.filter((spec) => list.includes(spec) && !spec.placeholder && !emptyRows.has(spec.id)).map(descriptor);
    if (groups.settled.recentlyAdded) registerHomeRows(usable(groups.recentlyAdded), 'recentlyAdded');
    if (groups.settled.collections) registerHomeRows(usable(groups.collections), 'collections');
    if (groups.settled.extras) registerHomeRows(usable(groups.extras), 'extras');
  }, [ready, groups, enabledSpecs, emptyRows]);

  const onEmpty = useCallback((id: string) => {
    setEmptyRows((current) => (current.has(id) ? current : new Set(current).add(id)));
  }, []);

  const continueCards = useMemo<CardItem[]>(
    () =>
      continueWatching.items.map((item) => ({
        id: item.id,
        title: item.title,
        image: item.image,
        mediaType: item.target.kind,
      })),
    [continueWatching.items],
  );
  const continueSettled = !showContinue || continueWatching.status !== 'loading';

  // Choose the hero once its inputs settle; background refreshes must not swap it.
  const heroKey = useRef<string | null>(null);
  const heroSource = settings.homeHeroSource;
  const heroWanted = settings.showHeroSection !== false;
  const allSettled = groups.settled.recentlyAdded && groups.settled.collections && continueSettled;
  useEffect(() => {
    if (!ready || !heroWanted || !allSettled) return;
    const key = `${heroSource}|${settings.discoveryDisabled === true}`;
    if (heroKey.current === key) return;
    let alive = true;
    resolveHeroItems(heroSource, specs, continueCards).then((items) => {
      if (!alive) return;
      heroKey.current = key;
      setHeroItems(items);
    });
    return () => {
      alive = false;
    };
    // specs and continueCards are read at the moment the hero is chosen.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ready, heroWanted, allSettled, heroSource, settings.discoveryDisabled]);

  const openItem = useCallback(
    async (item: CardItem) => {
      const id = await resolveDetailsId(item);
      if (id) nav(detailsPath(id));
      else appToast(`Could not find details for ${item.title}`);
    },
    [nav],
  );

  const displayRows = useMemo<DisplayRow[]>(() => {
    const titles = settings.homeRowTitles;
    const hidden = new Set(settings.homeRowHidden);
    const rows: Array<DisplayRow & { placeholder?: boolean }> = [];
    if (showContinue && continueWatching.status !== 'empty') {
      rows.push({
        kind: 'continue',
        id: CONTINUE_WATCHING_ROW_ID,
        title: homeRowTitle(titles, CONTINUE_WATCHING_ROW_ID, 'Continue Watching'),
      });
    }
    for (const spec of enabledSpecs) {
      if (emptyRows.has(spec.id)) continue;
      rows.push({
        kind: 'row',
        id: spec.id,
        title: spec.placeholder ? '' : homeRowTitle(titles, spec.id, spec.defaultTitle),
        spec,
        placeholder: spec.placeholder,
      });
    }
    const ordered = orderHomeRows(
      rows.filter((row) => row.placeholder || !hidden.has(row.id)),
      (row) => row.id,
      settings.homeRowOrder,
    );

    // Rows with the same title get the addon name beside them.
    const counts = new Map<string, number>();
    ordered.forEach((row) => counts.set(row.title.trim().toLowerCase(), (counts.get(row.title.trim().toLowerCase()) ?? 0) + 1));
    return ordered.map((row) =>
      row.kind === 'row' && row.spec.kind === 'stremioCatalog' && (counts.get(row.title.trim().toLowerCase()) ?? 0) > 1
        ? { ...row, caption: row.spec.detail }
        : row,
    );
  }, [enabledSpecs, emptyRows, settings.homeRowTitles, settings.homeRowHidden, settings.homeRowOrder, showContinue, continueWatching.status]);

  const layout = settings.heroLayout || 'carousel';
  const isCarousel = layout === 'carousel';

  return (
    <UltraBlurBackground imageUrl={activeBackdrop} className="min-h-screen pb-10">
      {!(heroWanted && isCarousel && heroItems?.length) && <div className="pt-20" />}
      {heroWanted &&
        (heroItems === null ? (
          <div className="bleed" style={{ padding: '20px' }}>
            <div className="rounded-2xl overflow-hidden ring-1 ring-white/10 bg-neutral-900/40 aspect-[2/1] max-h-[640px] skeleton" />
          </div>
        ) : heroItems.length === 0 ? null : isCarousel ? (
          <HeroCarousel
            items={heroItems}
            autoRotate={settings.heroAutoRotate !== false}
            onInfo={openItem}
            onActiveChange={setActiveBackdrop}
          />
        ) : (
          <BillboardHero item={heroItems[0]} onBackdrop={setActiveBackdrop} onInfo={openItem} />
        ))}
      <div className="mt-6" />
      {ready && !connected && (
        <SectionBanner title="Continue Watching" message="Connect your Plex account to see your in‑progress shows and movies here." cta="Open Settings" to="/settings" />
      )}
      {displayRows.map((row) =>
        row.kind === 'continue' ? (
          <ContinueWatchingRow key={row.id} title={row.title} continueWatching={continueWatching} onOpen={openItem} />
        ) : (
          <HomeRowView key={row.id} spec={row.spec} title={row.title} caption={row.caption} onOpen={openItem} onEmpty={onEmpty} />
        ),
      )}
      <BrowseModal />
    </UltraBlurBackground>
  );
}

/** The single-title hero used by the Netflix and Apple TV layouts. */
function BillboardHero({
  item,
  onBackdrop,
  onInfo,
}: {
  item: CardItem;
  onBackdrop: (url: string | undefined) => void;
  onInfo: (item: CardItem) => void;
}) {
  const nav = useNavigate();
  const [metadata, setMetadata] = useState<HeroMetadata | null>(null);
  const [trailer, setTrailer] = useState<{ videoUrl?: string; ytKey?: string }>({});

  useEffect(() => {
    let alive = true;
    heroMetadata(item).then((value) => {
      if (!alive) return;
      setMetadata(value);
      onBackdrop(value.backdropUrl);
    });
    heroTrailer(item)
      .then((value) => alive && setTrailer(value))
      .catch(() => {});
    return () => {
      alive = false;
    };
  }, [item, onBackdrop]);

  return (
    <HomeHero
      title={metadata?.title || item.showTitle || item.title}
      overview={metadata?.overview}
      backdropUrl={metadata?.backdropUrl}
      rating={metadata?.rating}
      year={metadata?.year}
      runtime={metadata?.runtime}
      genres={metadata?.genres}
      logoUrl={metadata?.logoUrl}
      videoUrl={trailer.videoUrl}
      ytKey={trailer.ytKey}
      onPlay={async () => nav(await resolvePlayRoute(item.id, item.mediaType))}
      onMoreInfo={() => onInfo(item)}
    />
  );
}
