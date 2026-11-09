import { useEffect, useRef, useState } from 'react';
import { addToList, getMyLists, type TraktUserList } from '@/services/traktLists';
import { isTraktConnected, type WatchTarget } from '@/services/watchState';

/** Hero button that adds the title to one of the user's Trakt lists. */
export default function AddToTraktList({
  target,
  onMessage,
}: {
  target?: WatchTarget;
  onMessage: (message: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const [lists, setLists] = useState<TraktUserList[] | null>(null);
  const [failed, setFailed] = useState(false);
  const [busy, setBusy] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    setFailed(false);
    getMyLists().then(setLists).catch(() => setFailed(true));
    const onDown = (event: MouseEvent) => {
      if (!ref.current?.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', onDown);
    return () => document.removeEventListener('mousedown', onDown);
  }, [open]);

  if (!target || !isTraktConnected() || target.kind === 'season') return null;

  const add = async (list: TraktUserList) => {
    setBusy(true);
    try {
      await addToList(list.ids.trakt, target);
      onMessage(`Added to ${list.name}`);
      setOpen(false);
    } catch (error) {
      onMessage(error instanceof Error ? error.message : "Couldn't add to list");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="relative" ref={ref}>
      <button
        onClick={() => setOpen((value) => !value)}
        className="w-10 h-10 flex items-center justify-center rounded-full bg-white/10 border border-white/30 text-white hover:bg-white/20 transition-all"
        title="Add to Trakt list"
        aria-label="Add to Trakt list"
        aria-haspopup="menu"
        aria-expanded={open}
      >
        <svg className="h-5 w-5" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" d="M4 6h16M4 12h10M4 18h10m5-5v8m-4-4h8" />
        </svg>
      </button>
      {open && (
        <div role="menu" className="absolute bottom-12 left-0 z-30 max-h-72 w-60 overflow-y-auto rounded-xl bg-neutral-900 py-1 shadow-2xl ring-1 ring-white/10">
          {failed && <p className="px-3 py-2 text-sm text-white/60">Couldn't load your lists.</p>}
          {!failed && lists === null && <p className="px-3 py-2 text-sm text-white/60">Loading...</p>}
          {!failed && lists?.length === 0 && <p className="px-3 py-2 text-sm text-white/60">You have no Trakt lists yet. Create one in My List.</p>}
          {lists?.map((list) => (
            <button
              key={list.ids.trakt}
              role="menuitem"
              disabled={busy}
              onClick={() => add(list)}
              className="block w-full truncate px-3 py-2 text-left text-sm text-white hover:bg-white/10 disabled:opacity-50"
            >
              {list.name}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
