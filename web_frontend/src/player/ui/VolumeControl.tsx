import { useCallback, useRef, useState } from 'react';
import { VolumeIcon } from './icons';

interface Props {
  volume: number;
  onChange: (volume: number) => void;
}

const BUTTON = 'w-12 h-12 sm:w-14 sm:h-14 bg-transparent flex items-center justify-center text-white transition-transform duration-150 ease-out hover:scale-110 focus:outline-none focus-visible:ring-2 focus-visible:ring-white/30 rounded';

/** Pointer-driven rather than a range input, which sticks in WebKit. */
export default function VolumeControl({ volume, onChange }: Props) {
  const [open, setOpen] = useState(false);
  const [dragging, setDragging] = useState(false);
  const trackRef = useRef<HTMLDivElement | null>(null);

  const updateFrom = useCallback((clientX: number) => {
    const rect = trackRef.current?.getBoundingClientRect();
    if (!rect || rect.width === 0) return;
    onChange(Math.max(0, Math.min(1, (clientX - rect.left) / rect.width)));
  }, [onChange]);

  return (
    <div className="flex items-center">
      <button className={BUTTON} onClick={() => setOpen(!open)} aria-label="Volume" title="Volume">
        <VolumeIcon level={volume} />
      </button>
      <div className="ml-3 overflow-hidden transition-[width] duration-200" style={{ width: open ? '18rem' : 0 }}>
        <div className={`bg-black/90 rounded-2xl px-4 py-3 ring-1 ring-white/10 shadow-xl w-[18rem] transition-all duration-200 ${open ? 'opacity-100 translate-x-0' : 'opacity-0 -translate-x-2'}`}>
          <div className="flex items-center gap-3">
            <VolumeIcon level={volume} className="w-5 h-5 text-white flex-shrink-0" />
            <div className="relative flex-1 h-1.5 select-none">
              <div className="absolute inset-0 bg-white/20 rounded-full overflow-hidden">
                <div className="h-full rounded-full bg-brand" style={{ width: `${Math.round(volume * 100)}%` }} />
              </div>
              <div
                className={`absolute top-1/2 -translate-y-1/2 -translate-x-1/2 z-20 pointer-events-none transition-transform ${dragging ? 'scale-105' : ''}`}
                style={{ left: `${Math.round(volume * 100)}%` }}
                aria-hidden
              >
                <div className="w-5 h-5 rounded-full border-4 border-white/60 flex items-center justify-center">
                  <span className="block w-2.5 h-2.5 rounded-full bg-white" />
                </div>
              </div>
              <div
                ref={trackRef}
                role="slider"
                aria-label="Volume"
                aria-valuemin={0}
                aria-valuemax={100}
                aria-valuenow={Math.round(volume * 100)}
                tabIndex={0}
                className="absolute -inset-y-2 inset-x-0 cursor-pointer"
                style={{ touchAction: 'none' }}
                onPointerDown={(e) => {
                  e.preventDefault();
                  e.currentTarget.setPointerCapture(e.pointerId);
                  setDragging(true);
                  updateFrom(e.clientX);
                }}
                onPointerMove={(e) => { if (dragging) updateFrom(e.clientX); }}
                onPointerUp={() => setDragging(false)}
                onPointerCancel={() => setDragging(false)}
                onKeyDown={(e) => {
                  e.stopPropagation();
                  if (e.key === 'ArrowLeft' || e.key === 'ArrowDown') { e.preventDefault(); onChange(Math.max(0, volume - 0.05)); }
                  if (e.key === 'ArrowRight' || e.key === 'ArrowUp') { e.preventDefault(); onChange(Math.min(1, volume + 0.05)); }
                  if (e.key === 'Home') { e.preventDefault(); onChange(0); }
                  if (e.key === 'End') { e.preventDefault(); onChange(1); }
                }}
              />
            </div>
            <div className="w-12 text-right text-xs text-white/70">{Math.round(volume * 100)}%</div>
          </div>
        </div>
      </div>
    </div>
  );
}
