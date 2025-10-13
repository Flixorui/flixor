import { useEffect, useState } from 'react';
import { useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { loadSettings } from '@/state/settings';
import { tmdbPersonCombined, tmdbSearchPerson, tmdbImage } from '@/services/tmdb';
import Row from '@/components/Row';

export default function Person() {
  const { id } = useParams();
  const [sp] = useSearchParams();
  const nav = useNavigate();
  const [rows, setRows] = useState<any[]>([]);
  const [name, setName] = useState('');
  useEffect(() => {
    const s = loadSettings();
    async function load() {
      if (!s.tmdbBearer) return;
      let pid = id;
      if (!pid) {
        const q = sp.get('name');
        if (!q) return;
        const res: any = await tmdbSearchPerson(s.tmdbBearer, q);
        pid = res.results?.[0]?.id;
      }
      if (!pid) return;
      const cc: any = await tmdbPersonCombined(s.tmdbBearer, pid);
      setName(cc.cast?.[0]?.name || '');
      const movies = (cc.cast||[]).filter((c:any)=>c.media_type==='movie').slice(0,12)
        .map((m:any)=>({id:`tmdb:movie:${m.id}`, title:m.title, image: tmdbImage(m.backdrop_path,'w780')||tmdbImage(m.poster_path,'w500')}));
      const tv = (cc.cast||[]).filter((c:any)=>c.media_type==='tv').slice(0,12)
        .map((m:any)=>({id:`tmdb:tv:${m.id}`, title:m.name, image: tmdbImage(m.backdrop_path,'w780')||tmdbImage(m.poster_path,'w500')}));
      setRows([
        { title: 'Movies', items: movies },
        { title: 'TV Shows', items: tv },
      ]);
    }
    load();
  }, [id]);
  return (
    <div className="pb-10">
      <div className="page-gutter pt-6"><h1 className="text-2xl font-semibold">{name || 'Person'}</h1></div>
      {rows.map(r => <Row key={r.title} title={r.title} items={r.items} onItemClick={(id)=> nav(`/details/${encodeURIComponent(id)}`)} />)}
    </div>
  );
}
