import { useEffect, useState, type ReactNode } from 'react';
import { saveSettings, useSettings, type PlayerAspectMode } from '@/state/settings';
import { formatTime } from '../format';
import { activeCueIndex, SubtitleCue } from '../subtitles/parser';
import type { SubtitleEngine } from '../subtitles/useSubtitleEngine';
import type { EpisodeBrowser, EpisodeEntry, PlayerChapter, PlayerSession } from '../types';

export const ASPECT_MODES: Array<{ value: PlayerAspectMode; label: string }> = [
  { value: 'fit', label: 'Fit' },
  { value: 'fill', label: 'Fill' },
  { value: 'zoom', label: 'Zoom' },
  { value: 'stretch', label: 'Stretch' },
];

const ROW = 'w-full text-left px-3 py-2 rounded hover:bg-white/10 transition-colors';

function tabClass(active: boolean) {
  return `flex-1 px-4 py-2 text-sm ${active ? 'bg-white/10 text-white' : 'text-white/60 hover:text-white'}`;
}

function PanelShell({ title, onClose, children, width = 'max-w-2xl' }: { title: string; onClose: () => void; children: ReactNode; width?: string }) {
  return (
    <div className="absolute bottom-24 right-6 z-40 max-w-[calc(100vw-3rem)]">
      <div className={`w-[32rem] ${width} max-w-full bg-black/90 rounded-xl ring-1 ring-white/10 shadow-2xl overflow-hidden`}>
        <div className="flex items-center justify-between pl-6 pr-3 py-4 bg-white/10 border-b border-white/10">
          <div className="text-xl font-semibold text-white">{title}</div>
          <button className="px-3 py-1.5 text-sm bg-white/10 hover:bg-white/20 rounded text-white" onClick={onClose}>Close</button>
        </div>
        {children}
      </div>
    </div>
  );
}

export function EpisodesPanel({ browser, onClose }: { browser: EpisodeBrowser; onClose: () => void }) {
  return (
    <PanelShell title="Episodes" onClose={onClose}>
      {browser.seasons.length > 1 && (
        <div className="flex gap-2 overflow-x-auto no-scrollbar px-4 pt-3">
          {browser.seasons.map((season) => (
            <button
              key={season}
              onClick={() => browser.selectSeason(season)}
              className={`flex-shrink-0 px-3 py-1.5 rounded-full text-sm font-semibold ${season === browser.season ? 'bg-white text-black' : 'bg-white/10 text-white hover:bg-white/20'}`}
            >
              {season === 0 ? 'Specials' : `Season ${season}`}
            </button>
          ))}
        </div>
      )}
      <div className="max-h-[55vh] overflow-y-auto p-4">
        {browser.loading && <div className="text-white/80 p-6">Loading episodes…</div>}
        {!browser.loading && browser.episodes.length === 0 && <div className="text-white/70 p-6">No episodes found.</div>}
        {!browser.loading && browser.episodes.length > 0 && (
          <div className="divide-y divide-white/10">
            {browser.episodes.map((episode) => <EpisodeRow key={episode.key} episode={episode} onPlay={browser.play} />)}
          </div>
        )}
      </div>
    </PanelShell>
  );
}

function EpisodeRow({ episode, onPlay }: { episode: EpisodeEntry; onPlay: (entry: EpisodeEntry) => void }) {
  return (
    <button
      className={`w-full text-left flex items-start gap-4 px-2 py-3 transition-colors ${episode.isCurrent ? 'bg-white/10' : 'hover:bg-white/5'}`}
      onClick={() => { if (!episode.isCurrent) onPlay(episode); }}
    >
      <div className="w-40 aspect-video bg-black/30 rounded overflow-hidden flex-shrink-0 relative">
        {episode.thumb && <img src={episode.thumb} alt="" className="w-full h-full object-cover" />}
        {episode.progress !== undefined && (
          <div className="absolute bottom-0 left-0 right-0 h-1.5 bg-white/20">
            <div className="h-full bg-brand" style={{ width: `${Math.round(episode.progress * 100)}%` }} />
          </div>
        )}
      </div>
      <div className="flex-1 min-w-0">
        <div className="text-white font-semibold text-base mb-1">
          {episode.episode}  <span className="font-bold">{episode.title}</span>
          {episode.isCurrent && <span className="ml-2 text-xs text-white/60">Now playing</span>}
        </div>
        {episode.summary && <div className="text-white/80 text-sm leading-relaxed line-clamp-2">{episode.summary}</div>}
      </div>
    </button>
  );
}

export function ChaptersPanel({ chapters, currentTime, onSeek, onClose }: { chapters: PlayerChapter[]; currentTime: number; onSeek: (seconds: number) => void; onClose: () => void }) {
  const activeIndex = chapters.reduce((found, chapter, index) => (chapter.start <= currentTime ? index : found), -1);
  return (
    <PanelShell title="Chapters" onClose={onClose}>
      <div className="max-h-[55vh] overflow-y-auto p-2">
        {chapters.map((chapter, index) => (
          <button key={chapter.id} className={`${ROW} flex justify-between gap-4 ${index === activeIndex ? 'text-brand-bright' : 'text-white'}`} onClick={() => onSeek(chapter.start)}>
            <span className="truncate">{chapter.title}</span>
            <span className="text-white/60 tabular-nums">{formatTime(chapter.start)}</span>
          </button>
        ))}
      </div>
    </PanelShell>
  );
}

const SPEEDS = [0.5, 0.75, 1, 1.25, 1.5, 2];

export function SpeedPanel({ rate, onChange }: { rate: number; onChange: (rate: number) => void }) {
  return (
    <div className="absolute bottom-24 right-6 z-40 w-[28rem] max-w-[92vw] bg-black/95 backdrop-blur rounded-lg ring-1 ring-white/10 shadow-2xl p-5">
      <div className="text-white font-bold text-2xl mb-4">Playback Speed</div>
      <div className="grid grid-cols-6 gap-1">
        {SPEEDS.map((speed) => {
          const selected = Math.abs(rate - speed) < 0.001;
          return (
            <button
              key={speed}
              onClick={() => onChange(speed)}
              className={`py-2 rounded text-sm font-semibold ${selected ? 'bg-white text-black' : 'bg-white/10 text-white hover:bg-white/20'}`}
            >
              {speed}x
            </button>
          );
        })}
      </div>
    </div>
  );
}

export function SettingsPanel({ session, aspect, onAspect, onDone }: {
  session: PlayerSession;
  aspect: PlayerAspectMode;
  onAspect: (mode: PlayerAspectMode) => void;
  onDone: () => void;
}) {
  const tabs = [
    session.quality ? 'quality' : null,
    session.audio.options.length > 0 ? 'audio' : null,
    'aspect',
  ].filter(Boolean) as Array<'quality' | 'audio' | 'aspect'>;
  const [tab, setTab] = useState(tabs[0]);

  return (
    <div className="absolute bottom-24 right-6 z-40 w-80 max-w-[92vw] bg-black/95 backdrop-blur rounded-lg overflow-hidden ring-1 ring-white/10">
      <div className="flex border-b border-white/10">
        {tabs.map((name) => (
          <button key={name} className={tabClass(tab === name)} onClick={() => setTab(name)}>
            {name[0].toUpperCase() + name.slice(1)}
          </button>
        ))}
      </div>
      <div className="max-h-64 overflow-y-auto p-2">
        {tab === 'quality' && session.quality && (
          <>
            {session.quality.warning && <div className="mb-2 p-2 bg-yellow-600/20 rounded text-yellow-300 text-xs">{session.quality.warning}</div>}
            {session.quality.options.map((option) => (
              <button
                key={option.label}
                className={`${ROW} ${session.quality?.value === option.value ? 'text-brand-bright' : 'text-white'}`}
                onClick={() => { session.quality?.set(option.value); onDone(); }}
              >
                {option.label}
                {option.note && (
                  <span className={`text-xs ml-2 ${option.noteTone === 'warn' ? 'text-yellow-400' : option.noteTone === 'good' ? 'text-green-400' : 'text-white/60'}`}>
                    {option.note}
                  </span>
                )}
              </button>
            ))}
          </>
        )}
        {tab === 'audio' && session.audio.options.map((option) => (
          <button
            key={option.id}
            className={`${ROW} ${session.audio.selected === option.id ? 'text-brand-bright' : 'text-white'}`}
            onClick={() => { session.audio.select(option.id); onDone(); }}
          >
            {option.label}
          </button>
        ))}
        {tab === 'aspect' && ASPECT_MODES.map((mode) => (
          <button key={mode.value} className={`${ROW} ${aspect === mode.value ? 'text-brand-bright' : 'text-white'}`} onClick={() => onAspect(mode.value)}>
            {mode.label}
          </button>
        ))}
      </div>
    </div>
  );
}

function Stepper({ label, value, onMinus, onPlus, onReset }: { label: string; value: string; onMinus: () => void; onPlus: () => void; onReset?: () => void }) {
  return (
    <div className="flex items-center justify-between gap-3 py-2">
      <span className="text-white/90 text-sm">{label}</span>
      <div className="flex items-center gap-2">
        {onReset && <button className="text-xs text-white/60 hover:text-white" onClick={onReset}>Reset</button>}
        <button className="w-8 h-8 rounded bg-white/10 hover:bg-white/20 text-white" onClick={onMinus} aria-label={`Decrease ${label}`}>−</button>
        <span className="w-16 text-center text-white text-sm tabular-nums">{value}</span>
        <button className="w-8 h-8 rounded bg-white/10 hover:bg-white/20 text-white" onClick={onPlus} aria-label={`Increase ${label}`}>+</button>
      </div>
    </div>
  );
}

function SyncList({ engine, videoRef }: { engine: SubtitleEngine; videoRef: React.RefObject<HTMLVideoElement> }) {
  const { cues, delay, syncToCue } = engine;
  const [position, setPosition] = useState(() => videoRef.current?.currentTime ?? 0);
  useEffect(() => {
    const timer = setInterval(() => setPosition(videoRef.current?.currentTime ?? 0), 1000);
    return () => clearInterval(timer);
  }, [videoRef]);

  if (cues.length === 0) return <p className="py-6 text-center text-white/60 text-sm">Pick a text subtitle track to sync by line.</p>;

  const around = position - delay;
  const pivot = activeCueIndex(cues, around);
  const nearest = pivot >= 0 ? pivot : cues.findIndex((cue: SubtitleCue) => cue.start >= around);
  const start = Math.max(0, (nearest >= 0 ? nearest : cues.length - 1) - 6);
  return (
    <>
      <p className="text-xs text-white/60 mb-2">Choose the line being spoken right now.</p>
      <div className="max-h-44 overflow-y-auto">
        {cues.slice(start, start + 16).map((cue, index) => (
          <button key={`${cue.start}-${index}`} className={`${ROW} flex gap-3 text-sm ${start + index === pivot ? 'text-brand-bright' : 'text-white'}`} onClick={() => syncToCue(cue)}>
            <span className="text-white/50 tabular-nums">{formatTime(cue.start)}</span>
            <span className="truncate">{cue.text.replace(/\n/g, ' ')}</span>
          </button>
        ))}
      </div>
    </>
  );
}

const SWATCHES = ['#FFFFFF', '#FFD400', '#00E5FF', '#7CFF6B', '#FF6B6B', '#000000'];

function Swatches({ label, value, onChange }: { label: string; value: string; onChange: (color: string) => void }) {
  return (
    <div className="flex items-center justify-between gap-3 py-2">
      <span className="text-white/90 text-sm">{label}</span>
      <div className="flex items-center gap-1.5">
        {SWATCHES.map((color) => (
          <button
            key={color}
            aria-label={`${label} ${color}`}
            onClick={() => onChange(color)}
            className={`w-6 h-6 rounded-full ring-2 ${value.toUpperCase() === color ? 'ring-white' : 'ring-white/20'}`}
            style={{ backgroundColor: color }}
          />
        ))}
      </div>
    </div>
  );
}

export function SubtitlePanel({ engine, videoRef, onClose }: { engine: SubtitleEngine; videoRef: React.RefObject<HTMLVideoElement>; onClose: () => void }) {
  const settings = useSettings();
  const [tab, setTab] = useState<'tracks' | 'sync' | 'style'>('tracks');
  const fontSize = settings.subtitleFontSize ?? 100;
  const offset = settings.subtitleOffset ?? 0;

  return (
    <PanelShell title="Subtitles" onClose={onClose}>
      <div className="flex border-b border-white/10">
        <button className={tabClass(tab === 'tracks')} onClick={() => setTab('tracks')}>Tracks</button>
        <button className={tabClass(tab === 'sync')} onClick={() => setTab('sync')}>Sync</button>
        <button className={tabClass(tab === 'style')} onClick={() => setTab('style')}>Style</button>
      </div>
      <div className="max-h-[50vh] overflow-y-auto p-3">
        {tab === 'tracks' && (
          <>
            {engine.loadError && <div className="mb-2 p-2 rounded bg-red-600/20 text-red-200 text-xs">{engine.loadError}</div>}
            <button className={`${ROW} ${engine.selectedId === null ? 'text-brand-bright' : 'text-white'}`} onClick={() => engine.select(null)}>Off</button>
            {engine.options.map((option) => (
              <button key={option.id} className={`${ROW} ${engine.selectedId === option.id ? 'text-brand-bright' : 'text-white'}`} onClick={() => engine.select(option)}>
                {option.label}
                {option.forced && <span className="text-xs text-white/60 ml-2">Forced</span>}
                {option.delivery === 'burn' && <span className="text-xs text-white/60 ml-2">Needs transcode</span>}
                {engine.selectedId === option.id && engine.loading && <span className="text-xs text-white/60 ml-2">Loading…</span>}
              </button>
            ))}
            {engine.options.length === 0 && <p className="py-4 text-center text-white/60 text-sm">No subtitles available.</p>}
          </>
        )}
        {tab === 'sync' && (
          <>
            <Stepper
              label="Delay"
              value={`${engine.delay > 0 ? '+' : ''}${engine.delay.toFixed(1)} s`}
              onMinus={() => engine.setDelay(engine.delay - 0.1)}
              onPlus={() => engine.setDelay(engine.delay + 0.1)}
              onReset={engine.delay !== 0 ? () => engine.setDelay(0) : undefined}
            />
            <SyncList engine={engine} videoRef={videoRef} />
          </>
        )}
        {tab === 'style' && (
          <>
            <Stepper label="Size" value={`${fontSize}%`} onMinus={() => saveSettings({ subtitleFontSize: Math.max(50, fontSize - 10) })} onPlus={() => saveSettings({ subtitleFontSize: Math.min(200, fontSize + 10) })} />
            <Stepper label="Position" value={`${offset}px`} onMinus={() => saveSettings({ subtitleOffset: offset - 10 })} onPlus={() => saveSettings({ subtitleOffset: offset + 10 })} />
            <Stepper label="Outline" value={`${settings.subtitleBorderSize}`} onMinus={() => saveSettings({ subtitleBorderSize: Math.max(0, settings.subtitleBorderSize - 0.5) })} onPlus={() => saveSettings({ subtitleBorderSize: Math.min(5, settings.subtitleBorderSize + 0.5) })} />
            <Stepper label="Background" value={`${Math.round(settings.subtitleBackgroundOpacity * 100)}%`} onMinus={() => saveSettings({ subtitleBackgroundOpacity: Math.max(0, Math.round((settings.subtitleBackgroundOpacity - 0.1) * 10) / 10) })} onPlus={() => saveSettings({ subtitleBackgroundOpacity: Math.min(1, Math.round((settings.subtitleBackgroundOpacity + 0.1) * 10) / 10) })} />
            <Swatches label="Text" value={settings.subtitleTextColor} onChange={(subtitleTextColor) => saveSettings({ subtitleTextColor })} />
            <label className="flex items-center justify-between py-2 text-white/90 text-sm">
              Bold
              <input type="checkbox" checked={settings.subtitleBold} onChange={(e) => saveSettings({ subtitleBold: e.target.checked })} />
            </label>
            <label className="flex items-center justify-between py-2 text-white/90 text-sm">
              Remove hearing-impaired text
              <input type="checkbox" checked={settings.subtitleFilterSDH} onChange={(e) => saveSettings({ subtitleFilterSDH: e.target.checked })} />
            </label>
          </>
        )}
      </div>
    </PanelShell>
  );
}

export function ShortcutsOverlay({ seekSmall, seekLarge, onClose }: { seekSmall: number; seekLarge: number; onClose: () => void }) {
  const shortcuts: Array<[string, string]> = [
    ['Space / K', 'Play or pause'],
    ['Hold Space', 'Play at 2x'],
    ['← →', `Seek ${seekSmall} s`],
    ['Shift ← →', `Seek ${seekLarge} s`],
    ['J / L', `Seek ${seekLarge} s`],
    ['Option ← →', 'Seek 2 s'],
    ['↑ ↓', 'Volume'],
    ['M', 'Mute'],
    ['[ ]', 'Previous or next chapter'],
    ['Shift N', 'Next episode'],
    ['S', 'Skip intro or credits'],
    ['V', 'Next subtitle track'],
    ['B', 'Next audio track'],
    ['G / H', 'Subtitle offset −/+ 0.1 s'],
    ['< >', 'Slower or faster'],
    ['/', 'Normal speed'],
    ['A', 'Change aspect'],
    ['F', 'Full screen'],
    ['P', 'Picture in Picture'],
    ['I', 'Performance stats'],
    ['?', 'Show or hide this list'],
    ['Esc', 'Close or exit full screen'],
  ];
  return (
    <div className="absolute inset-0 z-50 bg-black/70 flex items-center justify-center p-6" onClick={onClose}>
      <div className="w-full max-w-2xl bg-black/90 rounded-xl ring-1 ring-white/10 p-6" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-white text-xl font-semibold">Keyboard Shortcuts</h2>
          <button className="px-3 py-1.5 text-sm bg-white/10 hover:bg-white/20 rounded text-white" onClick={onClose} aria-label="Close keyboard shortcuts">Close</button>
        </div>
        <dl className="grid grid-cols-1 sm:grid-cols-2 gap-x-8 gap-y-2 max-h-[70vh] overflow-y-auto">
          {shortcuts.map(([keys, action]) => (
            <div key={keys} className="flex items-center justify-between gap-3">
              <dt className="text-white font-mono text-xs bg-white/10 rounded px-2 py-1 whitespace-nowrap">{keys}</dt>
              <dd className="text-white/80 text-sm text-right">{action}</dd>
            </div>
          ))}
        </dl>
      </div>
    </div>
  );
}
