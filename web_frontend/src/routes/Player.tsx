import { useEffect, useMemo, useRef, useState } from 'react';
import { useLocation, useNavigate, useParams } from 'react-router-dom';
import PlayerChrome from '@/components/PlayerChrome';
import WebPlayer from '@/components/WebPlayer';
import AdvancedPlayer from '@/components/AdvancedPlayer';
import { loadSettings } from '@/state/settings';
import { plexImage, plexMetadata } from '@/services/plex';
import { apiClient } from '@/services/api';
import { plexStreamUrl, plexTimelineUpdate, plexMetadataWithExtras, plexPartUrl } from '@/services/plex';
import { backendStreamUrl, backendUpdateProgress } from '@/services/plex_backend_player';
import { plexChildren } from '@/services/plex';

export default function Player() {
  const { id } = useParams();
  const loc = useLocation();
  const nav = useNavigate();
  const [isPlaying, setIsPlaying] = useState(true);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(3600);
  const qs = useMemo(()=> new URLSearchParams(loc.search), [loc.search]);
  const [webUrl, setWebUrl] = useState<string | null>(null);
  const [isDash, setIsDash] = useState(false);
  const [title, setTitle] = useState<string>('');
  const [poster, setPoster] = useState<string | undefined>(undefined);
  const [quality, setQuality] = useState<string>('auto');
  const [resolution, setResolution] = useState<string>('source');
  const qualityOptions = useMemo(() => ([
    { label: 'Auto', value: 'auto' },
    { label: 'Original', value: 'original' },
    { label: '1 Mbps', value: '1000' },
    { label: '2 Mbps', value: '2000' },
    { label: '3 Mbps', value: '3000' },
    { label: '4 Mbps', value: '4000' },
    { label: '6 Mbps', value: '6000' },
    { label: '8 Mbps', value: '8000' },
    { label: '10 Mbps', value: '10000' },
    { label: '12 Mbps', value: '12000' },
    { label: '20 Mbps', value: '20000' },
  ]), []);
  const resolutionOptions = useMemo(() => ([
    { label: 'Source', value: 'source' },
    { label: '480p', value: '854x480' },
    { label: '720p', value: '1280x720' },
    { label: '1080p', value: '1920x1080' },
    { label: '1440p', value: '2560x1440' },
    { label: '4K', value: '3840x2160' },
  ]), []);
  function bitrateForResolution(res?: string): number | undefined {
    switch (res) {
      case '854x480': return 1500;
      case '1280x720': return 3000;
      case '1920x1080': return 6000;
      case '2560x1440': return 10000;
      case '3840x2160': return 20000;
      default: return undefined;
    }
  }
  const [ratingKey, setRatingKey] = useState<string | null>(null);
  const [markers, setMarkers] = useState<Array<{ type: string; start: number; end: number }>>([]);
  const [next, setNext] = useState<{ id: string; title: string } | null>(null);
  const last = useRef<{ t: number; d: number; state: 'playing'|'paused'|'buffering' } | null>(null);
  const timerRef = useRef<number | null>(null);

  useEffect(() => {
    async function open() {
      if (!id) return;
      const decoded = decodeURIComponent(id);
      let url: string | undefined;
      if (decoded.startsWith('plex:')) {
        const s = loadSettings();
        if (s.plexBaseUrl && s.plexToken) {
          const rk = decoded.replace(/^plex:/, '');
          try {
            const meta: any = await (await import('@/services/plex_backend')).plexBackendMetadata(rk);
            const m = meta?.MediaContainer?.Metadata?.[0];
            if (m) {
              setTitle(m.title || m.grandparentTitle || '');
              const p = m.thumb || m.parentThumb || m.grandparentThumb;
              const img = apiClient.getPlexImageNoToken(p || '');
              setPoster(img);
              setRatingKey(String(m.ratingKey));
              // Fetch markers (intro, credits)
              try {
                const mark: any = await (await import('@/services/plex_backend')).plexBackendMetadataWithExtras(String(m.ratingKey));
                const mm = mark?.MediaContainer?.Metadata?.[0];
                const list = (mm?.Marker || []).map((mk: any) => ({ type: String(mk.type||''), start: (mk.start||0)/1000, end: (mk.end||0)/1000 }));
                setMarkers(list);
              } catch {}
            }
            const v = qs.get('v');
            let partId: string | undefined;
              if (v) {
                const media = (m?.Media||[]).find((me:any)=> String(me.id||me.Id)===v);
                partId = media?.Part?.[0]?.id ? String(media.Part[0].id) : undefined;
              } else {
                partId = m?.Media?.[0]?.Part?.[0]?.id ? String(m.Media[0].Part[0].id) : undefined;
              }
              if (partId) {
                const resSel = resolution !== 'source' ? resolution : undefined;
                const resBitrate = bitrateForResolution(resSel);
                const qnum = quality !== 'original' ? (Number(quality) || undefined) : undefined;
                url = await backendStreamUrl(String(m.ratingKey), {
                  quality: qnum ?? resBitrate,
                  resolution: resSel,
                });
                setIsDash(false);
              }

            // Compute next episode prompt if current is an episode
            if (m?.type === 'episode' && m.parentRatingKey) {
              try {
                const kids: any = await (await import('@/services/plex_backend')).plexBackendDir(`/library/metadata/${String(m.parentRatingKey)}/children`);
                const list = (kids?.MediaContainer?.Metadata || []) as any[];
                // Sort by 'index' ascending
                list.sort((a:any,b:any)=> (a.index||0)-(b.index||0));
                const idx = list.findIndex((e:any)=> String(e.ratingKey) === String(m.ratingKey));
                const n = idx>=0 ? list[idx+1] : null;
                if (n) setNext({ id: `plex:${String(n.ratingKey)}`, title: n.title || `Episode ${(n.index||'')}` }); else setNext(null);
              } catch { setNext(null); }
            } else { setNext(null); }
          } catch (e) { console.error(e); }
        }
      }
      // Fallback: sample
      if (!url) { url = `https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4`; setIsDash(false); }
      // @ts-ignore
      setWebUrl(url);
    }
    open();
  }, [id, quality, resolution]);

  // Progress timeline updates for Plex
  useEffect(() => {
    if (!ratingKey) return;
    function tick() {
      const v = last.current; if (!v) return;
      backendUpdateProgress(ratingKey, v.t*1000, v.d*1000, v.state as any).catch(()=>{});
    }
    timerRef.current = window.setInterval(tick, 10000) as unknown as number;
    return () => { if (timerRef.current) window.clearInterval(timerRef.current); timerRef.current = null; };
  }, [ratingKey]);

  // Extra timeline on visibilitychange/unload
  useEffect(() => {
    const handler = () => {
      const v = last.current; if (!ratingKey || !v) return;
      backendUpdateProgress(ratingKey, v.t*1000, v.d*1000, 'paused').catch(()=>{});
    };
    document.addEventListener('visibilitychange', handler);
    window.addEventListener('beforeunload', handler);
    window.addEventListener('unload', handler);
    return () => {
      document.removeEventListener('visibilitychange', handler);
      window.removeEventListener('beforeunload', handler);
      window.removeEventListener('unload', handler);
    };
  }, [ratingKey]);

  function handleAutoNext() {
    if (!next) return;
    // Keep selected quality and navigate to next episode
    const url = `/player/${encodeURIComponent(next.id)}`;
    nav(url);
  }

  // Web-only path
  {
    // Check if we have Plex configuration for advanced player
    const s = loadSettings();
    const useAdvanced = qs.get('advanced') === 'true' || true; // Default to advanced player
    
    if (useAdvanced && s.plexBaseUrl && s.plexToken && ratingKey) {
      // Use AdvancedPlayer for Plex content
      return (
        <AdvancedPlayer
          plexConfig={{ baseUrl: s.plexBaseUrl, token: s.plexToken }}
          itemId={ratingKey}
          onBack={() => nav(-1)}
          onNext={(nextId) => {
            const url = `/player/${encodeURIComponent(`plex:${nextId}`)}`;
            nav(url);
          }}
        />
      );
    } else if (webUrl) {
      // Fallback to WebPlayer for non-Plex content or if advanced is disabled
      const tParam = Number(qs.get('t') || 0);
      return (
        <WebPlayer
          src={webUrl}
          title={title || String(id)}
          poster={poster}
          startTime={isFinite(tParam) ? Math.max(0, tParam/1000) : undefined}
          quality={quality}
          qualityOptions={qualityOptions}
          onQualityChange={(v) => setQuality(v)}
          resolution={resolution}
          resolutionOptions={resolutionOptions}
          onResolutionChange={(v) => setResolution(v)}
          markers={markers}
          dash={isDash}
          onProgress={(t, d, state) => { last.current = { t, d, state }; setCurrentTime(Math.floor(t)); setDuration(Math.floor(d)); }}
          onBack={() => {
            if (ratingKey && last.current) {
              backendUpdateProgress(ratingKey, (last.current?.t||0)*1000, (last.current?.d||0)*1000, 'paused').finally(()=> nav(-1));
            } else { nav(-1); }
          }}
          nextLabel={next?.title}
          onNext={() => handleAutoNext()}
        />
      );
    }
  }

  // Fallback safety (should not be hit in web-only)
  return <div className="fixed inset-0 bg-black" />;
}
