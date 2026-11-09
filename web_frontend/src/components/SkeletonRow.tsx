import { useSettings } from '@/state/settings';
import { useCardStyle } from './cards/cardStyle';

export default function SkeletonRow({ count, title }: { count?: number; title?: string }) {
  const settings = useSettings();
  const style = useCardStyle();
  const poster = settings.rowLayout === 'poster';
  const cards = count ?? (poster ? 8 : 5);
  return (
    <section className="mb-4">
      <div className="row-gutter">
        <div className="row-band">
          <div className="py-[15px]">
            {title ? (
              <h2 className="text-white font-bold text-lg cursor-default">{title}</h2>
            ) : (
              <div className="h-[28px] w-48 skeleton rounded" />
            )}
          </div>
          <div className="row-edge no-scrollbar overflow-x-hidden py-[15px]">
            <div className="flex gap-3 md:gap-4 w-max">
              {Array.from({ length: cards }).map((_, i) => (
                <div key={i} className="flex-shrink-0" style={{ width: poster ? style.posterWidth : `min(${style.landscapeWidth}px, 86vw)` }}>
                  <div className={`relative overflow-hidden bg-neutral-800 skeleton ${poster ? 'aspect-[2/3]' : 'aspect-[2/1]'}`} style={{ borderRadius: style.radius }} />
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
