import SmartImage from './SmartImage';

type PosterCardProps = {
  title: string;
  image?: string;
  subtitle?: string;
  badge?: string;
  onClick?: () => void;
};

export default function PosterCard({ title, image, subtitle, badge, onClick }: PosterCardProps) {
  return (
    <button onClick={onClick} className="group w-40 flex-shrink-0 text-left">
      <div className="relative rounded-md overflow-hidden aspect-[2/3] bg-neutral-800 ring-1 ring-white/10 transition-[transform,ring] duration-300 group-hover:ring-white/60">
        {image ? (
          <SmartImage url={image} alt={title} width={240} className="w-full h-full" imgClassName="transition-transform group-hover:scale-[1.03]" />
        ) : (
          <div className="w-full h-full skeleton" />
        )}
        {badge && (
          <span className="absolute top-2 left-2 text-xs bg-black/70 px-2 py-0.5 rounded border border-white/10">{badge}</span>
        )}
      </div>
      <div className="pt-2">
        <p className="text-sm font-medium line-clamp-2">{title}</p>
        {subtitle && <p className="text-xs text-neutral-400 line-clamp-1">{subtitle}</p>}
      </div>
    </button>
  );
}
