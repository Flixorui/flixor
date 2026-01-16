type ContentRatingBadgeProps = {
  rating?: string;
  size?: 'sm' | 'md' | 'lg';
  className?: string;
};

// Image badge types that have PNG assets
type ImageRatingType = 'g' | 'pg' | 'pg13' | 'r' | 'tvg' | 'tvpg' | 'tv14' | 'tvma' | 'unrated';

// Map normalized ratings to image file names
const ratingImageMap: Record<string, ImageRatingType> = {
  'G': 'g',
  'PG': 'pg',
  'PG-13': 'pg13',
  'R': 'r',
  'TV-G': 'tvg',
  'TV-PG': 'tvpg',
  'TV-14': 'tv14',
  'TV-MA': 'tvma',
  'NR': 'unrated',
  'UNRATED': 'unrated',
};

// Color mappings for fallback text badges
const ratingColors: Record<string, { bg: string; text: string; border: string }> = {
  // Movie ratings
  G: { bg: 'bg-green-600/20', text: 'text-green-400', border: 'border-green-500/50' },
  PG: { bg: 'bg-yellow-600/20', text: 'text-yellow-400', border: 'border-yellow-500/50' },
  'PG-13': { bg: 'bg-orange-600/20', text: 'text-orange-400', border: 'border-orange-500/50' },
  R: { bg: 'bg-red-600/20', text: 'text-red-400', border: 'border-red-500/50' },
  'NC-17': { bg: 'bg-red-800/20', text: 'text-red-300', border: 'border-red-600/50' },
  NR: { bg: 'bg-neutral-600/20', text: 'text-neutral-400', border: 'border-neutral-500/50' },

  // TV ratings
  'TV-Y': { bg: 'bg-green-600/20', text: 'text-green-400', border: 'border-green-500/50' },
  'TV-Y7': { bg: 'bg-green-600/20', text: 'text-green-400', border: 'border-green-500/50' },
  'TV-G': { bg: 'bg-green-600/20', text: 'text-green-400', border: 'border-green-500/50' },
  'TV-PG': { bg: 'bg-yellow-600/20', text: 'text-yellow-400', border: 'border-yellow-500/50' },
  'TV-14': { bg: 'bg-orange-600/20', text: 'text-orange-400', border: 'border-orange-500/50' },
  'TV-MA': { bg: 'bg-red-600/20', text: 'text-red-400', border: 'border-red-500/50' },
};

// Normalize rating strings
function normalizeRating(rating: string): string {
  const normalized = rating.toUpperCase().trim();
  // Handle common variations
  const mappings: Record<string, string> = {
    'TVPG': 'TV-PG',
    'TVMA': 'TV-MA',
    'TV14': 'TV-14',
    'TVY': 'TV-Y',
    'TVY7': 'TV-Y7',
    'TVG': 'TV-G',
    'PG13': 'PG-13',
    'NC17': 'NC-17',
    'NOTRATED': 'NR',
    'NOT RATED': 'NR',
    'UNRATED': 'NR',
  };
  return mappings[normalized.replace(/[\s-]/g, '')] || normalized;
}

// Size presets - matching Mobile's 18x27 aspect ratio
const sizeClasses = {
  sm: 'h-3.5', // 14px - compact for hero
  md: 'h-[22px]', // Medium (default)
  lg: 'h-[28px]', // Large
};

const textSizeClasses = {
  sm: 'text-[9px] px-1 py-px',
  md: 'text-xs px-2 py-0.5',
  lg: 'text-sm px-2.5 py-1',
};

type ImageBadgeProps = {
  type: ImageRatingType;
  size: 'sm' | 'md' | 'lg';
  className?: string;
};

function ImageBadge({ type, size, className = '' }: ImageBadgeProps) {
  return (
    <img
      src={`/badges/${type}.png`}
      alt={type.toUpperCase()}
      className={`${sizeClasses[size]} w-auto object-contain ${className}`}
      loading="lazy"
    />
  );
}

type TextBadgeProps = {
  label: string;
  colors: { bg: string; text: string; border: string };
  size: 'sm' | 'md' | 'lg';
  className?: string;
};

function TextBadge({ label, colors, size, className = '' }: TextBadgeProps) {
  return (
    <span
      className={`
        inline-flex items-center justify-center
        font-bold tracking-wide
        rounded border
        ${colors.bg} ${colors.text} ${colors.border}
        ${textSizeClasses[size]}
        ${className}
      `}
    >
      {label}
    </span>
  );
}

export default function ContentRatingBadge({ rating, size = 'md', className = '' }: ContentRatingBadgeProps) {
  if (!rating) return null;

  const normalizedRating = normalizeRating(rating);
  const imageType = ratingImageMap[normalizedRating];

  // Use image if available
  if (imageType) {
    return <ImageBadge type={imageType} size={size} className={className} />;
  }

  // Fallback to text badge
  const colors = ratingColors[normalizedRating] || {
    bg: 'bg-neutral-600/20',
    text: 'text-neutral-400',
    border: 'border-neutral-500/50',
  };

  return <TextBadge label={normalizedRating} colors={colors} size={size} className={className} />;
}

// Compact version that just shows the rating text (no image)
export function ContentRatingText({ rating, className = '' }: Pick<ContentRatingBadgeProps, 'rating' | 'className'>) {
  if (!rating) return null;

  const normalizedRating = normalizeRating(rating);
  const colors = ratingColors[normalizedRating] || { text: 'text-neutral-400' };

  return <span className={`font-medium ${colors.text} ${className}`}>{normalizedRating}</span>;
}

// Helper to determine if a rating indicates mature content
export function isMatureRating(rating?: string): boolean {
  if (!rating) return false;
  const normalized = normalizeRating(rating);
  return ['R', 'NC-17', 'TV-MA', 'TV-14'].includes(normalized);
}
