import PosterCard from './PosterCard';

type Item = { id: string; title: string; image?: string; subtitle?: string; badge?: string };

export default function Carousel({ title, items, onItemClick }: { title: string; items: Item[]; onItemClick?: (id: string) => void }) {
  return (
    <section className="px-4 md:px-6 lg:px-10 py-4">
      <h2 className="text-lg font-semibold mb-3">{title}</h2>
      <div className="">
        <div className="flex gap-3">
          {items.map((it) => (
            <PosterCard key={it.id} {...it} onClick={() => onItemClick?.(it.id)} />
          ))}
        </div>
      </div>
    </section>
  );
}

