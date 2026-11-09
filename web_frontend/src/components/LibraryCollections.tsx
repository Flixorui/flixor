import { useEffect, useState } from 'react';
import SmartImage from './SmartImage';
import PosterCard from './PosterCard';
import { useCardStyle } from './cards/cardStyle';
import type { CardItem } from './cards/cardTypes';
import { getAllCollections, getCollectionItems, type PlexCollection, type PlexLibrary } from '@/services/plexCollections';

function Loading() {
  return <p className="text-neutral-400 py-12 text-center">Loading…</p>;
}

function ErrorState({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <div className="py-12 text-center">
      <p className="text-neutral-400 mb-3">{message}</p>
      <button onClick={onRetry} className="btn">Retry</button>
    </div>
  );
}

/** Every Plex collection in the enabled libraries. */
export function CollectionsGrid({ libraries, onSelect }: { libraries: PlexLibrary[]; onSelect: (collection: PlexCollection) => void }) {
  const [collections, setCollections] = useState<PlexCollection[] | null>(null);
  const [error, setError] = useState('');
  const [attempt, setAttempt] = useState(0);
  const libraryKeys = libraries.map((library) => library.key).join(',');

  useEffect(() => {
    let alive = true;
    setCollections(null);
    setError('');
    getAllCollections(libraries)
      .then((list) => alive && setCollections(list.sort((a, b) => a.title.localeCompare(b.title))))
      .catch((e: any) => alive && setError(e?.message || 'Could not load collections'));
    return () => {
      alive = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [libraryKeys, attempt]);

  if (error) return <ErrorState message={error} onRetry={() => setAttempt((value) => value + 1)} />;
  if (!collections) return <Loading />;
  if (collections.length === 0) return <p className="text-neutral-400 py-12 text-center">No Plex collections found.</p>;

  return (
    <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-4">
      {collections.map((collection) => (
        <button key={collection.ratingKey} onClick={() => onSelect(collection)} className="text-left group outline-none">
          <div className="relative aspect-video rounded-xl overflow-hidden bg-neutral-800 ring-1 ring-white/10 group-hover:ring-white/40 group-focus-visible:ring-2 group-focus-visible:ring-white transition-all">
            {collection.image && <SmartImage url={collection.image} alt={collection.title} width={320} className="w-full h-full" imgClassName="object-cover" />}
          </div>
          <p className="mt-2 text-sm font-medium text-white line-clamp-1">{collection.title}</p>
          <p className="text-xs text-neutral-400">
            {collection.count} {collection.count === 1 ? 'title' : 'titles'} · {collection.libraryTitle}
          </p>
        </button>
      ))}
    </div>
  );
}

/** The titles inside one collection. */
export function CollectionItems({ ratingKey, title, onBack, onOpen }: { ratingKey: string; title?: string; onBack: () => void; onOpen: (item: CardItem) => void }) {
  const [items, setItems] = useState<CardItem[] | null>(null);
  const [error, setError] = useState('');
  const [attempt, setAttempt] = useState(0);
  const style = useCardStyle('library');

  useEffect(() => {
    let alive = true;
    setItems(null);
    setError('');
    getCollectionItems(ratingKey)
      .then((list) => alive && setItems(list))
      .catch((e: any) => alive && setError(e?.message || 'Could not load this collection'));
    return () => {
      alive = false;
    };
  }, [ratingKey, attempt]);

  return (
    <div>
      <div className="flex items-center gap-3 mb-4">
        <button onClick={onBack} className="btn">Back</button>
        {title && <h2 className="text-white font-bold text-lg">{title}</h2>}
      </div>
      {error ? (
        <ErrorState message={error} onRetry={() => setAttempt((value) => value + 1)} />
      ) : !items ? (
        <Loading />
      ) : items.length === 0 ? (
        <p className="text-neutral-400 py-12 text-center">This collection is empty.</p>
      ) : (
        <div className="grid gap-3" style={{ gridTemplateColumns: `repeat(auto-fill, minmax(${style.posterWidth}px, 1fr))` }}>
          {items.map((item) => (
            <PosterCard key={item.id} id={item.id} title={item.title} image={item.image} item={item} surface="library" fill onClick={() => onOpen(item)} />
          ))}
        </div>
      )}
    </div>
  );
}
