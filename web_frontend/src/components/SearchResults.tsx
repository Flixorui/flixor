import PosterCard from './PosterCard';
import SmartImage from './SmartImage';
import { handleRowKeyDown } from './cards/rowKeyboard';
import type { CardItem } from './cards/cardTypes';

export interface SearchResult {
  id: string;
  title: string;
  type: 'movie' | 'tv' | 'person' | 'collection';
  image?: string;
  year?: string;
  overview?: string;
  available?: boolean;
  /** The addon a result came from. */
  addon?: string;
  subtitle?: string;
}

interface SearchResultsProps {
  results: SearchResult[];
  onItemClick: (item: SearchResult) => void;
}

function cardFor(item: SearchResult): CardItem {
  return {
    id: item.id,
    title: item.title,
    image: item.image,
    year: item.year,
    overview: item.overview,
    subtitle: item.year,
    mediaType: item.type === 'movie' ? 'movie' : 'show',
  };
}

export default function SearchResults({ results, onItemClick }: SearchResultsProps) {
  const titles = results.filter((r) => r.type === 'movie' || r.type === 'tv');
  const available = titles.filter((r) => r.available);
  const addons = titles.filter((r) => r.addon);
  const movies = titles.filter((r) => r.type === 'movie' && !r.available && !r.addon);
  const shows = titles.filter((r) => r.type === 'tv' && !r.available && !r.addon);
  const people = results.filter((r) => r.type === 'person');
  const collections = results.filter((r) => r.type === 'collection');

  return (
    <div className="space-y-8">
      {available.length > 0 && <SearchRow title="Results from Your Plex" items={available} onItemClick={onItemClick} badge="In Library" />}
      {collections.length > 0 && <CollectionRow items={collections} onItemClick={onItemClick} />}
      {movies.length > 0 && <SearchRow title="Movies" items={movies} onItemClick={onItemClick} />}
      {shows.length > 0 && <SearchRow title="TV Shows" items={shows} onItemClick={onItemClick} />}
      {addons.length > 0 && <SearchRow title="From Your Addons" items={addons} onItemClick={onItemClick} />}
      {people.length > 0 && <PeopleRow items={people} onItemClick={onItemClick} />}
    </div>
  );
}

function SearchRow({ title, items, onItemClick, badge }: { title: string; items: SearchResult[]; onItemClick: (item: SearchResult) => void; badge?: string }) {
  return (
    <div>
      <h3 className="text-lg font-semibold mb-4 text-white">{title}</h3>
      <div className="flex gap-4 overflow-x-auto pb-4 no-scrollbar" data-card-row="" onKeyDown={handleRowKeyDown}>
        {items.map((item) => (
          <PosterCard key={item.id} id={item.id} title={item.title} image={item.image} subtitle={item.year} badge={badge} item={cardFor(item)} onClick={() => onItemClick(item)} />
        ))}
      </div>
    </div>
  );
}

function PeopleRow({ items, onItemClick }: { items: SearchResult[]; onItemClick: (item: SearchResult) => void }) {
  return (
    <div>
      <h3 className="text-lg font-semibold mb-4 text-white">People</h3>
      <div className="flex gap-4 overflow-x-auto pb-4 no-scrollbar">
        {items.map((person) => (
          <button key={person.id} onClick={() => onItemClick(person)} className="flex-shrink-0 w-[120px] text-center group outline-none">
            <div className="w-[120px] h-[120px] rounded-full overflow-hidden bg-neutral-800 ring-1 ring-white/10 group-hover:ring-white/40 group-focus-visible:ring-2 group-focus-visible:ring-white flex items-center justify-center text-3xl font-semibold text-white/40">
              {person.image ? <SmartImage url={person.image} alt={person.title} width={120} className="w-full h-full" /> : person.title.charAt(0)}
            </div>
            <p className="mt-2 text-sm font-medium text-white line-clamp-2">{person.title}</p>
            {person.subtitle && <p className="text-xs text-neutral-400 line-clamp-1">{person.subtitle}</p>}
          </button>
        ))}
      </div>
    </div>
  );
}

function CollectionRow({ items, onItemClick }: { items: SearchResult[]; onItemClick: (item: SearchResult) => void }) {
  return (
    <div>
      <h3 className="text-lg font-semibold mb-4 text-white">Collections</h3>
      <div className="flex gap-4 overflow-x-auto pb-4 no-scrollbar">
        {items.map((item) => (
          <button key={item.id} onClick={() => onItemClick(item)} className="flex-shrink-0 w-[240px] text-left group outline-none">
            <div className="aspect-video rounded-lg overflow-hidden bg-neutral-800 ring-1 ring-white/10 group-hover:ring-white/40 group-focus-visible:ring-2 group-focus-visible:ring-white">
              {item.image && <SmartImage url={item.image} alt={item.title} width={240} className="w-full h-full" />}
            </div>
            <p className="mt-2 text-sm font-medium text-white line-clamp-1">{item.title}</p>
          </button>
        ))}
      </div>
    </div>
  );
}
