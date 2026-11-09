import { useState } from 'react';
import { Link } from 'react-router-dom';
import SmartImage from '@/components/SmartImage';
import { newCollection, useCollections, type UserCollection } from '@/state/collections';
import CollectionEditor from './CollectionEditor';

/** The user's collections, shown on My List. */
export default function UserCollectionsSection() {
  const collections = useCollections();
  const [editing, setEditing] = useState<UserCollection | null>(null);

  return (
    <section className="mb-8">
      <div className="mb-3 flex items-center justify-between">
        <h2 className="text-xl font-bold text-white">Collections</h2>
        <button onClick={() => setEditing(newCollection())} className="rounded-full border border-white/30 px-4 py-1.5 text-sm font-semibold text-white hover:bg-white/10">+ New Collection</button>
      </div>
      {collections.length === 0 ? (
        <p className="text-sm text-white/50">Build your own collections from TMDB, Trakt lists, people or addon catalogs.</p>
      ) : (
        <div className="flex gap-3 overflow-x-auto no-scrollbar pb-1">
          {collections.map((collection) => (
            <Link key={collection.id} to={`/collections/${encodeURIComponent(collection.id)}`} className="group w-[220px] flex-shrink-0">
              <div className="aspect-video overflow-hidden rounded-xl bg-white/10 ring-1 ring-white/10 transition group-hover:ring-white/40">
                {collection.cover && <SmartImage url={collection.cover.url} alt="" width={440} className="h-full w-full" imgClassName="object-cover" />}
              </div>
              <p className="mt-2 truncate text-sm font-medium text-white">{collection.name}</p>
              <p className="text-xs text-white/50">{collection.sources.length} {collection.sources.length === 1 ? 'source' : 'sources'}</p>
            </Link>
          ))}
        </div>
      )}
      {editing && <CollectionEditor collection={editing} onClose={() => setEditing(null)} />}
    </section>
  );
}
