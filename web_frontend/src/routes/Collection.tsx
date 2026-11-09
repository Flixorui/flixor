import { useCallback, useEffect, useRef, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import TitleGrid from '@/components/details/TitleGrid';
import CollectionEditor from '@/components/collections/CollectionEditor';
import { fetchSourcePage, sourceSummary, type CollectionItem } from '@/components/collections/resolveSources';
import { deleteCollection, saveCollection, useCollections, type CollectionSource } from '@/state/collections';

type Cursors = Map<string, number>;

export default function Collection() {
  const { id = '' } = useParams();
  const nav = useNavigate();
  const collections = useCollections();
  const collection = collections.find((item) => item.id === decodeURIComponent(id));

  const [items, setItems] = useState<CollectionItem[]>([]);
  const [failures, setFailures] = useState<Array<{ source: CollectionSource; message: string }>>([]);
  const [phase, setPhase] = useState<'loading' | 'loaded'>('loading');
  const [loadingMore, setLoadingMore] = useState(false);
  const [editing, setEditing] = useState(false);
  const [cursors, setCursors] = useState<Cursors>(new Map());
  const generation = useRef(0);

  const sourcesKey = collection ? JSON.stringify(collection.sources) : '';

  const loadPages = useCallback(async (
    sources: CollectionSource[],
    from: Cursors,
    gen: number,
  ) => {
    const results = await Promise.allSettled(sources.map((source) => fetchSourcePage(source, from.get(source.sourceId))));
    if (gen !== generation.current) return;

    const next: Cursors = new Map();
    const failed: Array<{ source: CollectionSource; message: string }> = [];
    const fetched: CollectionItem[] = [];
    results.forEach((result, index) => {
      const source = sources[index];
      if (result.status === 'fulfilled') {
        fetched.push(...result.value.items);
        if (result.value.nextCursor != null) next.set(source.sourceId, result.value.nextCursor);
      } else {
        failed.push({ source, message: result.reason instanceof Error ? result.reason.message : "This source couldn't be loaded." });
      }
    });
    setItems((current) => {
      const seen = new Set(current.map((item) => item.id));
      return [...current, ...fetched.filter((item) => !seen.has(item.id) && seen.add(item.id))];
    });
    setCursors(next);
    setFailures(failed);
  }, []);

  useEffect(() => {
    if (!collection) return;
    const gen = ++generation.current;
    setItems([]);
    setFailures([]);
    setCursors(new Map());
    setPhase('loading');
    loadPages(collection.sources, new Map(), gen).finally(() => {
      if (gen === generation.current) setPhase('loaded');
    });
    // `sourcesKey` stands in for the sources; renames must not reload.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sourcesKey, loadPages]);

  const loadMore = async () => {
    if (!collection || loadingMore) return;
    const gen = generation.current;
    setLoadingMore(true);
    await loadPages(collection.sources.filter((source) => cursors.has(source.sourceId)), cursors, gen);
    if (gen === generation.current) setLoadingMore(false);
  };

  if (!collection) {
    return (
      <div className="page-gutter py-24 text-center text-white/60">
        <p>This collection doesn't exist any more.</p>
        <Link to="/my-list" className="mt-3 inline-block font-semibold text-white hover:text-white/80">Back to My List</Link>
      </div>
    );
  }

  const remove = () => {
    if (!window.confirm(`Delete "${collection.name}"? This can't be undone.`)) return;
    deleteCollection(collection.id);
    nav('/my-list');
  };

  const setCoverFrom = (item: CollectionItem) => {
    const url = item.backdrop || item.image;
    if (url) saveCollection({ ...collection, cover: { url, style: item.backdrop ? 'backdrop' : 'poster' } });
  };

  return (
    <div className="page-gutter pb-16 pt-8">
      <header className="mb-8 flex items-start justify-between gap-4">
        <div className="min-w-0">
          <h1 className="truncate text-3xl font-bold text-white">{collection.name}</h1>
          <p className="mt-1 truncate text-sm text-white/60">{collection.sources.map(sourceSummary).join(' + ')}</p>
        </div>
        <div className="flex flex-shrink-0 gap-2">
          <button onClick={() => setEditing(true)} className="rounded-lg bg-white/10 px-3 py-1.5 text-sm font-medium text-white hover:bg-white/20">Edit</button>
          <button onClick={remove} className="rounded-lg bg-white/10 px-3 py-1.5 text-sm font-medium text-red-400 hover:bg-white/20">Delete</button>
        </div>
      </header>

      {failures.map(({ source, message }) => (
        <p key={source.sourceId} className="mb-3 rounded-lg bg-amber-400/10 p-3 text-sm text-amber-200">{sourceSummary(source)}: {message}</p>
      ))}

      {phase === 'loading' && (
        <div className="grid grid-cols-[repeat(auto-fill,minmax(130px,1fr))] gap-4 md:grid-cols-[repeat(auto-fill,minmax(160px,1fr))]">
          {Array.from({ length: 12 }).map((_, index) => <div key={index} className="aspect-[2/3] animate-pulse rounded-xl bg-white/10" />)}
        </div>
      )}
      {phase === 'loaded' && items.length === 0 && failures.length === 0 && (
        <p className="py-16 text-center text-white/60">This collection has no titles to show.</p>
      )}
      {items.length > 0 && (
        <TitleGrid
          items={items}
          renderOverlay={(item) => (
            <button
              onClick={() => setCoverFrom(item as CollectionItem)}
              title="Use as cover"
              className="absolute left-2 top-2 rounded bg-black/70 px-2 py-1 text-[11px] font-medium text-white opacity-0 transition-opacity hover:bg-black focus:opacity-100 group-hover:opacity-100"
            >
              Use as cover
            </button>
          )}
        />
      )}
      {cursors.size > 0 && (
        <div className="py-8 text-center">
          <button onClick={loadMore} disabled={loadingMore} className="rounded-full bg-white/15 px-5 py-2 text-sm font-semibold text-white hover:bg-white/25 disabled:opacity-50">
            {loadingMore ? 'Loading...' : 'Load More'}
          </button>
        </div>
      )}
      {editing && <CollectionEditor collection={collection} onClose={() => setEditing(false)} />}
    </div>
  );
}
