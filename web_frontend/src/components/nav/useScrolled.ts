import { useEffect, useState } from 'react';

const SCROLL_THRESHOLD = 35;

/** True once the page has scrolled away from the top. Only updates when that flips. */
export function useScrolled(): boolean {
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const update = () => setScrolled(window.scrollY > SCROLL_THRESHOLD);
    update();
    window.addEventListener('scroll', update, { passive: true });
    return () => window.removeEventListener('scroll', update);
  }, []);

  return scrolled;
}
