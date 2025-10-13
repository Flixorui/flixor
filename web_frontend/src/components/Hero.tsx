import SmartImage from './SmartImage';

type HeroProps = { title: string; overview?: string; backdropUrl?: string; cta?: React.ReactNode };
export default function Hero({ title, overview, backdropUrl, cta }: HeroProps) {
  return (
    <div className="relative w-full h-[50vh] md:h-[60vh] overflow-hidden">
      {backdropUrl ? (
        <div className="absolute inset-0">
          <SmartImage url={backdropUrl} alt="backdrop" width={1280} className="w-full h-full" imgClassName="object-cover object-center" priority />
        </div>
      ) : (
        <div className="absolute inset-0 bg-neutral-900" />
      )}
      <div className="absolute inset-0 bg-gradient-to-t from-black via-black/40" />
      <div className="absolute bottom-0 left-0 p-6 md:p-10 max-w-3xl">
        <h1 className="text-3xl md:text-5xl font-bold mb-3">{title}</h1>
        {overview && <p className="text-neutral-300 line-clamp-3 md:line-clamp-4 mb-4">{overview}</p>}
        {cta}
      </div>
    </div>
  );
}
