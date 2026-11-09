import { VideoSeekSlider } from 'react-video-seek-slider';
import type { PlayerChapter, PlayerMarker } from '../types';

interface Props {
  currentTime: number;
  duration: number;
  buffered: number;
  markers: PlayerMarker[];
  chapters: PlayerChapter[];
  previewUrl?: (ms: number) => string;
  onSeek: (seconds: number) => void;
}

const RANGE_COLORS: Record<string, string> = {
  intro: 'rgba(96, 165, 250, 0.9)',
  recap: 'rgba(167, 139, 250, 0.9)',
  credits: 'rgba(250, 204, 21, 0.9)',
  preview: 'rgba(52, 211, 153, 0.9)',
};

/** The seek slider, with intro and credits ranges and chapter ticks drawn on the track. */
export default function SeekBar({ currentTime, duration, buffered, markers, chapters, previewUrl, onSeek }: Props) {
  const percent = (seconds: number) => `${Math.min(100, Math.max(0, (seconds / duration) * 100))}%`;
  const ranges = markers.filter((marker) => RANGE_COLORS[marker.type]);
  const ticks = chapters.filter((chapter) => chapter.start > 1);

  return (
    <div className="relative h-full">
      <VideoSeekSlider
        max={duration * 1000}
        currentTime={currentTime * 1000}
        bufferTime={buffered * 1000}
        onChange={(ms: number) => onSeek(ms / 1000)}
        offset={0}
        secondsPrefix="00:00:"
        minutesPrefix="00:"
        getPreviewScreenUrl={previewUrl}
      />
      {duration > 0 && (
        <div className="absolute left-0 right-0 top-0 h-[18px] pointer-events-none z-[5]" aria-hidden>
          {ranges.map((marker) => (
            <span
              key={marker.id}
              className="absolute top-1/2 -translate-y-1/2 h-[3px] rounded-sm"
              style={{
                left: percent(marker.start),
                width: `calc(${percent(marker.end)} - ${percent(marker.start)})`,
                backgroundColor: RANGE_COLORS[marker.type],
              }}
            />
          ))}
          {ticks.map((chapter) => (
            <span
              key={chapter.id}
              className="absolute top-1/2 -translate-y-1/2 h-[9px] w-[2px] bg-white/80"
              style={{ left: percent(chapter.start) }}
            />
          ))}
        </div>
      )}
    </div>
  );
}
