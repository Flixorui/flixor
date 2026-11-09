import { useEffect, useMemo, useState } from 'react';
import { useSettings } from '@/state/settings';
import { activeCueIndex, SubtitleCue } from './parser';

function hexToRgba(hex: string, opacity: number): string {
  const value = hex.replace('#', '');
  const r = parseInt(value.slice(0, 2), 16) || 0;
  const g = parseInt(value.slice(2, 4), 16) || 0;
  const b = parseInt(value.slice(4, 6), 16) || 0;
  return `rgba(${r}, ${g}, ${b}, ${opacity})`;
}

interface Props {
  cues: SubtitleCue[];
  delay: number;
  videoRef: React.RefObject<HTMLVideoElement>;
  /** Real time at the video's 0, for converted streams that start mid-film. */
  timeOffset?: number;
  /** Lifts the text clear of the player controls while they are showing. */
  controlsVisible: boolean;
}

export default function SubtitleOverlay({ cues, delay, videoRef, timeOffset = 0, controlsVisible }: Props) {
  const settings = useSettings();
  const [text, setText] = useState('');

  useEffect(() => {
    if (cues.length === 0) { setText(''); return; }
    const tick = () => {
      const video = videoRef.current;
      if (!video) return;
      const index = activeCueIndex(cues, video.currentTime + timeOffset - delay);
      setText(index >= 0 ? cues[index].text : '');
    };
    tick();
    const timer = setInterval(tick, 100);
    return () => clearInterval(timer);
  }, [cues, delay, videoRef, timeOffset]);

  const fontSize = settings.subtitleFontSize ?? 100;
  const bottomOffset = settings.subtitleOffset ?? 0;
  const border = settings.subtitleBorderSize;
  const textStyle = useMemo<React.CSSProperties>(() => ({
    fontFamily: settings.subtitleFontName || 'inherit',
    fontSize: `calc(clamp(18px, 3.6vh, 46px) * ${fontSize / 100})`,
    fontWeight: settings.subtitleBold ? 700 : 500,
    color: settings.subtitleTextColor,
    backgroundColor: hexToRgba(settings.subtitleBackgroundColor, settings.subtitleBackgroundOpacity),
    WebkitTextStroke: border > 0 ? `${border}px ${settings.subtitleBorderColor}` : undefined,
    paintOrder: 'stroke fill',
    lineHeight: 1.25,
    whiteSpace: 'pre-line',
  }), [settings, fontSize, border]);

  if (!text) return null;
  return (
    <div
      className="absolute left-0 right-0 z-30 flex justify-center px-[6vw] pointer-events-none transition-[bottom] duration-200"
      style={{ bottom: `calc(${controlsVisible ? '128px' : '6vh'} + ${bottomOffset}px)` }}
    >
      <span className="inline-block max-w-[85%] rounded px-2 py-0.5 text-center" style={textStyle}>{text}</span>
    </div>
  );
}
