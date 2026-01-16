import { useEffect, useCallback } from 'react';

type TrailerModalProps = {
  isOpen: boolean;
  onClose: () => void;
  youtubeKey?: string;
  videoUrl?: string; // Direct video URL (e.g., from Plex)
  title?: string;
};

export default function TrailerModal({
  isOpen,
  onClose,
  youtubeKey,
  videoUrl,
  title,
}: TrailerModalProps) {
  const handleEscape = useCallback(
    (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    },
    [onClose]
  );

  const handleBackdropClick = useCallback(
    (e: React.MouseEvent) => {
      if (e.target === e.currentTarget) onClose();
    },
    [onClose]
  );

  useEffect(() => {
    if (isOpen) {
      document.addEventListener('keydown', handleEscape);
      document.body.style.overflow = 'hidden';
    }

    return () => {
      document.removeEventListener('keydown', handleEscape);
      document.body.style.overflow = '';
    };
  }, [isOpen, handleEscape]);

  if (!isOpen) return null;

  const hasContent = youtubeKey || videoUrl;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/90 backdrop-blur-sm"
      onClick={handleBackdropClick}
    >
      {/* Modal Container */}
      <div className="relative w-full max-w-5xl mx-4">
        {/* Close Button */}
        <button
          onClick={onClose}
          className="absolute -top-12 right-0 p-2 text-white/70 hover:text-white transition-colors"
          aria-label="Close"
        >
          <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>

        {/* Title */}
        {title && (
          <div className="absolute -top-12 left-0">
            <h2 className="text-white text-lg font-semibold">{title} - Trailer</h2>
          </div>
        )}

        {/* Video Container */}
        <div className="relative aspect-video bg-black rounded-lg overflow-hidden shadow-2xl ring-1 ring-white/10">
          {youtubeKey ? (
            <iframe
              src={`https://www.youtube.com/embed/${youtubeKey}?autoplay=1&rel=0&modestbranding=1&enablejsapi=1`}
              className="absolute inset-0 w-full h-full"
              allow="autoplay; encrypted-media; fullscreen"
              allowFullScreen
            />
          ) : videoUrl ? (
            <video
              src={videoUrl}
              className="absolute inset-0 w-full h-full object-contain"
              autoPlay
              controls
              playsInline
            />
          ) : (
            <div className="absolute inset-0 flex items-center justify-center text-white/50">
              No trailer available
            </div>
          )}
        </div>

        {/* Keyboard hint */}
        <div className="mt-4 text-center">
          <span className="text-white/40 text-sm">Press ESC or click outside to close</span>
        </div>
      </div>
    </div>
  );
}
