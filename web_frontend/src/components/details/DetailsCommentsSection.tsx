import { useCallback, useEffect, useRef, useState } from 'react';
import {
  CommentsUnresolvedError,
  fetchComments,
  resolveCommentsPath,
  type TraktComment,
  type TraktCommentSort,
} from '@/services/traktComments';
import type { WatchTarget } from '@/services/watchState';
import DetailsSectionHeading, { DetailsHorizontalRow } from './DetailsSectionHeading';

type Phase = 'loading' | 'loaded' | 'failed';

const SORTS: Array<{ value: TraktCommentSort; label: string }> = [
  { value: 'likes', label: 'Most Liked' },
  { value: 'newest', label: 'Newest' },
];

const PAGE_SIZE = 10;

function formatDate(value?: string): string | undefined {
  if (!value) return undefined;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? undefined : date.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
}

const authorOf = (comment: TraktComment) => comment.user?.username || comment.user?.name || 'Trakt user';
const ratingOf = (comment: TraktComment) => comment.user_rating ?? comment.user_stats?.rating ?? undefined;
const hasSpoiler = (comment: TraktComment) => comment.spoiler || /\[spoiler\]/i.test(comment.comment);
const displayText = (comment: TraktComment) => comment.comment.replace(/\[\/?spoiler\]/gi, '').trim();

function CommentMeta({ comment }: { comment: TraktComment }) {
  const rating = ratingOf(comment);
  return (
    <span className="flex items-center gap-2 text-xs text-white/50">
      {rating != null && (
        <span className="flex items-center gap-1 text-amber-300">
          <svg className="h-3 w-3" fill="currentColor" viewBox="0 0 24 24"><path d="M12 17.27 18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z" /></svg>
          {rating}
        </span>
      )}
      {(comment.likes ?? 0) > 0 && <span>{comment.likes} likes</span>}
      {formatDate(comment.created_at) && <span>{formatDate(comment.created_at)}</span>}
    </span>
  );
}

function Badge({ children }: { children: string }) {
  return <span className="rounded bg-white/10 px-1.5 py-0.5 text-[10px] font-semibold uppercase text-white/70">{children}</span>;
}

function CommentCard({ comment, onOpen }: { comment: TraktComment; onOpen: () => void }) {
  return (
    <button
      onClick={onOpen}
      aria-label={`Open comment by ${authorOf(comment)}`}
      className="flex h-[180px] w-[320px] flex-shrink-0 flex-col rounded-xl bg-white/[0.07] p-4 text-left ring-1 ring-white/10 transition hover:bg-white/[0.11]"
    >
      <span className="mb-2 flex items-center gap-2">
        <span className="min-w-0 flex-1 truncate text-sm font-semibold text-white">{authorOf(comment)}</span>
        {comment.review && <Badge>Review</Badge>}
      </span>
      <span className={`flex-1 overflow-hidden text-sm leading-relaxed line-clamp-5 ${hasSpoiler(comment) ? 'text-amber-300/90' : 'text-white/80'}`}>
        {hasSpoiler(comment) ? 'This comment contains spoilers.' : displayText(comment)}
      </span>
      <span className="mt-2"><CommentMeta comment={comment} /></span>
    </button>
  );
}

function PlaceholderCard() {
  return <div className="h-[180px] w-[320px] flex-shrink-0 animate-pulse rounded-xl bg-white/[0.06]" />;
}

function CommentPopup({
  comment,
  position,
  revealed,
  canPrevious,
  canNext,
  onPrevious,
  onNext,
  onReveal,
  onClose,
}: {
  comment: TraktComment;
  position: string;
  revealed: boolean;
  canPrevious: boolean;
  canNext: boolean;
  onPrevious: () => void;
  onNext: () => void;
  onReveal: () => void;
  onClose: () => void;
}) {
  const hidden = hasSpoiler(comment) && !revealed;

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose();
      else if (event.key === 'ArrowLeft' && canPrevious) onPrevious();
      else if (event.key === 'ArrowRight' && canNext) onNext();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [canPrevious, canNext, onPrevious, onNext, onClose]);

  const navButton = (label: string, enabled: boolean, onClick: () => void, path: string) => (
    <button
      onClick={onClick}
      disabled={!enabled}
      aria-label={label}
      className="flex h-9 w-9 items-center justify-center rounded-full bg-white/10 text-white transition hover:bg-white/20 disabled:opacity-30"
    >
      <svg className="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d={path} />
      </svg>
    </button>
  );

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4" role="dialog" aria-modal="true" aria-label="Comment" onClick={onClose}>
      <div className="flex max-h-[80vh] w-full max-w-[720px] flex-col rounded-2xl bg-neutral-900 p-6 ring-1 ring-white/10" onClick={(event) => event.stopPropagation()}>
        <div className="mb-4 flex items-center gap-2">
          <span className="min-w-0 flex-1 truncate text-lg font-bold text-white">{authorOf(comment)}</span>
          {comment.review && <Badge>Review</Badge>}
          {hasSpoiler(comment) && <Badge>Spoiler</Badge>}
          {navButton('Previous comment', canPrevious, onPrevious, 'M15 19l-7-7 7-7')}
          <span className="text-xs tabular-nums text-white/60">{position}</span>
          {navButton('Next comment', canNext, onNext, 'M9 5l7 7-7 7')}
          {navButton('Close', true, onClose, 'M6 18L18 6M6 6l12 12')}
        </div>
        <div className="mb-3"><CommentMeta comment={comment} /></div>
        <div className="relative flex-1 overflow-y-auto">
          <p className={`whitespace-pre-wrap text-[15px] leading-relaxed text-white/85 ${hidden ? 'blur-md select-none' : ''}`}>{displayText(comment)}</p>
          {hidden && (
            <div className="absolute inset-0 flex items-center justify-center">
              <button onClick={onReveal} className="rounded-full bg-white px-4 py-2 text-sm font-semibold text-black">Show spoiler</button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

export default function DetailsCommentsSection({ target }: { target?: WatchTarget }) {
  const [phase, setPhase] = useState<Phase>('loading');
  const [message, setMessage] = useState('');
  const [comments, setComments] = useState<TraktComment[]>([]);
  const [total, setTotal] = useState(0);
  const [sort, setSort] = useState<TraktCommentSort>('likes');
  const [hasMore, setHasMore] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [revealed, setRevealed] = useState<Set<number>>(new Set());
  const [selected, setSelected] = useState<number | null>(null);
  const [attempt, setAttempt] = useState(0);

  const pathRef = useRef<string | null>(null);
  const pageRef = useRef(1);
  const generation = useRef(0);

  const targetKey = target ? JSON.stringify(target) : '';

  useEffect(() => {
    if (!target) return;
    const gen = ++generation.current;
    const controller = new AbortController();
    setPhase('loading');
    setComments([]);
    setSelected(null);
    setHasMore(false);
    setTotal(0);
    pageRef.current = 1;
    pathRef.current = null;

    (async () => {
      try {
        const path = await resolveCommentsPath(target);
        if (gen !== generation.current) return;
        pathRef.current = path;
        const page = await fetchComments(path, sort, 1, PAGE_SIZE, controller.signal);
        if (gen !== generation.current) return;
        setComments(page.items);
        setTotal(page.itemCount);
        setHasMore(page.hasMore);
        pageRef.current = page.page;
        setPhase('loaded');
      } catch (error) {
        if (gen !== generation.current || controller.signal.aborted) return;
        setMessage(error instanceof CommentsUnresolvedError
          ? "This title couldn't be found on Trakt."
          : "Couldn't load comments from Trakt.");
        setPhase('failed');
      }
    })();

    return () => controller.abort();
    // `targetKey` stands in for the target's fields.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [targetKey, sort, attempt]);

  const loadMore = useCallback(async (): Promise<boolean> => {
    if (!hasMore || loadingMore || !pathRef.current) return false;
    const gen = generation.current;
    setLoadingMore(true);
    try {
      const page = await fetchComments(pathRef.current, sort, pageRef.current + 1, PAGE_SIZE);
      if (gen !== generation.current) return false;
      pageRef.current = page.page;
      setHasMore(page.hasMore);
      setTotal((count) => Math.max(count, page.itemCount));
      setComments((current) => {
        const known = new Set(current.map((c) => c.id));
        return [...current, ...page.items.filter((c) => !known.has(c.id))];
      });
      return true;
    } catch {
      return false;
    } finally {
      if (gen === generation.current) setLoadingMore(false);
    }
  }, [hasMore, loadingMore, sort]);

  const onRowScroll = (event: React.UIEvent<HTMLDivElement>) => {
    const element = event.currentTarget;
    if (element.scrollLeft + element.clientWidth > element.scrollWidth - 700) loadMore();
  };

  const selectNext = async () => {
    if (selected == null) return;
    if (selected + 1 < comments.length) setSelected(selected + 1);
    else if (await loadMore()) setSelected(selected + 1);
  };

  if (!target) return null;

  const selectedComment = selected != null ? comments[selected] : undefined;

  return (
    <section>
      <div className="mb-4 flex flex-wrap items-baseline gap-2 pr-[var(--page-gutter)]">
        <DetailsSectionHeading>Comments</DetailsSectionHeading>
        {total > 0 && <span className="text-sm text-white/50">{total}</span>}
        <span className="text-xs text-white/40">from Trakt</span>
        <div className="ml-auto flex rounded-lg bg-white/10 p-0.5" role="group" aria-label="Sort comments">
          {SORTS.map((option) => (
            <button
              key={option.value}
              onClick={() => { setRevealed(new Set()); setSort(option.value); }}
              disabled={phase === 'loading'}
              aria-pressed={sort === option.value}
              className={`rounded-md px-3 py-1 text-xs font-semibold transition ${sort === option.value ? 'bg-white text-black' : 'text-white/70 hover:text-white'}`}
            >
              {option.label}
            </button>
          ))}
        </div>
      </div>

      {phase === 'loading' && (
        <DetailsHorizontalRow>
          {Array.from({ length: 3 }).map((_, index) => <PlaceholderCard key={index} />)}
        </DetailsHorizontalRow>
      )}

      {phase === 'failed' && (
        <div className="rounded-xl bg-white/[0.06] p-6 text-center text-sm text-white/60 mr-[var(--page-gutter)]">
          <p>{message}</p>
          <button onClick={() => setAttempt((n) => n + 1)} className="mt-3 rounded-full bg-white/15 px-4 py-1.5 font-semibold text-white hover:bg-white/25">Try Again</button>
        </div>
      )}

      {phase === 'loaded' && (comments.length === 0 ? (
        <div className="rounded-xl bg-white/[0.06] p-6 text-center text-sm text-white/60 mr-[var(--page-gutter)]">No comments on Trakt yet.</div>
      ) : (
        <div onScroll={onRowScroll} className="row-edge overflow-x-auto no-scrollbar">
          <div className="flex w-max gap-3">
            {comments.map((comment, index) => (
              <CommentCard
                key={comment.id}
                comment={comment}
                onOpen={() => setSelected(index)}
              />
            ))}
            {loadingMore && <PlaceholderCard />}
          </div>
        </div>
      ))}

      {selectedComment && selected != null && (
        <CommentPopup
          comment={selectedComment}
          position={`${selected + 1} / ${Math.max(total, comments.length)}`}
          revealed={revealed.has(selectedComment.id)}
          canPrevious={selected > 0}
          canNext={selected + 1 < comments.length || hasMore}
          onPrevious={() => setSelected((value) => (value != null && value > 0 ? value - 1 : value))}
          onNext={selectNext}
          onReveal={() => setRevealed((current) => new Set(current).add(selectedComment.id))}
          onClose={() => setSelected(null)}
        />
      )}
    </section>
  );
}
