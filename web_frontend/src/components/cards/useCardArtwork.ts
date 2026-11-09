import { useEffect, useState, type RefObject } from 'react';
import { upgradedArtwork } from './cardMedia';
import type { CardMediaType } from './cardTypes';

/** Looks up better TMDB artwork once the card is near the viewport. */
export function useCardArtwork(
  ref: RefObject<HTMLElement>,
  id: string,
  kind: 'poster' | 'backdrop',
  mediaType?: CardMediaType,
): string | undefined {
  const [artwork, setArtwork] = useState<string | undefined>(undefined);

  useEffect(() => {
    setArtwork(undefined);
    const el = ref.current;
    if (!el || !id) return;
    let alive = true;
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (!entry.isIntersecting) return;
        observer.disconnect();
        upgradedArtwork(id, kind, mediaType).then((url) => {
          if (alive && url) setArtwork(url);
        });
      },
      { rootMargin: '300px' },
    );
    observer.observe(el);
    return () => {
      alive = false;
      observer.disconnect();
    };
  }, [ref, id, kind, mediaType]);

  return artwork;
}
