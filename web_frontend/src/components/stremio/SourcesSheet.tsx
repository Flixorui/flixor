import { useEffect, useMemo, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { Link } from 'react-router-dom';
import { CloseCircleIcon, RefreshIcon } from '@/components/ServiceIcons';
import {
  classifyPlayability,
  findAutomaticSource,
  getCachedStream,
  prepareStreamForPlayback,
  rankStreams,
  saveCachedStream,
  type StremioAddonStreams,
  type StremioContentIdentity,
  type StremioStream,
  type AutoPickAction,
} from '@/stremio';
import { hasStreamProviders } from '@/stremio/addons';
import { useStremioSources } from '@/hooks/useStremioSources';
import { useSettings } from '@/state/settings';
import SourceRow from './SourceRow';

export interface SourcesSheetProps {
  open: boolean;
  /** Null while the title is still being resolved. */
  identity: StremioContentIdentity | null;
  /** Shown in the sheet header. */
  title: string;
  onClose: () => void;
  /** Called with the source the user picked, for the caller to start playback. */
  onSelect: (stream: StremioStream) => void;
  /** Always list sources and skip the automatic Play action. Use inside the player. */
  manual?: boolean;
  /** URL of the source playing now, marked in the list. */
  currentUrl?: string;
}

const streamKey = (stream: StremioStream) => `${stream.installationId}:${stream.streamIndex}`;
const ALL_ADDONS = 'all';

function Spinner({ label }: { label: string }) {
  return (
    <div className="flex flex-col items-center gap-3 py-12 text-[13px] text-[#9ca3af]">
      <span className="h-7 w-7 animate-spin rounded-full border-2 border-white/25 border-t-white" />
      {label}
    </div>
  );
}

/** Source picker for a title: playable sources first, with the rest clearly labelled. */
export default function SourcesSheet({ open, identity, title, onClose, onSelect, manual = false, currentUrl }: SourcesSheetProps) {
  const settings = useSettings();
  const [notice, setNotice] = useState<string | null>(null);
  const [listRequested, setListRequested] = useState(false);
  const [seedResults, setSeedResults] = useState<StremioAddonStreams[] | null>(null);
  const [addonFilter, setAddonFilter] = useState(ALL_ADDONS);
  const [preparingKey, setPreparingKey] = useState<string | null>(null);
  const [rowErrors, setRowErrors] = useState<Record<string, string>>({});
  const [copiedKey, setCopiedKey] = useState<string | null>(null);

  const prepareController = useRef<AbortController | null>(null);
  const onSelectRef = useRef(onSelect);
  onSelectRef.current = onSelect;

  const wantsAuto = open && !manual && settings.stremioPlayAction !== 'showSources' && !listRequested;
  const sources = useStremioSources(open && !wantsAuto ? identity : null, seedResults);
  const identityKey = identity ? `${identity.requestType}|${identity.requestId}` : null;

  useEffect(() => {
    if (open) return;
    prepareController.current?.abort();
    setNotice(null);
    setListRequested(false);
    setSeedResults(null);
    setAddonFilter(ALL_ADDONS);
    setPreparingKey(null);
    setRowErrors({});
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener('keydown', onKeyDown);
    };
  }, [open, onClose]);

  const play = async (stream: StremioStream): Promise<boolean> => {
    if (!identity) return false;
    prepareController.current?.abort();
    const controller = new AbortController();
    prepareController.current = controller;
    const key = streamKey(stream);
    setPreparingKey(key);
    setRowErrors((current) => {
      const { [key]: _cleared, ...rest } = current;
      return rest;
    });
    try {
      const prepared = await prepareStreamForPlayback(stream, identity, { signal: controller.signal });
      saveCachedStream(identity, prepared);
      onSelectRef.current(prepared);
      return true;
    } catch (err: any) {
      if (err?.name !== 'AbortError') {
        setRowErrors((current) => ({ ...current, [key]: err?.message || 'This source could not be started' }));
      }
      return false;
    } finally {
      if (prepareController.current === controller) setPreparingKey(null);
    }
  };

  // Automatic Play action: find a source, and fall back to the list with a reason.
  useEffect(() => {
    if (!wantsAuto || !identity) return;
    const action = settings.stremioPlayAction as AutoPickAction;
    const controller = new AbortController();

    const showList = (nextNotice: string | undefined, results: StremioAddonStreams[]) => {
      setNotice(nextNotice ?? null);
      setSeedResults(results);
      setListRequested(true);
    };

    (async () => {
      try {
        // "Follow addon order" moves on to the next addon when a source won't start.
        const skipAddons = new Set<string>();
        let outcome = await findAutomaticSource(identity, action, { signal: controller.signal, skipAddons });
        if (controller.signal.aborted) return;
        while (action === 'addonOrder' && outcome.kind === 'play' && !(await play(outcome.stream))) {
          if (controller.signal.aborted) return;
          skipAddons.add(outcome.stream.installationId);
          outcome = await findAutomaticSource(identity, action, { signal: controller.signal, skipAddons });
          if (controller.signal.aborted) return;
        }
        if (action === 'addonOrder' && outcome.kind === 'play') return;
        if (outcome.kind === 'showSources') {
          showList(outcome.notice, outcome.results);
          return;
        }
        const started = await play(outcome.stream);
        if (!started && !controller.signal.aborted) {
          showList('The chosen source could not be started. Choose another one here.', outcome.results);
        }
      } catch (err: any) {
        if (err?.name !== 'AbortError') {
          showList('Could not find a source automatically. Choose one here.', []);
        }
      }
    })();

    return () => controller.abort();
    // Re-runs per title. `identity` and `play` are stable for the life of one lookup.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [wantsAuto, identityKey, settings.stremioPlayAction]);

  const hideUnsupported = settings.stremioUnsupportedSourceVisibility === 'hide';
  const allStreams = useMemo(() => sources.results.flatMap((result) => result.streams), [sources.results]);
  const visibleStreams = useMemo(() => {
    const ranked = rankStreams(
      addonFilter === ALL_ADDONS ? allStreams : allStreams.filter((stream) => stream.installationId === addonFilter),
    );
    return hideUnsupported ? ranked.filter((stream) => classifyPlayability(stream).playable) : ranked;
  }, [allStreams, addonFilter, hideUnsupported]);

  const hiddenCount = hideUnsupported
    ? allStreams.filter((stream) => !classifyPlayability(stream).playable).length
    : 0;
  const failedAll = sources.results.length > 0 && sources.results.every((result) => result.error);
  const cachedSource = !manual && identity && settings.stremioPreferCachedSourceResume ? getCachedStream(identity) : null;
  const noStreamAddons = identity
    ? sources.settled && sources.results.length === 0 && !sources.error
    : !hasStreamProviders();

  if (!open) return null;

  const openExternally = (stream: StremioStream) => {
    const url = stream.externalUrl ?? (stream.ytId ? `https://www.youtube.com/watch?v=${stream.ytId}` : undefined);
    if (url && /^https?:\/\//i.test(url)) window.open(url, '_blank', 'noopener,noreferrer');
  };
  const copyLink = async (stream: StremioStream) => {
    if (!stream.url) return;
    try {
      await navigator.clipboard.writeText(stream.url);
      setCopiedKey(streamKey(stream));
      setTimeout(() => setCopiedKey((current) => (current === streamKey(stream) ? null : current)), 2000);
    } catch {
      setRowErrors((current) => ({ ...current, [streamKey(stream)]: 'Could not copy the link' }));
    }
  };

  const renderRow = (stream: StremioStream, keySuffix = '') => (
    <SourceRow
      key={streamKey(stream) + keySuffix}
      stream={stream}
      isCurrent={Boolean(currentUrl && stream.url === currentUrl)}
      preparing={preparingKey === streamKey(stream)}
      error={rowErrors[streamKey(stream)]}
      copied={copiedKey === streamKey(stream)}
      onPlay={() => play(stream)}
      onOpenExternal={() => openExternally(stream)}
      onCopyLink={() => copyLink(stream)}
    />
  );

  const body = () => {
    if (noStreamAddons) {
      return (
        <div className="py-10 text-center text-[13px] text-[#9ca3af]">
          <p>No installed addon can provide sources for this title.</p>
          <Link to="/settings/stremio?view=addons" onClick={onClose} className="mt-3 inline-block font-semibold text-brand hover:underline">
            Manage addons
          </Link>
        </div>
      );
    }
    if (!identity) return <Spinner label="Looking up this title…" />;
    if (wantsAuto) {
      return (
        <div className="flex flex-col items-center gap-4 py-10 text-center">
          <Spinner label="Finding the best source…" />
          <button type="button" onClick={() => setListRequested(true)} className="rounded-full bg-white/10 px-4 py-2 text-[13px] font-semibold text-white hover:bg-white/20">
            Choose a source instead
          </button>
        </div>
      );
    }
    if (sources.error) {
      return <p className="py-10 text-center text-[13px] text-[#f87171]">{sources.error}</p>;
    }
    if (allStreams.length === 0 && !sources.settled) return <Spinner label="Asking your addons for sources…" />;
    if (failedAll) {
      return (
        <div className="py-10 text-center text-[13px] text-[#9ca3af]">
          <p>Your addons could not be reached.</p>
          <button type="button" onClick={sources.reload} className="mt-3 font-semibold text-brand hover:underline">Try again</button>
        </div>
      );
    }
    return (
      <div className="flex flex-col gap-2 pb-2">
        {cachedSource && addonFilter === ALL_ADDONS && (
          <div className="mb-1">
            <p className="mb-1.5 text-[11px] font-bold uppercase tracking-wide text-[#9ca3af]">Last used source</p>
            {renderRow(cachedSource.stream, ':cached')}
          </div>
        )}
        {visibleStreams
          .filter((stream) => !(cachedSource && addonFilter === ALL_ADDONS && stream.url === cachedSource.stream.url))
          .map((stream) => renderRow(stream))}
        {sources.settled && visibleStreams.length === 0 && (
          <p className="py-10 text-center text-[13px] text-[#9ca3af]">
            {hiddenCount > 0 ? 'None of the sources found can play in this browser.' : 'No sources found for this title.'}
          </p>
        )}
        {hiddenCount > 0 && visibleStreams.length > 0 && (
          <p className="py-2 text-center text-[12px] text-[#9ca3af]">
            {hiddenCount} {hiddenCount === 1 ? 'source' : 'sources'} that can't play in this browser hidden.
          </p>
        )}
      </div>
    );
  };

  const addonChips = sources.results.length > 1 && (
    <div className="no-scrollbar flex shrink-0 gap-2 overflow-x-auto px-5 pb-3">
      <FilterChip label="All" selected={addonFilter === ALL_ADDONS} onClick={() => setAddonFilter(ALL_ADDONS)} />
      {sources.results.map((result) => (
        <FilterChip
          key={result.installationId}
          label={result.addonName}
          sublabel={result.error ? 'Failed' : `${result.streams.length} ${result.streams.length === 1 ? 'source' : 'sources'}`}
          selected={addonFilter === result.installationId}
          onClick={() => setAddonFilter(result.installationId)}
        />
      ))}
    </div>
  );

  // Portalled because a parent layer would otherwise keep it under the bottom tab bar.
  return createPortal(
    <div
      role="dialog"
      aria-modal="true"
      aria-label={`Sources for ${title}`}
      className="fixed inset-0 z-[60] flex items-end justify-center bg-black/60 md:items-center"
      onClick={onClose}
    >
      <div
        className="flex max-h-[85vh] w-full max-w-2xl flex-col rounded-t-2xl bg-neutral-900 md:rounded-2xl"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="flex items-center justify-between gap-3 px-5 pb-3 pt-5">
          <div className="min-w-0">
            <h2 className="truncate text-lg font-bold text-white">{title}</h2>
            <p className="text-[12px] text-[#9ca3af]">
              {sources.loading && allStreams.length > 0 ? 'Still asking other addons…' : 'Choose a source'}
            </p>
          </div>
          <div className="flex flex-shrink-0 items-center gap-1">
            <button type="button" onClick={sources.reload} disabled={sources.loading} aria-label="Refresh sources" className="rounded-full p-2 text-[#9ca3af] hover:bg-white/10 disabled:opacity-40">
              <RefreshIcon size={20} />
            </button>
            <button type="button" onClick={onClose} aria-label="Close" className="rounded-full p-2 text-[#9ca3af] hover:bg-white/10">
              <CloseCircleIcon size={22} />
            </button>
          </div>
        </div>
        {addonChips}
        {notice && (
          <p className="mx-5 mb-3 rounded-lg bg-[#f59e0b]/10 px-3 py-2 text-[12px] text-[#fbbf24]">{notice}</p>
        )}
        <div className="min-h-0 flex-1 overflow-y-auto px-5 pb-4">{body()}</div>
      </div>
    </div>,
    document.body,
  );
}

function FilterChip({ label, sublabel, selected, onClick }: { label: string; sublabel?: string; selected: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`flex-shrink-0 rounded-[10px] border px-3 py-1.5 text-left transition-colors ${
        selected ? 'border-brand/50 bg-brand/20 text-white' : 'border-white/[0.08] bg-white/[0.05] text-[#d1d5db] hover:bg-white/10'
      }`}
    >
      <span className="block whitespace-nowrap text-[13px] font-semibold">{label}</span>
      {sublabel && <span className="block whitespace-nowrap text-[11px] text-[#9ca3af]">{sublabel}</span>}
    </button>
  );
}
