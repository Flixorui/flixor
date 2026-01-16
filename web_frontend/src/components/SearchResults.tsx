import SmartImage from './SmartImage';

interface SearchResult {
  id: string;
  title: string;
  type: 'movie' | 'tv' | 'person' | 'collection';
  image?: string;
  year?: string;
  overview?: string;
  available?: boolean;
}

interface SearchResultsProps {
  results: SearchResult[];
  plexResults?: SearchResult[];
  onItemClick: (item: SearchResult) => void;
}

export default function SearchResults({ results, plexResults = [], onItemClick }: SearchResultsProps) {
  // Separate Plex results (available) from TMDB-only results
  const availableResults = results.filter(r => r.available);
  const movies = results.filter(r => r.type === 'movie' && !r.available);
  const shows = results.filter(r => r.type === 'tv' && !r.available);
  const collections = results.filter(r => r.type === 'collection');

  return (
    <div className="space-y-8">
      {/* Results from Your Plex */}
      {availableResults.length > 0 && (
        <SearchRow
          title="Results from Your Plex"
          items={availableResults}
          onItemClick={onItemClick}
          showBadge
        />
      )}

      {/* Movies Section */}
      {movies.length > 0 && (
        <SearchRow
          title="Movies"
          items={movies}
          onItemClick={onItemClick}
        />
      )}

      {/* TV Shows Section */}
      {shows.length > 0 && (
        <SearchRow
          title="TV Shows"
          items={shows}
          onItemClick={onItemClick}
        />
      )}

      {/* Collections Section */}
      {collections.length > 0 && (
        <SearchRow
          title="Collections"
          items={collections}
          onItemClick={onItemClick}
        />
      )}
    </div>
  );
}

function SearchRow({
  title,
  items,
  onItemClick,
  showBadge = false
}: {
  title: string;
  items: SearchResult[];
  onItemClick: (item: SearchResult) => void;
  showBadge?: boolean;
}) {
  return (
    <div>
      <h3 className="text-lg font-semibold mb-4 text-white">{title}</h3>
      <div className="flex gap-4 overflow-x-auto pb-4 scrollbar-hide">
        {items.map(item => (
          <SearchResultCard
            key={item.id}
            item={item}
            onClick={() => onItemClick(item)}
            showBadge={showBadge || item.available}
          />
        ))}
      </div>
    </div>
  );
}

function SearchResultCard({
  item,
  onClick,
  showBadge = false
}: {
  item: SearchResult;
  onClick: () => void;
  showBadge?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      className="flex-shrink-0 w-[150px] group text-left focus:outline-none"
    >
      {/* Poster */}
      <div className="relative aspect-[2/3] rounded-lg overflow-hidden bg-neutral-800 ring-1 ring-white/10 group-hover:ring-white/30 transition-all">
        {item.image ? (
          <SmartImage
            url={item.image}
            alt={item.title}
            width={150}
            className="w-full h-full"
            imgClassName="object-cover"
          />
        ) : (
          <div className="w-full h-full flex items-center justify-center text-neutral-600">
            <svg className="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M15.75 10.5l4.72-4.72a.75.75 0 011.28.53v11.38a.75.75 0 01-1.28.53l-4.72-4.72M4.5 18.75h9a2.25 2.25 0 002.25-2.25v-9a2.25 2.25 0 00-2.25-2.25h-9A2.25 2.25 0 002.25 7.5v9a2.25 2.25 0 002.25 2.25z" />
            </svg>
          </div>
        )}

        {/* In Library Badge */}
        {(showBadge || item.available) && (
          <div className="absolute top-2 left-2 px-2 py-0.5 bg-green-600/90 backdrop-blur-sm rounded text-[10px] font-semibold text-white uppercase tracking-wide">
            In Library
          </div>
        )}

        {/* Hover overlay */}
        <div className="absolute inset-0 bg-black/0 group-hover:bg-black/20 transition-colors" />
      </div>

      {/* Title & Year */}
      <div className="mt-2">
        <p className="text-sm font-medium text-white truncate group-hover:text-white/90">{item.title}</p>
        <p className="text-xs text-neutral-500">{item.year || item.type}</p>
      </div>
    </button>
  );
}
