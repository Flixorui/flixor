import SmartImage from './SmartImage';

type BillboardProps = {
  image: string;
  title?: string;
  rating?: string;
  onPlay?: () => void;
};

export default function Billboard({ image, title = '', rating = 'TV-14', onPlay }: BillboardProps) {
  return (
    <div className="bleed" style={{padding: '20px'}}>
      <div className="rounded-2xl overflow-hidden shadow-billboard ring-1 ring-white/10 bg-neutral-900/40 relative">
        <SmartImage url={image} alt={title} width={1280} className="w-full h-[56vh] md:h-[64vh] xl:h-[68vh]" imgClassName="object-cover object-center" priority />
        <div className="absolute inset-0 bg-gradient-to-t from-black via-black/30 to-transparent" />
        <div className="absolute left-6 bottom-6 flex items-center gap-4">
          <button onClick={onPlay} className="px-6 py-2.5 rounded-md font-semibold text-black bg-white hover:bg-neutral-100 shadow-[0_8px_30px_rgba(147,51,234,.35)]">
            ▶ Play
          </button>
          {rating && <span className="px-3 py-1 rounded-md bg-white text-black text-sm font-semibold shadow">{rating}</span>}
        </div>
      </div>
    </div>
  );
}
