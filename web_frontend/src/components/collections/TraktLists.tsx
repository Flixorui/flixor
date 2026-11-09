import { useCallback, useEffect, useMemo, useState } from 'react';
import TitleGrid from '@/components/details/TitleGrid';
import { tmdbDetails, tmdbImage } from '@/services/tmdb';
import {
  createList,
  deleteList,
  getListItems,
  getMyLists,
  listEntriesToItems,
  removeEntryFromList,
  updateList,
  type ListGridItem,
  type TraktListPrivacy,
  type TraktUserList,
} from '@/services/traktLists';

const PRIVACY: Array<{ value: TraktListPrivacy; label: string }> = [
  { value: 'private', label: 'Private' },
  { value: 'friends', label: 'Friends' },
  { value: 'public', label: 'Public' },
];

function ListEditor({
  list,
  onSaved,
  onClose,
}: {
  list?: TraktUserList;
  onSaved: (list: TraktUserList) => void;
  onClose: () => void;
}) {
  const [name, setName] = useState(list?.name ?? '');
  const [description, setDescription] = useState(list?.description ?? '');
  const [privacy, setPrivacy] = useState<TraktListPrivacy>(list?.privacy ?? 'private');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const save = async () => {
    setSaving(true);
    setError(null);
    try {
      const input = { name: name.trim(), description: description.trim(), privacy };
      onSaved(list ? await updateList(list.ids.trakt, input) : await createList(input));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't save the list");
      setSaving(false);
    }
  };

  const field = 'w-full rounded-lg bg-white/[0.06] border border-white/10 px-3 py-2 text-sm text-white focus:outline-none focus:ring-2 focus:ring-white/20';

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4" role="dialog" aria-modal="true" aria-label={list ? 'Edit list' : 'New list'} onClick={onClose}>
      <div className="w-full max-w-md space-y-4 rounded-2xl bg-neutral-900 p-6 ring-1 ring-white/10" onClick={(event) => event.stopPropagation()}>
        <h3 className="text-lg font-bold text-white">{list ? 'Edit List' : 'New List'}</h3>
        <label className="block text-sm font-semibold text-white">
          Name
          <input value={name} onChange={(event) => setName(event.target.value)} maxLength={100} autoFocus className={`mt-1.5 ${field}`} />
        </label>
        <label className="block text-sm font-semibold text-white">
          Description
          <textarea value={description} onChange={(event) => setDescription(event.target.value)} rows={3} className={`mt-1.5 ${field}`} />
        </label>
        <div>
          <p className="mb-1.5 text-sm font-semibold text-white">Privacy</p>
          <div className="flex gap-2">
            {PRIVACY.map((option) => (
              <button
                key={option.value}
                onClick={() => setPrivacy(option.value)}
                aria-pressed={privacy === option.value}
                className={`flex-1 rounded-lg py-2 text-sm font-semibold ${privacy === option.value ? 'bg-white text-black' : 'bg-white/10 text-white hover:bg-white/20'}`}
              >
                {option.label}
              </button>
            ))}
          </div>
        </div>
        {error && <p className="text-sm text-red-400">{error}</p>}
        <div className="flex justify-end gap-3">
          <button onClick={onClose} className="rounded-lg bg-white/10 px-4 py-2 text-sm font-medium text-white hover:bg-white/20">Cancel</button>
          <button onClick={save} disabled={saving || !name.trim()} className="rounded-lg bg-white px-4 py-2 text-sm font-semibold text-black disabled:opacity-40">
            {saving ? 'Saving...' : 'Save'}
          </button>
        </div>
      </div>
    </div>
  );
}

const chip = (selected: boolean) =>
  `flex-shrink-0 rounded-full px-4 py-1.5 text-sm font-semibold transition ${selected ? 'bg-white text-black' : 'bg-white/10 text-white hover:bg-white/20'}`;

/** Chip row: the merged My List, each Trakt list with its count, and New List. */
export function TraktListSwitcher({
  myListCount,
  selectedId,
  onSelect,
  lists,
  listsFailed,
  onRetry,
  onCreate,
}: {
  myListCount: number;
  selectedId: number | null;
  onSelect: (id: number | null) => void;
  lists: TraktUserList[];
  listsFailed: boolean;
  onRetry: () => void;
  onCreate: () => void;
}) {
  return (
    <div className="mb-6 flex items-center gap-2 overflow-x-auto no-scrollbar pb-1">
      <button onClick={() => onSelect(null)} className={chip(selectedId === null)}>My List ({myListCount})</button>
      {lists.map((list) => (
        <button key={list.ids.trakt} onClick={() => onSelect(list.ids.trakt)} className={chip(selectedId === list.ids.trakt)} title={list.name}>
          {list.name.length > 32 ? `${list.name.slice(0, 32)}…` : list.name} ({list.item_count ?? 0})
        </button>
      ))}
      {listsFailed && <button onClick={onRetry} className="flex-shrink-0 text-sm font-medium text-amber-300">Couldn't load lists. Retry</button>}
      <button onClick={onCreate} className="flex-shrink-0 rounded-full border border-white/30 px-4 py-1.5 text-sm font-semibold text-white hover:bg-white/10">+ New List</button>
    </div>
  );
}

function TraktListContent({
  list,
  onEdit,
  onDeleted,
  onCountChange,
  onMessage,
}: {
  list: TraktUserList;
  onEdit: () => void;
  onDeleted: () => void;
  onCountChange: (delta: number) => void;
  onMessage: (message: string) => void;
}) {
  const [items, setItems] = useState<ListGridItem[]>([]);
  const [phase, setPhase] = useState<'loading' | 'loaded' | 'failed'>('loading');
  const [attempt, setAttempt] = useState(0);
  const listId = list.ids.trakt;

  useEffect(() => {
    let alive = true;
    setPhase('loading');
    (async () => {
      try {
        const base = listEntriesToItems(await getListItems(listId));
        if (!alive) return;
        setItems(base);
        setPhase('loaded');
        // Trakt has no artwork, so posters come from TMDB in small batches.
        for (let index = 0; index < base.length && alive; index += 8) {
          const batch = base.slice(index, index + 8);
          const posters = await Promise.all(batch.map(async (item) => {
            const [, media, id] = item.id.split(':');
            const details: any = await tmdbDetails('', media as 'movie' | 'tv', id).catch(() => null);
            return [item.id, tmdbImage(details?.poster_path, 'w500')] as const;
          }));
          if (!alive) return;
          const found = new Map(posters);
          setItems((current) => current.map((item) => (found.get(item.id) ? { ...item, image: found.get(item.id) } : item)));
        }
      } catch {
        if (alive) setPhase('failed');
      }
    })();
    return () => { alive = false; };
  }, [listId, attempt]);

  const remove = async (item: ListGridItem) => {
    const previous = items;
    setItems(items.filter((candidate) => candidate.id !== item.id));
    try {
      await removeEntryFromList(listId, item.entry);
      onCountChange(-1);
      onMessage(`Removed from ${list.name}`);
    } catch {
      setItems(previous);
      onMessage("Couldn't remove from list");
    }
  };

  const confirmDelete = async () => {
    if (!window.confirm(`Delete "${list.name}" from Trakt? This can't be undone.`)) return;
    try {
      await deleteList(listId);
      onDeleted();
    } catch {
      onMessage("Couldn't delete the list");
    }
  };

  const summary = useMemo(() => [list.privacy[0].toUpperCase() + list.privacy.slice(1), list.description].filter(Boolean).join(' · '), [list]);

  return (
    <div>
      <div className="mb-6 flex items-start justify-between gap-4">
        <p className="text-sm text-white/60">{summary}</p>
        <div className="flex flex-shrink-0 gap-2">
          <button onClick={onEdit} className="rounded-lg bg-white/10 px-3 py-1.5 text-sm font-medium text-white hover:bg-white/20">Edit</button>
          <button onClick={confirmDelete} className="rounded-lg bg-white/10 px-3 py-1.5 text-sm font-medium text-red-400 hover:bg-white/20">Delete</button>
        </div>
      </div>
      {phase === 'loading' && (
        <div className="grid grid-cols-[repeat(auto-fill,minmax(130px,1fr))] gap-4 md:grid-cols-[repeat(auto-fill,minmax(160px,1fr))]">
          {Array.from({ length: 8 }).map((_, index) => <div key={index} className="aspect-[2/3] animate-pulse rounded-xl bg-white/10" />)}
        </div>
      )}
      {phase === 'failed' && (
        <div className="py-16 text-center text-white/60">
          <p>Couldn't load this list.</p>
          <button onClick={() => setAttempt((n) => n + 1)} className="mt-3 rounded-full bg-white/15 px-4 py-1.5 font-semibold text-white hover:bg-white/25">Try Again</button>
        </div>
      )}
      {phase === 'loaded' && !items.length && <p className="py-16 text-center text-white/60">This list is empty. Add titles from their details page.</p>}
      {phase === 'loaded' && items.length > 0 && (
        <TitleGrid
          items={items}
          renderOverlay={(item) => (
            <button
              onClick={() => remove(item as ListGridItem)}
              aria-label={`Remove ${item.title} from ${list.name}`}
              title="Remove from list"
              className="absolute right-2 top-2 flex h-7 w-7 items-center justify-center rounded-full bg-black/70 text-white opacity-0 transition-opacity hover:bg-black focus:opacity-100 group-hover:opacity-100"
            >
              <svg className="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M6 18L18 6M6 6l12 12" /></svg>
            </button>
          )}
        />
      )}
    </div>
  );
}

/** Trakt list state for My List. `children` is the regular My List view. */
export function TraktListsArea({ myListCount, children, onMessage }: { myListCount: number; children: React.ReactNode; onMessage: (message: string) => void }) {
  const [lists, setLists] = useState<TraktUserList[]>([]);
  const [listsFailed, setListsFailed] = useState(false);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [editing, setEditing] = useState<{ list?: TraktUserList } | null>(null);

  const loadLists = useCallback(async () => {
    setListsFailed(false);
    try {
      setLists(await getMyLists());
    } catch {
      setListsFailed(true);
    }
  }, []);

  useEffect(() => { loadLists(); }, [loadLists]);

  const selected = lists.find((list) => list.ids.trakt === selectedId);

  const onSaved = (saved: TraktUserList) => {
    setEditing(null);
    setLists((current) => (current.some((list) => list.ids.trakt === saved.ids.trakt)
      ? current.map((list) => (list.ids.trakt === saved.ids.trakt ? { ...list, ...saved } : list))
      : [...current, saved]));
    setSelectedId(saved.ids.trakt);
  };

  return (
    <>
      <TraktListSwitcher
        myListCount={myListCount}
        selectedId={selected ? selectedId : null}
        onSelect={setSelectedId}
        lists={lists}
        listsFailed={listsFailed}
        onRetry={loadLists}
        onCreate={() => setEditing({})}
      />
      {selected ? (
        <TraktListContent
          key={selected.ids.trakt}
          list={selected}
          onEdit={() => setEditing({ list: selected })}
          onDeleted={() => {
            setSelectedId(null);
            setLists((current) => current.filter((list) => list.ids.trakt !== selected.ids.trakt));
            onMessage('List deleted');
          }}
          onCountChange={(delta) => setLists((current) => current.map((list) => (list.ids.trakt === selected.ids.trakt
            ? { ...list, item_count: Math.max((list.item_count ?? 0) + delta, 0) }
            : list)))}
          onMessage={onMessage}
        />
      ) : children}
      {editing && <ListEditor list={editing.list} onSaved={onSaved} onClose={() => setEditing(null)} />}
    </>
  );
}
