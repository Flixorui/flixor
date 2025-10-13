export default function EpisodeSkeletonList({ count = 6 }: { count?: number }) {
  return (
    <div className="mt-4 space-y-3">
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="flex gap-4 items-start py-2">
          <div className="w-8 h-6 skeleton rounded" />
          <div className="w-44 h-24 rounded-xl overflow-hidden bg-neutral-800 skeleton" />
          <div className="flex-1">
            <div className="h-4 w-2/5 skeleton rounded mb-2" />
            <div className="h-3 w-4/5 skeleton rounded" />
          </div>
        </div>
      ))}
    </div>
  );
}

