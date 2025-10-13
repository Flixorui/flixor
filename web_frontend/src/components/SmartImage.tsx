import { useEffect, useMemo, useRef, useState } from 'react';
import { apiClient } from '@/services/api';

type SmartImageProps = {
  // Provide either a Plex media path (e.g., /library/metadata/..../thumb)
  // or a full external URL (TMDB, etc.).
  plexPath?: string;
  url?: string;
  alt: string;
  width?: number; // intended CSS width in pixels for 1x DPR
  height?: number; // optional
  sizes?: string; // responsive sizes string
  className?: string; // wrapper class
  imgClassName?: string; // img element class
  priority?: boolean; // above-the-fold hero
  quality?: number; // 1-100
};

// Clamp helper
const clamp = (v: number, min: number, max: number) => Math.max(min, Math.min(max, v));

export function SmartImage({ plexPath, url, alt, width = 320, height, sizes, className = '', imgClassName = '', priority = false, quality = 70 }: SmartImageProps) {
  const [loaded, setLoaded] = useState(false);
  const dpr = (typeof window !== 'undefined' ? window.devicePixelRatio : 1) || 1;
  const baseW = clamp(Math.round(width), 80, 1920);
  const w1 = baseW;
  const w2 = clamp(Math.round(baseW * 2), baseW + 1, 2400);

  const makeUrl = (fmt: 'webp' | 'jpeg', w: number) => {
    const opts = { width: w, quality, format: fmt } as any;
    if (height) (opts as any).height = Math.round(height * (w / baseW));
    if (plexPath) return apiClient.getPlexImageNoToken(plexPath, opts);
    if (url) {
      // If this is already a same-origin Plex image URL (/api/image/plex?path=...),
      // prefer generating via getPlexImageNoToken using the embedded path to avoid double-proxy.
      try {
        const u = new URL(url, typeof window !== 'undefined' ? window.location.origin : 'http://localhost');
        if (u.pathname.includes('/api/image/plex')) {
          const p = u.searchParams.get('path') || u.searchParams.get('url') || '';
          if (p) return apiClient.getPlexImageNoToken(p, opts);
        }
      } catch {}
      return apiClient.getImageProxyUrl(url, opts);
    }
    return '';
  };

  const srcWebp1x = useMemo(() => makeUrl('webp', w1), [plexPath, url, w1, quality, height]);
  const srcWebp2x = useMemo(() => makeUrl('webp', w2), [plexPath, url, w2, quality, height]);
  const srcJpg1x = useMemo(() => makeUrl('jpeg', w1), [plexPath, url, w1, quality, height]);
  const srcJpg2x = useMemo(() => makeUrl('jpeg', w2), [plexPath, url, w2, quality, height]);
  const lqip = useMemo(() => makeUrl('jpeg', 24), [plexPath, url, quality, height]);

  const onLoad = () => setLoaded(true);
  const fetchPriority = priority ? 'high' : 'auto';
  const loading = priority ? 'eager' : 'lazy';

  // prevent SSR mismatch
  const mounted = useRef(false);
  useEffect(() => { mounted.current = true; }, []);

  return (
    <div className={`relative overflow-hidden ${className}`}>
      {/* LQIP blurred background */}
      <div
        aria-hidden
        className={`absolute inset-0 transition-opacity duration-300 ${loaded ? 'opacity-0' : 'opacity-100'}`}
        style={{
          backgroundImage: lqip ? `url(${lqip})` : undefined,
          backgroundSize: 'cover',
          backgroundPosition: 'center',
          filter: 'blur(20px)',
          transform: 'scale(1.05)',
        }}
      />
      <picture>
        {/* WebP */}
        <source
          type="image/webp"
          srcSet={`${srcWebp1x} 1x, ${srcWebp2x} 2x`}
          sizes={sizes}
        />
        {/* JPEG fallback */}
        <img
          src={srcJpg1x}
          srcSet={`${srcJpg1x} 1x, ${srcJpg2x} 2x`}
          sizes={sizes}
          alt={alt}
          width={width}
          height={height}
          loading={loading as any}
          decoding="async"
          fetchpriority={fetchPriority as any}
          className={`block w-full h-full object-cover ${imgClassName}`}
          onLoad={onLoad}
        />
      </picture>
    </div>
  );
}

export default SmartImage;
