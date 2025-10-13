import Pill from './Pill';

type Option = { label: string; value: string };

export default function FilterBar({
  query,
  setQuery,
  type,
  setType,
  genres,
  years,
}: {
  query: string;
  setQuery: (s: string) => void;
  type: string;
  setType: (s: string) => void;
  genres: Option[];
  years: Option[];
}) {
  return (
    <div className="flex flex-wrap items-center gap-3">
      <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search" className="input w-64" />
      <div className="flex items-center gap-2">
        <Pill active={type === 'all'} onClick={() => setType('all')}>All</Pill>
        <Pill active={type === 'movies'} onClick={() => setType('movies')}>Movies</Pill>
        <Pill active={type === 'tv'} onClick={() => setType('tv')}>TV Shows</Pill>
      </div>
      <select className="input">
        <option>Genre</option>
        {genres.map(g => <option key={g.value} value={g.value}>{g.label}</option>)}
      </select>
      <select className="input">
        <option>Year</option>
        {years.map(y => <option key={y.value} value={y.value}>{y.label}</option>)}
      </select>
      <select className="input">
        <option>Resolution</option>
        <option>4K</option>
        <option>1080p</option>
      </select>
      <select className="input">
        <option>HDR</option>
        <option>Dolby Vision</option>
        <option>HDR10</option>
      </select>
      <select className="input">
        <option>Audio</option>
        <option>Atmos</option>
        <option>5.1</option>
      </select>
    </div>
  );
}

