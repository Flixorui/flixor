import { smartImageUrl } from '@/components/SmartImage';

/** Same ceiling as the macOS Home preheat. */
const MAX_PREHEATED = 360;
const seen = new Set<string>();
const queue: string[] = [];
let running = 0;

function pump() {
  while (running < 6 && queue.length > 0) {
    const url = queue.shift()!;
    running += 1;
    const image = new Image();
    image.decoding = 'async';
    image.onload = image.onerror = () => {
      running -= 1;
      schedule();
    };
    image.src = url;
  }
}

function schedule() {
  if (queue.length === 0) return;
  const idle = (window as any).requestIdleCallback as undefined | ((cb: () => void) => void);
  if (idle) idle(pump);
  else window.setTimeout(pump, 200);
}

/** Loads artwork in idle time so it is in the HTTP cache before it scrolls in. */
export function preheatImages(urls: Array<string | undefined>, width: number) {
  for (const url of urls) {
    if (!url || url.startsWith('data:')) continue;
    const resolved = smartImageUrl(url, width);
    if (!resolved || seen.has(resolved) || seen.size >= MAX_PREHEATED) continue;
    seen.add(resolved);
    queue.push(resolved);
  }
  schedule();
}
