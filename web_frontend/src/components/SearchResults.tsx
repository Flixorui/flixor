import LandscapeCard from './LandscapeCard';

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
  onItemClick: (item: SearchResult) => void;
}

export default function SearchResults({ results, onItemClick }: SearchResultsProps) {
  // Group results by type
  const movies = results.filter(r => r.type === 'movie');
  const shows = results.filter(r => r.type === 'tv');
  const collections = results.filter(r => r.type === 'collection');

  return (
    <div className="space-y-8">
      {/* Movies Section */}
      {movies.length > 0 && (
        <div>
          <h3 className="text-lg font-semibold mb-4 text-neutral-300">Movies</h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5 gap-6">
            {movies.map(item => (
              <LandscapeResult key={item.id} item={item} onClick={() => onItemClick(item)} />
            ))}
          </div>
        </div>
      )}

      {/* TV Shows Section */}
      {shows.length > 0 && (
        <div>
          <h3 className="text-lg font-semibold mb-4 text-neutral-300">TV Shows</h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5 gap-6">
            {shows.map(item => (
              <LandscapeResult key={item.id} item={item} onClick={() => onItemClick(item)} />
            ))}
          </div>
        </div>
      )}

      {/* Collections Section */}
      {collections.length > 0 && (
        <div>
          <h3 className="text-lg font-semibold mb-4 text-neutral-300">Collections</h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5 gap-6">
            {collections.map(item => (
              <LandscapeResult key={item.id} item={item} onClick={() => onItemClick(item)} />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

function LandscapeResult({ item, onClick }: { item: SearchResult; onClick: () => void }) {
  return (
    <div>
      <LandscapeCard id={item.id} title={item.title} image={item.image || ''} badge={item.year} onClick={() => onClick()} layout="grid" />
      <div className="mt-2">
        <p className="text-sm font-medium truncate">{item.title}</p>
        {item.year && <p className="text-xs text-gray-400">{item.year}</p>}
      </div>
    </div>
  );
}
