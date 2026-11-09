import { useEffect, useRef, useState, type ReactNode } from 'react';
import type { WatchTarget } from '@/services/watchState';
import type { DetailsTitleActions } from './useDetailsTitleActions';

const CIRCLE =
  'relative w-10 h-10 flex items-center justify-center rounded-full bg-white/10 border border-white/30 text-white hover:bg-white/20 transition-all disabled:opacity-60';

function Spinner() {
  return <div className="h-4 w-4 animate-spin rounded-full border-2 border-white/30 border-t-white" />;
}

function WatchedIcon({ watched, inProgress }: { watched: boolean; inProgress: boolean }) {
  if (watched) {
    return (
      <svg className="h-5 w-5 text-brand" fill="currentColor" viewBox="0 0 24 24">
        <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z" />
      </svg>
    );
  }
  if (inProgress) {
    return (
      <svg className="h-5 w-5" fill="currentColor" viewBox="0 0 24 24">
        <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18V4c4.41 0 8 3.59 8 8s-3.59 8-8 8z" />
      </svg>
    );
  }
  return (
    <svg className="h-5 w-5" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24">
      <circle cx="12" cy="12" r="9" />
      <path strokeLinecap="round" strokeLinejoin="round" d="m8.5 12 2.5 2.5 4.5-5" />
    </svg>
  );
}

function usePopover() {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    const onDown = (event: MouseEvent) => {
      if (!ref.current?.contains(event.target as Node)) setOpen(false);
    };
    const onKey = (event: KeyboardEvent) => { if (event.key === 'Escape') setOpen(false); };
    document.addEventListener('mousedown', onDown);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('mousedown', onDown);
      document.removeEventListener('keydown', onKey);
    };
  }, [open]);
  return { open, setOpen, ref };
}

function MenuItem({ children, disabled, onClick }: { children: ReactNode; disabled?: boolean; onClick: () => void }) {
  return (
    <button
      role="menuitem"
      disabled={disabled}
      onClick={onClick}
      className="block w-full px-3 py-2 text-left text-sm text-white hover:bg-white/10 disabled:text-white/30 disabled:hover:bg-transparent"
    >
      {children}
    </button>
  );
}

export interface WatchSeasonOption {
  key: string;
  title: string;
  target: WatchTarget;
}

/** Movies and episodes get a toggle. Shows and seasons get a menu. */
export function DetailsWatchedControl({
  actions,
  seasonOptions = [],
}: {
  actions: DetailsTitleActions;
  seasonOptions?: WatchSeasonOption[];
}) {
  const { kind, isWatched, isInProgress, isWorking, progressText, setWatched } = actions;
  const menu = usePopover();
  const [openSeason, setOpenSeason] = useState<string | null>(null);

  if (!kind) return null;
  const watched = isWatched === true;
  const label = watched ? 'Mark as unwatched' : 'Mark as watched';

  if (kind === 'movie' || kind === 'episode') {
    return (
      <button
        onClick={() => setWatched(!watched)}
        disabled={isWorking}
        className={CIRCLE}
        title={label}
        aria-label={label}
        aria-pressed={watched}
      >
        {isWorking ? <Spinner /> : <WatchedIcon watched={watched} inProgress={isInProgress} />}
      </button>
    );
  }

  const noun = kind === 'show' ? 'Show' : 'Season';
  const act = (value: boolean, target?: WatchTarget) => {
    menu.setOpen(false);
    setOpenSeason(null);
    setWatched(value, target);
  };

  return (
    <div className="relative" ref={menu.ref}>
      <button
        onClick={() => menu.setOpen((value) => !value)}
        disabled={isWorking}
        className={CIRCLE}
        title="Watched status"
        aria-label="Watched status"
        aria-haspopup="menu"
        aria-expanded={menu.open}
      >
        {isWorking ? <Spinner /> : <WatchedIcon watched={watched} inProgress={isInProgress} />}
      </button>
      {menu.open && (
        <div role="menu" className="absolute bottom-12 left-0 z-30 w-64 rounded-xl bg-neutral-900 py-1 shadow-2xl ring-1 ring-white/10">
          {progressText && <div className="px-3 py-2 text-xs text-white/50">{progressText}</div>}
          <MenuItem disabled={watched} onClick={() => act(true)}>Mark {noun} as Watched</MenuItem>
          <MenuItem disabled={isWatched === false && !isInProgress} onClick={() => act(false)}>Mark {noun} as Unwatched</MenuItem>
          {seasonOptions.length > 0 && (
            <div className="mt-1 max-h-64 overflow-y-auto border-t border-white/10 pt-1">
              {seasonOptions.map((season) => (
                <div key={season.key}>
                  <MenuItem onClick={() => setOpenSeason((value) => (value === season.key ? null : season.key))}>
                    <span className="flex items-center justify-between">
                      {season.title}
                      <span className="text-white/40">{openSeason === season.key ? '−' : '+'}</span>
                    </span>
                  </MenuItem>
                  {openSeason === season.key && (
                    <div className="bg-white/5">
                      <MenuItem onClick={() => act(true, season.target)}>Mark as Watched</MenuItem>
                      <MenuItem onClick={() => act(false, season.target)}>Mark as Unwatched</MenuItem>
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function Star({ filled, className = 'h-5 w-5' }: { filled: boolean; className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill={filled ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth={filled ? 0 : 1.8}>
      <path strokeLinejoin="round" d="M12 17.27 18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z" />
    </svg>
  );
}

function RatingDialog({
  title,
  initial,
  onSave,
  onRemove,
  onClose,
}: {
  title: string;
  initial: number | null;
  onSave: (value: number) => void;
  onRemove: () => void;
  onClose: () => void;
}) {
  const [value, setValue] = useState<number | null>(initial);
  const [hover, setHover] = useState<number | null>(null);
  const shown = hover ?? value ?? 0;

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4" role="dialog" aria-modal="true" aria-label={`Rate ${title}`} onClick={onClose}>
      <div className="w-full max-w-md rounded-2xl bg-neutral-900 p-6 ring-1 ring-white/10" onClick={(event) => event.stopPropagation()}>
        <h3 className="text-lg font-bold text-white">Rate on Trakt</h3>
        <p className="mt-1 truncate text-sm text-white/60">{title}</p>
        <div className="my-6 flex justify-center gap-1 text-amber-300" onMouseLeave={() => setHover(null)}>
          {Array.from({ length: 10 }, (_, index) => index + 1).map((star) => (
            <button
              key={star}
              onMouseEnter={() => setHover(star)}
              onClick={() => setValue(star)}
              aria-label={`${star} out of 10`}
              aria-pressed={value === star}
              className="p-0.5"
            >
              <Star filled={star <= shown} className="h-7 w-7" />
            </button>
          ))}
        </div>
        <p className="mb-5 text-center text-sm tabular-nums text-white/70">{shown ? `${shown} / 10` : 'Not rated'}</p>
        <div className="flex gap-3">
          {initial != null && (
            <button onClick={onRemove} className="rounded-lg px-4 py-2.5 text-sm font-medium text-red-400 hover:bg-white/10">Remove</button>
          )}
          <div className="flex-1" />
          <button onClick={onClose} className="rounded-lg bg-white/10 px-4 py-2.5 text-sm font-medium text-white hover:bg-white/20">Cancel</button>
          <button
            onClick={() => { if (value != null) onSave(value); }}
            disabled={value == null || value === initial}
            className="rounded-lg bg-white px-4 py-2.5 text-sm font-semibold text-black disabled:opacity-40"
          >
            Save
          </button>
        </div>
      </div>
    </div>
  );
}

export function DetailsRateControl({ actions, title }: { actions: DetailsTitleActions; title: string }) {
  const [open, setOpen] = useState(false);
  const { canRate, userRating, isRatingWorking, rate } = actions;
  if (!canRate) return null;
  return (
    <>
      <button
        onClick={() => setOpen(true)}
        disabled={isRatingWorking}
        className={CIRCLE}
        title={userRating != null ? `Your Trakt rating: ${userRating}/10` : 'Rate on Trakt'}
        aria-label="Rate"
      >
        {isRatingWorking ? (
          <Spinner />
        ) : (
          <span className={userRating != null ? 'text-amber-300' : ''}><Star filled={userRating != null} /></span>
        )}
        {userRating != null && !isRatingWorking && (
          <span className="absolute -right-1 -top-1 rounded-full bg-brand px-1 text-[10px] font-bold text-white">{userRating}</span>
        )}
      </button>
      {open && (
        <RatingDialog
          title={title}
          initial={userRating}
          onSave={(value) => { setOpen(false); rate(value); }}
          onRemove={() => { setOpen(false); rate(null); }}
          onClose={() => setOpen(false)}
        />
      )}
    </>
  );
}
