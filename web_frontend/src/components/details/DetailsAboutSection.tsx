import { Link } from 'react-router-dom';
import ContentRatingBadge from '@/components/ContentRatingBadge';
import RatingsBar from '@/components/RatingsBar';
import DetailsSectionHeading from './DetailsSectionHeading';
import type { useDetailsData } from './useDetailsData';

function InfoRow({ label, value }: { label: string; value?: string }) {
  if (!value) return null;
  return (
    <div>
      <p className="text-sm text-white/50">{label}</p>
      <p className="text-sm text-white/90">{value}</p>
    </div>
  );
}

function SubHeading({ children }: { children: string }) {
  return <h3 className="mb-4 text-base font-bold text-white">{children}</h3>;
}

const hdrLabel = (videoProfile?: string) => {
  const profile = videoProfile?.toLowerCase() ?? '';
  if (profile.includes('dv')) return 'Dolby Vision';
  return profile.includes('hdr') ? 'HDR10' : undefined;
};

export default function DetailsAboutSection({ data }: { data: ReturnType<typeof useDetailsData> }) {
  const {
    title, tagline, overview, meta, kind, productionCompanies, networks, releaseDate, year, status, budget, revenue,
    originalLanguage, studio, director, writers, numberOfSeasons, numberOfEpisodes, audioTracks2, subtitleTracks2, tech,
    container, bitrate, fileSize, ratings,
  } = data;

  const entities = kind === 'movie' ? productionCompanies : networks;
  const entityKind = kind === 'movie' ? 'company' : 'network';

  return (
    <section className="space-y-8 pr-[var(--page-gutter)]">
      <div>
        <DetailsSectionHeading className="mb-3">About</DetailsSectionHeading>
        {tagline && <p className="mb-4 italic text-white/70">"{tagline}"</p>}
        <div className="flex items-start justify-between rounded-xl bg-white/5 p-4 ring-1 ring-white/10">
          <div className="flex-1">
            <h4 className="mb-1 text-lg font-semibold text-white">{title}</h4>
            <p className="mb-3 text-sm text-white/60">{meta.genres?.join(', ').toUpperCase()}</p>
            <p className="text-sm leading-relaxed text-white/80">{overview}</p>
          </div>
          {meta.rating && (
            <div className="ml-4 flex-shrink-0">
              <ContentRatingBadge rating={meta.rating} size="lg" />
            </div>
          )}
        </div>
      </div>

      {entities.length > 0 && (
        <div>
          <SubHeading>{kind === 'movie' ? 'Production' : 'Network'}</SubHeading>
          <div className="flex flex-wrap gap-3">
            {entities.slice(0, 6).map((entity) => (
              <Link
                key={entity.id}
                to={`/browse/${entityKind}/${entity.id}`}
                title={entity.name}
                className="flex min-h-[44px] items-center justify-center rounded-xl bg-white px-4 py-3 transition-opacity hover:opacity-80"
              >
                {entity.logo ? (
                  <img src={entity.logo} alt={entity.name} className="h-6 w-auto max-w-[80px] object-contain" style={{ filter: 'brightness(0)' }} />
                ) : (
                  <span className="text-sm font-semibold text-black">{entity.name}</span>
                )}
              </Link>
            ))}
          </div>
        </div>
      )}

      <div className="grid grid-cols-1 gap-8 md:grid-cols-3">
        <div>
          <SubHeading>Information</SubHeading>
          <div className="space-y-3">
            <InfoRow label="Released" value={releaseDate ? new Date(releaseDate).getFullYear().toString() : year} />
            <InfoRow label="Run Time" value={meta.runtime ? `${Math.floor(meta.runtime / 60)}h ${meta.runtime % 60}min` : undefined} />
            <InfoRow label="Rated" value={meta.rating} />
            <InfoRow label="Status" value={status} />
            {kind === 'movie' && !!budget && <InfoRow label="Budget" value={`$${(budget / 1000000).toFixed(0)}M`} />}
            {kind === 'movie' && !!revenue && <InfoRow label="Box Office" value={`$${(revenue / 1000000).toFixed(1)}M`} />}
            <InfoRow label="Studio" value={studio} />
            <InfoRow label="Directed By" value={director} />
            {writers.length > 0 && <InfoRow label="Written By" value={writers.join(', ')} />}
            {kind === 'tv' && !!numberOfSeasons && <InfoRow label="Seasons" value={String(numberOfSeasons)} />}
            {kind === 'tv' && !!numberOfEpisodes && <InfoRow label="Episodes" value={String(numberOfEpisodes)} />}
          </div>
        </div>
        <div>
          <SubHeading>Languages</SubHeading>
          <div className="space-y-3">
            <InfoRow label="Original Audio" value={originalLanguage?.toUpperCase()} />
            {audioTracks2.length > 0 && <InfoRow label="Audio" value={audioTracks2.join(', ')} />}
            {subtitleTracks2.length > 0 && <InfoRow label="Subtitles" value={subtitleTracks2.join(', ')} />}
          </div>
        </div>
        <div>
          <SubHeading>Technical</SubHeading>
          <div className="space-y-3">
            <InfoRow label="Resolution" value={tech.resolution} />
            <InfoRow label="Video" value={tech.videoCodec?.toUpperCase()} />
            <InfoRow label="Audio" value={tech.audioCodec ? `${tech.audioCodec.toUpperCase()} ${tech.audioChannels || ''}ch` : undefined} />
            <InfoRow label="HDR" value={hdrLabel(tech.videoProfile)} />
            <InfoRow label="Container" value={container?.toUpperCase()} />
            <InfoRow label="Bitrate" value={bitrate ? `${bitrate} Kbps` : undefined} />
            <InfoRow label="File Size" value={fileSize ? `${fileSize.toFixed(1)} GB` : undefined} />
          </div>
        </div>
      </div>

      {ratings && (
        <div>
          <SubHeading>Ratings</SubHeading>
          <RatingsBar {...ratings} />
        </div>
      )}
    </section>
  );
}
