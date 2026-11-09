import { useEffect, useState } from 'react';
import { DEFAULT_DISCOVER_FILTERS, DISCOVER_GENRES, DISCOVER_SORTS } from '@/services/discover';
import { tmdbSearchCollections, tmdbSearchPerson } from '@/services/tmdb';
import { getPublicList, publicListPath, searchPublicLists, type TraktPublicList } from '@/services/traktLists';
import { getCatalogs, type StremioCatalog } from '@/stremio';
import {
  saveCollection,
  type CollectionSource,
  type CollectionSourceKind,
  type PersonCredits,
  type PersonOrder,
  type UserCollection,
} from '@/state/collections';
import type { SearchDiscoverFilters } from '@/state/settings';
import { sourceSummary } from './resolveSources';

type Template = CollectionSourceKind['kind'];

const TEMPLATES: Array<{ value: Template; label: string }> = [
  { value: 'tmdbDiscover', label: 'TMDB discover' },
  { value: 'tmdbCollection', label: 'TMDB movie collection' },
  { value: 'person', label: "Person's credits" },
  { value: 'traktList', label: 'Public Trakt list' },
  { value: 'addonCatalog', label: 'Addon catalog' },
];

const field = 'w-full rounded-lg bg-white/[0.06] border border-white/10 px-3 py-2 text-sm text-white focus:outline-none focus:ring-2 focus:ring-white/20';
const select = `${field} [&>option]:bg-neutral-900`;
const primary = 'rounded-lg bg-white px-4 py-2 text-sm font-semibold text-black disabled:opacity-40';

function SearchPicker<T>({
  placeholder,
  search,
  label,
  onPick,
}: {
  placeholder: string;
  search: (query: string) => Promise<T[]>;
  label: (item: T) => string;
  onPick: (item: T) => void;
}) {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<T[] | null>(null);
  const [error, setError] = useState(false);
  const [busy, setBusy] = useState(false);

  const run = async () => {
    if (!query.trim()) return;
    setBusy(true);
    setError(false);
    try {
      setResults(await search(query.trim()));
    } catch {
      setResults(null);
      setError(true);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="space-y-2">
      <div className="flex gap-2">
        <input
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          onKeyDown={(event) => { if (event.key === 'Enter') run(); }}
          placeholder={placeholder}
          className={field}
        />
        <button onClick={run} disabled={busy || !query.trim()} className="rounded-lg bg-white/10 px-3 text-sm font-medium text-white hover:bg-white/20 disabled:opacity-40">Search</button>
      </div>
      {error && <p className="text-sm text-red-400">Search failed. Try again.</p>}
      {results?.length === 0 && <p className="text-sm text-white/50">No results.</p>}
      {!!results?.length && (
        <div className="max-h-44 overflow-y-auto rounded-lg bg-white/[0.04]">
          {results.map((item, index) => (
            <button key={index} onClick={() => onPick(item)} className="block w-full truncate px-3 py-2 text-left text-sm text-white hover:bg-white/10">{label(item)}</button>
          ))}
        </div>
      )}
    </div>
  );
}

function SourceForm({ template, onAdd }: { template: Template; onAdd: (source: CollectionSourceKind) => void }) {
  const [filters, setFilters] = useState<SearchDiscoverFilters>(DEFAULT_DISCOVER_FILTERS);
  const [credits, setCredits] = useState<PersonCredits>('knownFor');
  const [order, setOrder] = useState<PersonOrder>('popularity');
  const [catalogs, setCatalogs] = useState<StremioCatalog[] | null>(null);
  const [catalogsFailed, setCatalogsFailed] = useState(false);

  useEffect(() => {
    if (template !== 'addonCatalog') return;
    setCatalogsFailed(false);
    getCatalogs().then(setCatalogs).catch(() => setCatalogsFailed(true));
  }, [template]);

  switch (template) {
    case 'tmdbDiscover': {
      const genres = DISCOVER_GENRES[filters.mediaType];
      const sortLabel = DISCOVER_SORTS.find((sort) => sort.value === filters.sort)?.label ?? '';
      return (
        <div className="space-y-2">
          <div className="grid grid-cols-3 gap-2">
            <select aria-label="Media type" className={select} value={filters.mediaType} onChange={(event) => setFilters({ ...filters, mediaType: event.target.value as 'movie' | 'tv', genreId: undefined, genreName: undefined })}>
              <option value="movie">Movies</option>
              <option value="tv">TV</option>
            </select>
            <select
              aria-label="Genre"
              className={select}
              value={filters.genreId ?? ''}
              onChange={(event) => {
                const genre = genres.find((g) => g.id === Number(event.target.value));
                setFilters({ ...filters, genreId: genre?.id, genreName: genre?.name });
              }}
            >
              <option value="">Any genre</option>
              {genres.map((genre) => <option key={genre.id} value={genre.id}>{genre.name}</option>)}
            </select>
            <select aria-label="Sort" className={select} value={filters.sort} onChange={(event) => setFilters({ ...filters, sort: event.target.value as SearchDiscoverFilters['sort'] })}>
              {DISCOVER_SORTS.map((sort) => <option key={sort.value} value={sort.value}>{sort.label}</option>)}
            </select>
          </div>
          <button
            className={primary}
            onClick={() => onAdd({
              kind: 'tmdbDiscover',
              filters,
              label: [filters.genreName, filters.mediaType === 'tv' ? 'TV' : 'Movies', sortLabel].filter(Boolean).join(' · '),
            })}
          >
            Add Source
          </button>
        </div>
      );
    }
    case 'tmdbCollection':
      return (
        <SearchPicker<any>
          placeholder="Search for a franchise"
          search={async (query) => ((await tmdbSearchCollections(query)) as any)?.results ?? []}
          label={(item) => item.name}
          onPick={(item) => onAdd({ kind: 'tmdbCollection', id: item.id, name: item.name })}
        />
      );
    case 'person':
      return (
        <div className="space-y-2">
          <div className="grid grid-cols-2 gap-2">
            <select aria-label="Credits" className={select} value={credits} onChange={(event) => setCredits(event.target.value as PersonCredits)}>
              <option value="knownFor">Known for</option>
              <option value="acting">Acting</option>
              <option value="directing">Directing</option>
              <option value="allCrew">All crew work</option>
            </select>
            <select aria-label="Order" className={select} value={order} onChange={(event) => setOrder(event.target.value as PersonOrder)}>
              <option value="popularity">Most popular</option>
              <option value="newest">Newest first</option>
              <option value="oldest">Oldest first</option>
            </select>
          </div>
          <SearchPicker<any>
            placeholder="Search for a person"
            search={async (query) => (((await tmdbSearchPerson('', query)) as any)?.results ?? []).filter((r: any) => r.media_type === 'person')}
            label={(item) => item.name}
            onPick={(item) => onAdd({ kind: 'person', id: item.id, name: item.name, credits, order })}
          />
        </div>
      );
    case 'traktList':
      return (
        <SearchPicker<TraktPublicList>
          placeholder="Search lists, or paste a trakt.tv list URL"
          search={async (query) => {
            const path = publicListPath(query);
            if (path && (query.includes('/') || /^\d+$/.test(query))) return [await getPublicList(path)];
            return searchPublicLists(query);
          }}
          label={(list) => `${list.name}${list.user?.username ? ` · ${list.user.username}` : ''} (${list.item_count ?? 0})`}
          onPick={(list) => onAdd({ kind: 'traktList', id: list.ids.trakt, name: list.name, owner: list.user?.username })}
        />
      );
    case 'addonCatalog':
      if (catalogsFailed) return <p className="text-sm text-red-400">Couldn't load addon catalogs.</p>;
      if (!catalogs) return <p className="text-sm text-white/50">Loading catalogs...</p>;
      if (!catalogs.length) return <p className="text-sm text-white/50">No installed addon offers a catalog.</p>;
      return (
        <div className="max-h-44 overflow-y-auto rounded-lg bg-white/[0.04]">
          {catalogs.map((catalog) => (
            <button
              key={`${catalog.installationId}:${catalog.type}:${catalog.id}`}
              onClick={() => onAdd({
                kind: 'addonCatalog',
                installationId: catalog.installationId,
                addonName: catalog.addonName,
                type: catalog.type,
                catalogId: catalog.id,
                displayName: catalog.name,
              })}
              className="block w-full truncate px-3 py-2 text-left text-sm text-white hover:bg-white/10"
            >
              {catalog.addonName} · {catalog.name} ({catalog.type})
            </button>
          ))}
        </div>
      );
  }
}

export default function CollectionEditor({
  collection,
  onClose,
  onSaved,
}: {
  collection: UserCollection;
  onClose: () => void;
  onSaved?: (collection: UserCollection) => void;
}) {
  const [name, setName] = useState(collection.name);
  const [sources, setSources] = useState<CollectionSource[]>(collection.sources);
  const [showOnHome, setShowOnHome] = useState(collection.showOnHome === true);
  const [template, setTemplate] = useState<Template>('tmdbDiscover');

  const add = (source: CollectionSourceKind) => {
    setSources((current) => [...current, { ...source, sourceId: crypto.randomUUID() }]);
  };

  const save = () => {
    const saved = { ...collection, name: name.trim(), sources, showOnHome };
    saveCollection(saved);
    onSaved?.(saved);
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4" role="dialog" aria-modal="true" aria-label="Edit collection" onClick={onClose}>
      <div className="flex max-h-[90vh] w-full max-w-lg flex-col gap-4 overflow-y-auto rounded-2xl bg-neutral-900 p-6 ring-1 ring-white/10" onClick={(event) => event.stopPropagation()}>
        <h3 className="text-lg font-bold text-white">{collection.name ? 'Edit Collection' : 'New Collection'}</h3>
        <label className="block text-sm font-semibold text-white">
          Name
          <input value={name} onChange={(event) => setName(event.target.value)} maxLength={80} autoFocus className={`mt-1.5 ${field}`} />
        </label>

        <label className="flex items-center justify-between gap-3 text-sm font-semibold text-white">
          <span>
            Show on Home
            <span className="block text-xs font-normal text-white/50">Adds this collection as a row on the Home screen</span>
          </span>
          <input type="checkbox" className="h-4 w-4 accent-brand" checked={showOnHome} onChange={(event) => setShowOnHome(event.target.checked)} />
        </label>

        <div>
          <p className="mb-1.5 text-sm font-semibold text-white">Sources</p>
          {sources.length === 0 && <p className="text-sm text-white/50">Add at least one source below.</p>}
          <div className="space-y-1">
            {sources.map((source) => (
              <div key={source.sourceId} className="flex items-center gap-2 rounded-lg bg-white/[0.06] px-3 py-2">
                <span className="min-w-0 flex-1 truncate text-sm text-white/90">{sourceSummary(source)}</span>
                <button onClick={() => setSources((current) => current.filter((item) => item.sourceId !== source.sourceId))} className="text-sm text-red-400 hover:text-red-300">Remove</button>
              </div>
            ))}
          </div>
        </div>

        <div className="space-y-2 rounded-xl border border-white/10 p-3">
          <select aria-label="Source type" className={select} value={template} onChange={(event) => setTemplate(event.target.value as Template)}>
            {TEMPLATES.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
          </select>
          <SourceForm key={template} template={template} onAdd={add} />
        </div>

        <div className="flex justify-end gap-3">
          <button onClick={onClose} className="rounded-lg bg-white/10 px-4 py-2 text-sm font-medium text-white hover:bg-white/20">Cancel</button>
          <button onClick={save} disabled={!name.trim() || sources.length === 0} className={primary}>Save</button>
        </div>
      </div>
    </div>
  );
}
