import { useEffect, useState, useCallback } from 'react';
import { tmdbPersonCombined, tmdbSearchPerson, tmdbImage, tmdbPersonDetails } from '@/services/tmdb';
import Row from '@/components/Row';
import { useNavigate } from 'react-router-dom';

interface PersonDetails {
  name: string;
  biography?: string;
  birthday?: string;
  deathday?: string;
  place_of_birth?: string;
  profile_path?: string;
  known_for_department?: string;
  popularity?: number;
}

export default function PersonModal({ open, onClose, personId, name, tmdbKey }: { open: boolean; onClose: () => void; personId?: string; name?: string; tmdbKey?: string }) {
  const navigate = useNavigate();
  const [personDetails, setPersonDetails] = useState<PersonDetails | null>(null);
  const [movies, setMovies] = useState<any[]>([]);
  const [tv, setTv] = useState<any[]>([]);
  const [knownFor, setKnownFor] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [showFullBio, setShowFullBio] = useState(false);
  const [resolvedPersonId, setResolvedPersonId] = useState<string | undefined>(undefined);

  useEffect(() => {
    if (!open || !tmdbKey) return;
    setLoading(true);
    setShowFullBio(false);

    (async () => {
      let pid = personId;
      try {
        if (!pid && name) {
          const res: any = await tmdbSearchPerson(tmdbKey, name);
          pid = res.results?.[0]?.id ? String(res.results[0].id) : undefined;
        }
        if (!pid) {
          setLoading(false);
          return;
        }

        setResolvedPersonId(pid);

        // Fetch person details and combined credits in parallel
        const [details, combined]: [any, any] = await Promise.all([
          tmdbPersonDetails(tmdbKey, pid),
          tmdbPersonCombined(tmdbKey, pid),
        ]);

        // Set person details
        setPersonDetails({
          name: details.name || name || 'Unknown',
          biography: details.biography,
          birthday: details.birthday,
          deathday: details.deathday,
          place_of_birth: details.place_of_birth,
          profile_path: details.profile_path,
          known_for_department: details.known_for_department,
          popularity: details.popularity,
        });

        // Process filmography
        const allCredits = combined.cast || [];

        // Sort by popularity/vote_count to get "known for"
        const sortedCredits = [...allCredits].sort((a: any, b: any) => (b.vote_count || 0) - (a.vote_count || 0));
        const known = sortedCredits.slice(0, 6).map((x: any) => ({
          id: x.media_type === 'movie' ? `tmdb:movie:${x.id}` : `tmdb:tv:${x.id}`,
          title: x.title || x.name,
          image: tmdbImage(x.poster_path, 'w342') || tmdbImage(x.backdrop_path, 'w780'),
          year: (x.release_date || x.first_air_date || '').split('-')[0],
          character: x.character,
        }));
        setKnownFor(known);

        // Movies sorted by release date (newest first)
        const movieCredits = allCredits
          .filter((c: any) => c.media_type === 'movie')
          .sort((a: any, b: any) => (b.release_date || '').localeCompare(a.release_date || ''))
          .slice(0, 20)
          .map((x: any) => ({
            id: `tmdb:movie:${x.id}`,
            title: x.title,
            image: tmdbImage(x.backdrop_path, 'w780') || tmdbImage(x.poster_path, 'w500'),
            subtitle: x.character,
          }));
        setMovies(movieCredits);

        // TV shows sorted by first air date (newest first)
        const tvCredits = allCredits
          .filter((c: any) => c.media_type === 'tv')
          .sort((a: any, b: any) => (b.first_air_date || '').localeCompare(a.first_air_date || ''))
          .slice(0, 20)
          .map((x: any) => ({
            id: `tmdb:tv:${x.id}`,
            title: x.name,
            image: tmdbImage(x.backdrop_path, 'w780') || tmdbImage(x.poster_path, 'w500'),
            subtitle: x.character,
          }));
        setTv(tvCredits);
      } catch (e) {
        console.error('Error loading person details:', e);
      } finally {
        setLoading(false);
      }
    })();
  }, [open, personId, name, tmdbKey]);

  const handleEscape = useCallback((e: KeyboardEvent) => {
    if (e.key === 'Escape') onClose();
  }, [onClose]);

  useEffect(() => {
    if (open) {
      document.addEventListener('keydown', handleEscape);
      document.body.style.overflow = 'hidden';
    }
    return () => {
      document.removeEventListener('keydown', handleEscape);
      document.body.style.overflow = '';
    };
  }, [open, handleEscape]);

  const formatAge = (birthday?: string, deathday?: string) => {
    if (!birthday) return null;
    const birth = new Date(birthday);
    const end = deathday ? new Date(deathday) : new Date();
    const age = Math.floor((end.getTime() - birth.getTime()) / (365.25 * 24 * 60 * 60 * 1000));
    return age;
  };

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-[120] bg-black/80 backdrop-blur-sm flex items-center justify-center p-4" onClick={onClose}>
      <div
        className="w-full max-w-5xl max-h-[90vh] overflow-auto bg-neutral-950 border border-white/10 rounded-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        {loading ? (
          <div className="p-8 flex items-center justify-center">
            <div className="w-8 h-8 border-2 border-white/20 border-t-white rounded-full animate-spin" />
          </div>
        ) : (
          <>
            {/* Header with profile */}
            <div className="relative p-6 pb-4 border-b border-white/10">
              {/* Close button */}
              <button
                onClick={onClose}
                className="absolute top-4 right-4 p-2 rounded-full hover:bg-white/10 transition-colors"
              >
                <svg className="w-6 h-6 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>

              <div className="flex gap-6">
                {/* Profile Image */}
                <div className="flex-shrink-0">
                  {personDetails?.profile_path ? (
                    <img
                      src={tmdbImage(personDetails.profile_path, 'w185') || ''}
                      alt={personDetails?.name}
                      className="w-28 h-28 md:w-36 md:h-36 rounded-full object-cover ring-2 ring-white/20"
                    />
                  ) : (
                    <div className="w-28 h-28 md:w-36 md:h-36 rounded-full bg-white/10 flex items-center justify-center">
                      <svg className="w-12 h-12 text-white/30" fill="currentColor" viewBox="0 0 24 24">
                        <path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z" />
                      </svg>
                    </div>
                  )}
                </div>

                {/* Name and Info */}
                <div className="flex-1 min-w-0">
                  <h2 className="text-2xl md:text-3xl font-bold text-white mb-2">{personDetails?.name}</h2>

                  <div className="flex flex-wrap gap-x-4 gap-y-1 text-sm text-white/60 mb-3">
                    {personDetails?.known_for_department && (
                      <span>{personDetails.known_for_department}</span>
                    )}
                    {personDetails?.birthday && (
                      <span>
                        {new Date(personDetails.birthday).toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })}
                        {formatAge(personDetails.birthday, personDetails.deathday) && (
                          <span className="text-white/40"> ({formatAge(personDetails.birthday, personDetails.deathday)} years old)</span>
                        )}
                      </span>
                    )}
                    {personDetails?.place_of_birth && (
                      <span>{personDetails.place_of_birth}</span>
                    )}
                  </div>

                  {/* Biography */}
                  {personDetails?.biography && (
                    <div className="text-sm text-white/80 leading-relaxed">
                      <p className={showFullBio ? '' : 'line-clamp-3'}>
                        {personDetails.biography}
                      </p>
                      {personDetails.biography.length > 200 && (
                        <button
                          onClick={() => setShowFullBio(!showFullBio)}
                          className="text-blue-400 hover:text-blue-300 mt-1"
                        >
                          {showFullBio ? 'Show less' : 'Read more'}
                        </button>
                      )}
                    </div>
                  )}
                </div>
              </div>
            </div>

            {/* Content */}
            <div className="p-6 space-y-8">
              {/* Known For */}
              {knownFor.length > 0 && (
                <div>
                  <h3 className="text-lg font-semibold text-white mb-4">Known For</h3>
                  <div className="grid grid-cols-3 md:grid-cols-6 gap-3">
                    {knownFor.map((item) => (
                      <button
                        key={item.id}
                        onClick={() => {
                          onClose();
                          navigate(`/details/${encodeURIComponent(item.id)}`);
                        }}
                        className="group text-left"
                      >
                        <div className="aspect-[2/3] rounded-lg overflow-hidden bg-white/10 mb-2 ring-1 ring-white/10 group-hover:ring-2 group-hover:ring-white/50 transition-all">
                          {item.image ? (
                            <img src={item.image} alt={item.title} className="w-full h-full object-cover" />
                          ) : (
                            <div className="w-full h-full flex items-center justify-center text-white/20">
                              <svg className="w-8 h-8" fill="currentColor" viewBox="0 0 24 24">
                                <path d="M18 3v2h-2V3H8v2H6V3H4v18h2v-2h2v2h8v-2h2v2h2V3h-2z" />
                              </svg>
                            </div>
                          )}
                        </div>
                        <p className="text-xs text-white/80 line-clamp-1">{item.title}</p>
                        {item.character && (
                          <p className="text-xs text-white/50 line-clamp-1">{item.character}</p>
                        )}
                      </button>
                    ))}
                  </div>
                </div>
              )}

              {/* Movies */}
              {movies.length > 0 && (
                <Row
                  title={`Movies (${movies.length})`}
                  items={movies as any}
                  onItemClick={(id) => {
                    onClose();
                    navigate(`/details/${encodeURIComponent(id)}`);
                  }}
                />
              )}

              {/* TV Shows */}
              {tv.length > 0 && (
                <Row
                  title={`TV Shows (${tv.length})`}
                  items={tv as any}
                  onItemClick={(id) => {
                    onClose();
                    navigate(`/details/${encodeURIComponent(id)}`);
                  }}
                />
              )}

              {/* Empty state */}
              {movies.length === 0 && tv.length === 0 && !loading && (
                <div className="text-center py-12 text-white/50">
                  No filmography found for this person.
                </div>
              )}
            </div>

            {/* Footer hint */}
            <div className="px-6 pb-4 text-center">
              <span className="text-white/30 text-xs">Press ESC or click outside to close</span>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
