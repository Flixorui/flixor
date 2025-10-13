export default function SkeletonRow({ count = 8, title }: { count?: number; title?: string }) {
  return (
    <section className="py-2 my-5">
      <div className="page-gutter">
        <div className="row-band">
          <div className="pt-4">
            <div className="flex items-baseline gap-3 group">
              {title ? (
                <h2 className="text-neutral-200 font-semibold text-xl md:text-2xl cursor-default">{title}</h2>
              ) : (
                <div className="h-6 w-48 skeleton rounded" />
              )}
            </div>
          </div>
          <div className="row-edge no-scrollbar overflow-x-auto" style={{ padding: '12px 0 16px 0' }}>
            <div className="flex gap-8 pb-4 w-max">
              {Array.from({ length: count }).map((_, i) => (
                <div key={i} className="group flex-shrink-0 w-[360px] md:w-[420px]">
                  <div className="relative aspect-[2/1] rounded-xl overflow-hidden bg-neutral-800 skeleton" />
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
