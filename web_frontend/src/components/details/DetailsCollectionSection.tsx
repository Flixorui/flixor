import { useEffect, useState } from 'react';
import { tmdbCollection, tmdbImage } from '@/services/tmdb';
import DetailsMediaRow, { type DetailsMediaItem } from './DetailsMediaRow';

export interface DetailsCollection {
  name: string;
  parts: DetailsMediaItem[];
}

/** The other movies of a TMDB collection, in release order. Null when it has under two parts. */
export function useDetailsCollection(collectionId?: number): DetailsCollection | null {
  const [collection, setCollection] = useState<DetailsCollection | null>(null);

  useEffect(() => {
    setCollection(null);
    if (!collectionId) return;
    let alive = true;
    tmdbCollection(collectionId)
      .then((data: any) => {
        if (!alive) return;
        const parts = [...(data?.parts || [])]
          .sort((a: any, b: any) => (a.release_date || '9999').localeCompare(b.release_date || '9999'))
          .map((part: any): DetailsMediaItem => ({
            id: `tmdb:movie:${part.id}`,
            title: part.title || part.name,
            image: tmdbImage(part.backdrop_path, 'w780') || tmdbImage(part.poster_path, 'w500'),
            poster: tmdbImage(part.poster_path, 'w500'),
            subtitle: part.release_date ? part.release_date.slice(0, 4) : undefined,
          }));
        setCollection(parts.length > 1 ? { name: data?.name, parts } : null);
      })
      .catch(() => { if (alive) setCollection(null); });
    return () => { alive = false; };
  }, [collectionId]);

  return collection;
}

export default function DetailsCollectionSection({
  collection,
  currentMovieId,
  onSelect,
}: {
  collection: DetailsCollection;
  currentMovieId?: string;
  onSelect: (id: string) => void;
}) {
  return (
    <DetailsMediaRow
      title={`Part of ${collection.name || 'a Collection'}`}
      subtitle={`${collection.parts.length} movies, in release order`}
      items={collection.parts}
      currentId={currentMovieId ? `tmdb:movie:${currentMovieId}` : undefined}
      onSelect={onSelect}
    />
  );
}
