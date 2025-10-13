import { useEffect, useState } from 'react';
import { tmdbPersonCombined, tmdbSearchPerson, tmdbImage } from '@/services/tmdb';
import Row from '@/components/Row';

export default function PersonModal({ open, onClose, personId, name, tmdbKey }: { open: boolean; onClose: () => void; personId?: string; name?: string; tmdbKey?: string }) {
  const [title, setTitle] = useState('');
  const [movies, setMovies] = useState<any[]>([]);
  const [tv, setTv] = useState<any[]>([]);

  useEffect(() => {
    if (!open || !tmdbKey) return;
    (async () => {
      let pid = personId;
      try {
        if (!pid && name) {
          const res: any = await tmdbSearchPerson(tmdbKey, name);
          pid = res.results?.[0]?.id ? String(res.results[0].id) : undefined;
        }
        if (!pid) return;
        const cc: any = await tmdbPersonCombined(tmdbKey, pid);
        setTitle(cc.cast?.[0]?.name || name || 'Person');
        const m = (cc.cast||[]).filter((c:any)=>c.media_type==='movie').slice(0,12)
          .map((x:any)=>({ id:`tmdb:movie:${x.id}`, title:x.title, image: tmdbImage(x.backdrop_path,'w780')||tmdbImage(x.poster_path,'w500') }));
        const t = (cc.cast||[]).filter((c:any)=>c.media_type==='tv').slice(0,12)
          .map((x:any)=>({ id:`tmdb:tv:${x.id}`, title:x.name, image: tmdbImage(x.backdrop_path,'w780')||tmdbImage(x.poster_path,'w500') }));
        setMovies(m); setTv(t);
      } catch (e) { console.error(e); }
    })();
  }, [open, personId, name, tmdbKey]);

  if (!open) return null;
  return (
    <div className="fixed inset-0 z-[120] bg-black/70 backdrop-blur-sm flex items-center justify-center" onClick={onClose}>
      <div className="w-[90vw] max-w-5xl max-h-[80vh] overflow-auto bg-neutral-950 border border-white/10 rounded-xl p-4" onClick={(e)=>e.stopPropagation()}>
        <div className="flex items-center justify-between mb-2">
          <h3 className="text-xl font-semibold">{title}</h3>
          <button className="btn-ghost" onClick={onClose}>Close</button>
        </div>
        {movies.length>0 && <Row title="Movies" items={movies as any} />}
        {tv.length>0 && <Row title="TV Shows" items={tv as any} />}
      </div>
    </div>
  );
}
