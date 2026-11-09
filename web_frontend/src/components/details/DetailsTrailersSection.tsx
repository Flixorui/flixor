import DetailsSectionHeading, { DetailsHorizontalRow } from './DetailsSectionHeading';

export interface DetailsTrailer {
  key: string;
  name: string;
  type?: string;
}

export default function DetailsTrailersSection({
  trailers,
  onSelect,
}: {
  trailers: DetailsTrailer[];
  onSelect: (trailer: DetailsTrailer) => void;
}) {
  if (!trailers.length) return null;
  return (
    <section>
      <DetailsSectionHeading className="mb-4">Trailers &amp; Videos</DetailsSectionHeading>
      <DetailsHorizontalRow>
        {trailers.map((trailer) => (
          <button
            key={trailer.key}
            onClick={() => onSelect(trailer)}
            className="group relative w-[240px] flex-shrink-0 overflow-hidden rounded-xl text-left focus:outline-none focus:ring-2 focus:ring-white/50 md:w-[280px]"
          >
            <div className="relative aspect-video bg-black/40">
              <img
                src={`https://img.youtube.com/vi/${trailer.key}/mqdefault.jpg`}
                alt=""
                loading="lazy"
                className="h-full w-full object-cover transition-transform duration-300 group-hover:scale-105"
              />
              {trailer.type && (
                <span className="absolute left-2 top-2 rounded bg-black/70 px-1.5 py-0.5 text-[10px] font-semibold uppercase text-white">
                  {trailer.type}
                </span>
              )}
              <div className="absolute inset-0 flex items-center justify-center bg-black/20 transition-colors group-hover:bg-black/40">
                <div className="flex h-10 w-10 items-center justify-center rounded-full bg-white/90 shadow-lg">
                  <svg className="ml-0.5 h-4 w-4 text-black" fill="currentColor" viewBox="0 0 24 24"><path d="M8 5v14l11-7z" /></svg>
                </div>
              </div>
            </div>
            <p className="mt-2 truncate text-sm text-white/90">{trailer.name}</p>
          </button>
        ))}
      </DetailsHorizontalRow>
    </section>
  );
}
