import { useEffect, useMemo, useState } from 'react';
import { useNavigate, useParams, useSearchParams } from 'react-router-dom';
import SmartImage from '@/components/SmartImage';
import DetailsMediaRow, { type DetailsMediaItem } from '@/components/details/DetailsMediaRow';
import TitleGrid, { type TitleGridItem } from '@/components/details/TitleGrid';
import { tmdbImage, tmdbPersonCombined, tmdbPersonDetails, tmdbSearchPerson } from '@/services/tmdb';

type Department = 'acting' | 'crew';
type MediaFilter = 'all' | 'movies' | 'tv';
type SortOrder = 'popular' | 'newest' | 'oldest';

const NON_FICTION_GENRES = new Set([99, 10763, 10764, 10767]);

interface Credit {
  id: number;
  media_type: 'movie' | 'tv';
  title?: string;
  name?: string;
  poster_path?: string;
  backdrop_path?: string;
  release_date?: string;
  first_air_date?: string;
  popularity?: number;
  vote_count?: number;
  genre_ids?: number[];
  character?: string;
  job?: string;
}

const creditDate = (credit: Credit) => credit.release_date || credit.first_air_date || '';
const creditKey = (credit: Credit) => `${credit.media_type}:${credit.id}`;

/** One entry per title. Roles and jobs on the same title are joined. */
function dedupeCredits(credits: Credit[]): Credit[] {
  const merged = new Map<string, Credit>();
  for (const credit of credits) {
    const existing = merged.get(creditKey(credit));
    if (!existing) {
      merged.set(creditKey(credit), { ...credit });
      continue;
    }
    const join = (a?: string, b?: string) => (a && b && !a.includes(b) ? `${a}, ${b}` : a || b);
    existing.character = join(existing.character, credit.character);
    existing.job = join(existing.job, credit.job);
  }
  return [...merged.values()];
}

function sortCredits(credits: Credit[], order: SortOrder): Credit[] {
  const sorted = [...credits];
  if (order === 'popular') {
    sorted.sort((a, b) => (b.popularity ?? 0) - (a.popularity ?? 0));
  } else {
    // Undated entries go last either way.
    const direction = order === 'newest' ? -1 : 1;
    sorted.sort((a, b) => {
      const [dateA, dateB] = [creditDate(a), creditDate(b)];
      if (!dateA || !dateB) return dateA ? -1 : dateB ? 1 : 0;
      return dateA.localeCompare(dateB) * direction;
    });
  }
  return sorted;
}

const creditRoute = (credit: Credit) => `tmdb:${credit.media_type === 'tv' ? 'tv' : 'movie'}:${credit.id}`;

function toGridItem(credit: Credit, department: Department): TitleGridItem {
  const year = creditDate(credit).slice(0, 4);
  const role = department === 'acting' ? credit.character : credit.job;
  return {
    id: creditRoute(credit),
    title: credit.title || credit.name || '',
    image: tmdbImage(credit.poster_path, 'w500'),
    subtitle: [year, role].filter(Boolean).join(' · ') || undefined,
  };
}

const age = (birthday: string, end?: string) => {
  const from = new Date(birthday);
  const to = end ? new Date(end) : new Date();
  let years = to.getFullYear() - from.getFullYear();
  if (to.getMonth() < from.getMonth() || (to.getMonth() === from.getMonth() && to.getDate() < from.getDate())) years -= 1;
  return years;
};

const formatDate = (value: string) =>
  new Date(value).toLocaleDateString(undefined, { year: 'numeric', month: 'long', day: 'numeric' });

export default function Person() {
  const { id: routeId } = useParams();
  const nav = useNavigate();
  const [params] = useSearchParams();
  const name = params.get('name') || undefined;

  const [person, setPerson] = useState<any | null>(null);
  const [cast, setCast] = useState<Credit[]>([]);
  const [crew, setCrew] = useState<Credit[]>([]);
  const [phase, setPhase] = useState<'loading' | 'loaded' | 'failed'>('loading');
  const [attempt, setAttempt] = useState(0);
  const [department, setDepartment] = useState<Department>('acting');
  const [mediaFilter, setMediaFilter] = useState<MediaFilter>('all');
  const [sort, setSort] = useState<SortOrder>('popular');
  const [bioExpanded, setBioExpanded] = useState(false);

  useEffect(() => {
    let alive = true;
    setPhase('loading');
    (async () => {
      try {
        let personId = routeId;
        if (!personId && name) {
          const search: any = await tmdbSearchPerson('', name);
          const match = (search?.results || []).find((result: any) => result.media_type === 'person');
          personId = match?.id ? String(match.id) : undefined;
        }
        if (!personId) throw new Error('not found');
        const [details, credits]: any[] = await Promise.all([tmdbPersonDetails('', personId), tmdbPersonCombined('', personId)]);
        if (!alive) return;
        const castCredits = dedupeCredits(credits?.cast || []);
        const crewCredits = dedupeCredits(credits?.crew || []);
        setPerson(details);
        setCast(castCredits);
        setCrew(crewCredits);
        const prefersCrew = (details?.known_for_department ?? 'Acting') !== 'Acting';
        setDepartment((prefersCrew && crewCredits.length) || (!castCredits.length && crewCredits.length) ? 'crew' : 'acting');
        setPhase('loaded');
      } catch {
        if (alive) setPhase('failed');
      }
    })();
    return () => { alive = false; };
  }, [routeId, name, attempt]);

  const knownFor = useMemo<DetailsMediaItem[]>(() => {
    const prefersCrew = (person?.known_for_department ?? 'Acting') !== 'Acting';
    const source = prefersCrew && crew.length ? crew : cast.length ? cast : crew;
    return source
      .filter((credit) => {
        if (!credit.poster_path) return false;
        if (credit.genre_ids?.some((genre) => NON_FICTION_GENRES.has(genre))) return false;
        const character = credit.character?.toLowerCase() ?? '';
        return !(character === 'self' || character.startsWith('self ') || character.startsWith('himself') || character.startsWith('herself'));
      })
      .sort((a, b) => (b.vote_count ?? 0) - (a.vote_count ?? 0))
      .slice(0, 12)
      .map((credit) => ({
        id: creditRoute(credit),
        title: credit.title || credit.name || '',
        image: tmdbImage(credit.backdrop_path, 'w780') || tmdbImage(credit.poster_path, 'w500'),
        poster: tmdbImage(credit.poster_path, 'w500'),
      }));
  }, [person, cast, crew]);

  const credits = useMemo(() => {
    const source = department === 'acting' ? cast : crew;
    const filtered = source.filter((credit) => {
      if (mediaFilter === 'movies') return credit.media_type !== 'tv';
      if (mediaFilter === 'tv') return credit.media_type === 'tv';
      return true;
    });
    return sortCredits(filtered, sort).map((credit) => toGridItem(credit, department));
  }, [department, cast, crew, mediaFilter, sort]);

  if (phase === 'loading') {
    return (
      <div className="page-gutter flex gap-8 py-10">
        <div className="h-72 w-48 flex-shrink-0 animate-pulse rounded-2xl bg-white/10" />
        <div className="flex-1 space-y-3">
          <div className="h-8 w-64 animate-pulse rounded bg-white/10" />
          <div className="h-4 w-full animate-pulse rounded bg-white/10" />
          <div className="h-4 w-3/4 animate-pulse rounded bg-white/10" />
        </div>
      </div>
    );
  }

  if (phase === 'failed' || !person) {
    return (
      <div className="page-gutter py-24 text-center text-white/60">
        <p>{name ? `Couldn't find "${name}" on TMDB.` : "Couldn't load this person."}</p>
        <button onClick={() => setAttempt((n) => n + 1)} className="mt-3 rounded-full bg-white/15 px-4 py-1.5 font-semibold text-white hover:bg-white/25">Try Again</button>
      </div>
    );
  }

  const photo = tmdbImage(person.profile_path, 'w500');
  const biography: string = person.biography || '';
  const isLongBio = biography.length > 480;
  const filterButton = (active: boolean, label: string, onClick: () => void) => (
    <button
      key={label}
      onClick={onClick}
      aria-pressed={active}
      className={`rounded-full px-3.5 py-1.5 text-sm font-semibold transition ${active ? 'bg-white text-black' : 'bg-white/10 text-white hover:bg-white/20'}`}
    >
      {label}
    </button>
  );

  return (
    <div className="page-gutter space-y-10 pb-16 pt-8">
      <header className="flex flex-col gap-8 md:flex-row">
        <div className="h-72 w-48 flex-shrink-0 overflow-hidden rounded-2xl bg-white/10 ring-1 ring-white/10">
          {photo && <SmartImage url={photo} alt={person.name} width={384} className="h-full w-full" imgClassName="object-cover" />}
        </div>
        <div className="min-w-0 flex-1">
          <h1 className="text-4xl font-bold text-white">{person.name}</h1>
          <dl className="mt-3 flex flex-wrap gap-x-8 gap-y-2 text-sm">
            {person.known_for_department && <div><dt className="text-white/50">Known for</dt><dd className="text-white/90">{person.known_for_department}</dd></div>}
            {person.birthday && (
              <div>
                <dt className="text-white/50">Born</dt>
                <dd className="text-white/90">{formatDate(person.birthday)}{!person.deathday && ` (age ${age(person.birthday)})`}</dd>
              </div>
            )}
            {person.deathday && <div><dt className="text-white/50">Died</dt><dd className="text-white/90">{formatDate(person.deathday)}{person.birthday && ` (age ${age(person.birthday, person.deathday)})`}</dd></div>}
            {person.place_of_birth && <div><dt className="text-white/50">Birthplace</dt><dd className="text-white/90">{person.place_of_birth}</dd></div>}
          </dl>
          {biography && (
            <div className="mt-4 max-w-3xl">
              <p className={`whitespace-pre-line text-sm leading-relaxed text-white/80 ${!bioExpanded && isLongBio ? 'line-clamp-6' : ''}`}>{biography}</p>
              {isLongBio && (
                <button onClick={() => setBioExpanded((value) => !value)} className="mt-1 text-sm font-semibold text-white hover:text-white/80">
                  {bioExpanded ? 'Show less' : 'Read more'}
                </button>
              )}
            </div>
          )}
        </div>
      </header>

      {knownFor.length > 0 && <DetailsMediaRow title="Known For" items={knownFor} onSelect={(id) => nav(`/details/${encodeURIComponent(id)}`)} />}

      <section>
        <h2 className="mb-4 text-[22px] font-bold leading-7 text-white">Filmography</h2>
        <div className="mb-6 flex flex-wrap items-center gap-2">
          {cast.length > 0 && crew.length > 0 && (
            <>
              {filterButton(department === 'acting', `Acting (${cast.length})`, () => setDepartment('acting'))}
              {filterButton(department === 'crew', `Crew (${crew.length})`, () => setDepartment('crew'))}
              <span className="mx-1 h-5 w-px bg-white/15" />
            </>
          )}
          {filterButton(mediaFilter === 'all', 'All', () => setMediaFilter('all'))}
          {filterButton(mediaFilter === 'movies', 'Movies', () => setMediaFilter('movies'))}
          {filterButton(mediaFilter === 'tv', 'TV', () => setMediaFilter('tv'))}
          <span className="mx-1 h-5 w-px bg-white/15" />
          {filterButton(sort === 'popular', 'Popular', () => setSort('popular'))}
          {filterButton(sort === 'newest', 'Newest', () => setSort('newest'))}
          {filterButton(sort === 'oldest', 'Oldest', () => setSort('oldest'))}
        </div>
        {credits.length ? <TitleGrid items={credits} /> : <p className="py-10 text-center text-white/60">No credits to show.</p>}
      </section>
    </div>
  );
}
