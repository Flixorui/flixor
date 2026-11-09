import SmartImage from '@/components/SmartImage';
import DetailsSectionHeading, { DetailsHorizontalRow } from './DetailsSectionHeading';

export interface DetailsCastMember {
  id?: string;
  name: string;
  img?: string;
  character?: string;
}

export default function DetailsCastSection({
  cast,
  onSelect,
}: {
  cast: DetailsCastMember[];
  onSelect: (member: DetailsCastMember) => void;
}) {
  if (!cast.length) return null;
  return (
    <section>
      <DetailsSectionHeading className="mb-4">Cast &amp; Crew</DetailsSectionHeading>
      <DetailsHorizontalRow gapClass="gap-4">
        {cast.map((member, index) => (
          <button
            key={`${member.id ?? member.name}-${index}`}
            onClick={() => onSelect(member)}
            className="w-24 flex-shrink-0 text-center transition-opacity hover:opacity-80"
          >
            <div className="mx-auto mb-2 h-24 w-24 overflow-hidden rounded-full bg-white/10 ring-1 ring-white/10">
              {member.img ? (
                <SmartImage url={member.img} alt={member.name} width={96} className="h-full w-full" imgClassName="object-cover" />
              ) : (
                <div className="flex h-full w-full items-center justify-center text-white/20">
                  <svg className="h-8 w-8" fill="currentColor" viewBox="0 0 24 24">
                    <path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z" />
                  </svg>
                </div>
              )}
            </div>
            <p className="truncate text-xs font-medium text-white">{member.name}</p>
            {member.character && <p className="truncate text-xs text-white/50">{member.character}</p>}
          </button>
        ))}
      </DetailsHorizontalRow>
    </section>
  );
}
