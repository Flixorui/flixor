import { useState, useEffect, useCallback } from 'react';
import SmartImage from './SmartImage';

type NextEpisodeCountdownProps = {
  nextEpisode: {
    id: string;
    title: string;
    image?: string;
    episodeInfo?: string; // e.g., "S01E06"
    showTitle?: string;
  };
  countdownSeconds?: number;
  onPlayNext: () => void;
  onCancel: () => void;
};

export default function NextEpisodeCountdown({
  nextEpisode,
  countdownSeconds = 10,
  onPlayNext,
  onCancel,
}: NextEpisodeCountdownProps) {
  const [secondsLeft, setSecondsLeft] = useState(countdownSeconds);

  const handlePlayNext = useCallback(() => {
    onPlayNext();
  }, [onPlayNext]);

  useEffect(() => {
    if (secondsLeft <= 0) {
      handlePlayNext();
      return;
    }

    const timer = setInterval(() => {
      setSecondsLeft((prev) => prev - 1);
    }, 1000);

    return () => clearInterval(timer);
  }, [secondsLeft, handlePlayNext]);

  // Progress percentage for the circular countdown
  const progress = ((countdownSeconds - secondsLeft) / countdownSeconds) * 100;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-sm">
      <div className="max-w-lg w-full mx-4 bg-neutral-900 rounded-2xl overflow-hidden shadow-2xl border border-white/10">
        {/* Episode Preview */}
        <div className="relative aspect-video">
          {nextEpisode.image ? (
            <SmartImage
              url={nextEpisode.image}
              alt={nextEpisode.title}
              width={512}
              className="w-full h-full"
              imgClassName="object-cover"
            />
          ) : (
            <div className="w-full h-full bg-neutral-800 flex items-center justify-center">
              <svg className="w-16 h-16 text-white/20" fill="currentColor" viewBox="0 0 24 24">
                <path d="M18 4l2 4h-3l-2-4h-2l2 4h-3l-2-4H8l2 4H7L5 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V4h-4z" />
              </svg>
            </div>
          )}

          {/* Gradient overlay */}
          <div className="absolute inset-0 bg-gradient-to-t from-neutral-900 via-transparent to-transparent" />

          {/* Episode badge */}
          {nextEpisode.episodeInfo && (
            <span className="absolute top-4 left-4 text-sm font-medium bg-black/70 text-white px-3 py-1 rounded-full">
              {nextEpisode.episodeInfo}
            </span>
          )}
        </div>

        {/* Content */}
        <div className="p-6">
          <p className="text-white/60 text-sm mb-1">Up Next</p>
          {nextEpisode.showTitle && (
            <p className="text-white/80 text-sm mb-1">{nextEpisode.showTitle}</p>
          )}
          <h3 className="text-white text-xl font-semibold mb-6">{nextEpisode.title}</h3>

          {/* Actions */}
          <div className="flex items-center justify-between">
            <button
              onClick={onCancel}
              className="px-5 py-2.5 text-white/80 hover:text-white transition-colors"
            >
              Cancel
            </button>

            <button
              onClick={handlePlayNext}
              className="flex items-center gap-3 px-6 py-3 bg-white text-black font-semibold rounded-lg hover:bg-white/90 transition-all"
            >
              {/* Circular countdown indicator */}
              <div className="relative w-8 h-8">
                <svg className="w-8 h-8 -rotate-90" viewBox="0 0 36 36">
                  {/* Background circle */}
                  <circle
                    cx="18"
                    cy="18"
                    r="16"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2"
                    className="text-black/20"
                  />
                  {/* Progress circle */}
                  <circle
                    cx="18"
                    cy="18"
                    r="16"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2"
                    strokeDasharray={`${progress} 100`}
                    strokeLinecap="round"
                    className="text-black transition-all duration-1000"
                  />
                </svg>
                <span className="absolute inset-0 flex items-center justify-center text-sm font-bold">
                  {secondsLeft}
                </span>
              </div>
              <span>Play Next</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// Hook to manage next episode countdown logic
export function useNextEpisodeCountdown(
  isNearEnd: boolean,
  hasNextEpisode: boolean,
  onPlayNext: () => void
) {
  const [showCountdown, setShowCountdown] = useState(false);
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    if (isNearEnd && hasNextEpisode && !dismissed) {
      setShowCountdown(true);
    }
  }, [isNearEnd, hasNextEpisode, dismissed]);

  const handleCancel = useCallback(() => {
    setShowCountdown(false);
    setDismissed(true);
  }, []);

  const handlePlayNext = useCallback(() => {
    setShowCountdown(false);
    onPlayNext();
  }, [onPlayNext]);

  // Reset dismissed state when episode changes (detected by hasNextEpisode changing)
  useEffect(() => {
    setDismissed(false);
    setShowCountdown(false);
  }, [hasNextEpisode]);

  return {
    showCountdown,
    handleCancel,
    handlePlayNext,
  };
}
