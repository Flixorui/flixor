import Pill from './Pill';

export type FilterOption = { label: string; value: string };

export const LIBRARY_SORTS: FilterOption[] = [
  { label: 'Date Added • Newest', value: 'addedAt:desc' },
  { label: 'Date Added • Oldest', value: 'addedAt' },
  { label: 'Title • A-Z', value: 'titleSort' },
  { label: 'Title • Z-A', value: 'titleSort:desc' },
  { label: 'Release Year • Newest', value: 'year:desc' },
  { label: 'Release Year • Oldest', value: 'year' },
  { label: 'Rating • High to Low', value: 'rating:desc' },
  { label: 'Rating • Low to High', value: 'rating' },
];

export type LibraryFilters = { query: string; genre: string; year: string; sort: string };

export default function FilterBar({
  filters,
  onChange,
  type,
  setType,
  genres,
  years,
  viewMode,
  setViewMode,
}: {
  filters: LibraryFilters;
  onChange: (next: LibraryFilters) => void;
  type: 'all' | 'movies' | 'shows';
  setType: (value: 'all' | 'movies' | 'shows') => void;
  genres: FilterOption[];
  years: FilterOption[];
  viewMode: 'grid' | 'list';
  setViewMode: (value: 'grid' | 'list') => void;
}) {
  return (
    <div className="flex flex-wrap items-center gap-3">
      <input
        value={filters.query}
        onChange={(e) => onChange({ ...filters, query: e.target.value })}
        placeholder="Search"
        aria-label="Search this library"
        className="input w-64 max-w-full"
      />
      <div className="flex items-center gap-2">
        <Pill active={type === 'all'} onClick={() => setType('all')}>All</Pill>
        <Pill active={type === 'movies'} onClick={() => setType('movies')}>Movies</Pill>
        <Pill active={type === 'shows'} onClick={() => setType('shows')}>TV Shows</Pill>
      </div>
      <select className="input" aria-label="Genre" value={filters.genre} onChange={(e) => onChange({ ...filters, genre: e.target.value })}>
        <option value="">All Genres</option>
        {genres.map((g) => <option key={g.value} value={g.value}>{g.label}</option>)}
      </select>
      <select className="input" aria-label="Year" value={filters.year} onChange={(e) => onChange({ ...filters, year: e.target.value })}>
        <option value="">All Years</option>
        {years.map((y) => <option key={y.value} value={y.value}>{y.label}</option>)}
      </select>
      <select className="input" aria-label="Sort" value={filters.sort} onChange={(e) => onChange({ ...filters, sort: e.target.value })}>
        {LIBRARY_SORTS.map((s) => <option key={s.value} value={s.value}>{s.label}</option>)}
      </select>
      <div className="flex items-center gap-1" role="group" aria-label="View mode">
        <Pill active={viewMode === 'grid'} onClick={() => setViewMode('grid')}>Grid</Pill>
        <Pill active={viewMode === 'list'} onClick={() => setViewMode('list')}>List</Pill>
      </div>
    </div>
  );
}
