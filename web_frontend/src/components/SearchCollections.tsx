import SmartImage from './SmartImage';

interface CollectionItem {
  id: string;
  title: string;
  type: 'collection';
  image?: string;
  overview?: string;
}

interface SearchCollectionsProps {
  collections: CollectionItem[];
  onItemClick: (item: CollectionItem) => void;
}

// Predefined feature collections
const FEATURED_COLLECTIONS = [
  {
    id: 'streams',
    title: 'Streams',
    gradient: 'from-cyan-500 to-blue-600',
    icon: '▶'
  },
  {
    id: 'coming-soon',
    title: 'Coming Soon',
    gradient: 'from-green-500 to-emerald-600',
    icon: '🎬'
  },
  {
    id: 'halloween',
    title: 'Halloween',
    gradient: 'from-orange-500 to-red-600',
    icon: '🎃'
  },
  {
    id: 'tron',
    title: 'Tron Collection',
    gradient: 'from-blue-400 to-cyan-500',
    icon: '💿'
  },
  {
    id: 'pocket-watch',
    title: 'Creators Collection',
    gradient: 'from-purple-500 to-pink-600',
    icon: '⏰'
  }
];

export default function SearchCollections({ collections, onItemClick }: SearchCollectionsProps) {
  return (
    <div>
      {/* Featured Collections */}
      <div className="mb-8">
        <h3 className="text-lg font-medium mb-4 text-gray-300">Featured</h3>
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-4">
          {FEATURED_COLLECTIONS.map(collection => (
            <div
              key={collection.id}
              className="cursor-pointer group relative"
              onClick={() => onItemClick({
                id: `featured:${collection.id}`,
                title: collection.title,
                type: 'collection'
              })}
            >
              <div className={`aspect-video rounded-xl ring-1 ring-white/10 bg-gradient-to-br ${collection.gradient} flex items-center justify-center transform transition-all duration-300 group-hover:scale-[1.04]`}>
                <div className="text-center">
                  <div className="text-4xl mb-2">{collection.icon}</div>
                  <p className="text-white font-bold text-sm uppercase tracking-wide">{collection.title}</p>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* All Collections */}
      {collections.length > 0 && (
        <div>
          <h3 className="text-lg font-medium mb-4 text-gray-300">All Collections</h3>
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-4">
            {collections.map(collection => (
              <div
                key={collection.id}
                onClick={() => onItemClick(collection)}
                className="cursor-pointer group"
              >
                <div className="relative aspect-[16/9] rounded-xl overflow-hidden bg-gray-800 ring-1 ring-white/10">
                  {collection.image ? (
                    <>
                      <SmartImage url={collection.image} alt={collection.title} width={320} className="w-full h-full" imgClassName="object-cover transform transition-transform duration-300 group-hover:scale-[1.03]" />
                      <div className="absolute inset-0 bg-gradient-to-t from-black/70 via-black/10 to-transparent opacity-90 group-hover:opacity-100 transition-opacity duration-300" />
                    </>
                  ) : (
                    <div className="w-full h-full bg-gradient-to-br from-gray-700 to-gray-800 flex items-center justify-center">
                      <svg className="w-12 h-12 text-gray-600" fill="currentColor" viewBox="0 0 24 24">
                        <path d="M4 6H2v14c0 1.1.9 2 2 2h14v-2H4V6zm16-4H8c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm-1 9h-4v4h-2v-4H9V9h4V5h2v4h4v2z"/>
                      </svg>
                    </div>
                  )}

                  {/* Title overlay */}
                  <div className="absolute bottom-0 left-0 right-0 p-3 bg-gradient-to-t from-black/80 to-transparent">
                    <p className="text-white font-medium text-sm">{collection.title}</p>
                  </div>
                </div>
              </div>
            ))}

            {/* All Collections link */}
            <div
              onClick={() => onItemClick({
                id: 'all-collections',
                title: 'All Collections',
                type: 'collection'
              })}
              className="cursor-pointer group"
            >
              <div className="relative aspect-[16/9] rounded-xl overflow-hidden bg-gradient-to-br from-gray-700 to-gray-800 ring-1 ring-white/10 flex items-center justify-center transform transition-transform duration-300 group-hover:scale-[1.04]">
                <div className="text-center">
                  <svg className="w-10 h-10 text-white mb-2 mx-auto" fill="currentColor" viewBox="0 0 24 24">
                    <path d="M4 8h4V4H4v4zm6 12h4v-4h-4v4zm-6 0h4v-4H4v4zm0-6h4v-4H4v4zm6 0h4v-4H4v4zm6-10v4h4V4h-4zm-6 4h4V4h-4v4zm6 6h4v-4h-4v4zm0 6h4v-4h-4v4z"/>
                  </svg>
                  <p className="text-white font-medium text-sm">All Collections</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
