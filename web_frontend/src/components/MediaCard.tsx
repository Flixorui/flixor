import SmartImage from './SmartImage';

interface MediaCardProps {
  title: string;
  year?: number;
  posterUrl?: string;
  onClick?: () => void;
}

export function MediaCard({ title, year, posterUrl, onClick }: MediaCardProps) {
  return (
    <div
      className="cursor-pointer group"
      onClick={onClick}
    >
      <div className="relative aspect-[2/3] bg-gray-800 rounded-lg overflow-hidden">
        {posterUrl ? (
          <SmartImage
            url={posterUrl}
            alt={title}
            width={240}
            className="w-full h-full"
            imgClassName="group-hover:scale-105 transition-transform duration-300"
          />
        ) : (
          <div className="w-full h-full flex items-center justify-center bg-gray-800">
            <span className="text-gray-500">No Image</span>
          </div>
        )}
        <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-transparent to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300" />
      </div>
      <div className="mt-2">
        <h3 className="text-sm font-medium truncate group-hover:text-blue-400 transition-colors">
          {title}
        </h3>
        {year && (
          <p className="text-xs text-gray-500">{year}</p>
        )}
      </div>
    </div>
  );
}
