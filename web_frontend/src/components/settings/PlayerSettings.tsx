import { useNavigate } from 'react-router-dom';
import SettingItem from '@/components/SettingItem';
import SettingsCard from '@/components/SettingsCard';
import { ChevronBackIcon } from '@/components/ServiceIcons';
import { ASPECT_MODES } from '@/player/ui/panels';
import { saveSettings, useSettings, type PlayerAspectMode, type SubtitleSourcePreference } from '@/state/settings';

const FONT_OPTIONS = ['', 'Arial', 'Helvetica Neue', 'Verdana', 'Trebuchet MS', 'Georgia', 'Times New Roman', 'Courier New'];
const SPEED_OPTIONS = [0.5, 0.75, 1, 1.25, 1.5, 2];
const LANGUAGE_OPTIONS: Array<[string, string]> = [
  ['en', 'English'], ['es', 'Spanish'], ['es-419', 'Spanish (Latin America)'], ['pt', 'Portuguese'], ['pt-BR', 'Portuguese (Brazil)'],
  ['fr', 'French'], ['de', 'German'], ['it', 'Italian'], ['ja', 'Japanese'], ['ko', 'Korean'], ['zh', 'Chinese'], ['ru', 'Russian'],
  ['ar', 'Arabic'], ['hi', 'Hindi'], ['nl', 'Dutch'], ['sv', 'Swedish'], ['pl', 'Polish'], ['tr', 'Turkish'],
];

const SELECT_CLASS = 'bg-white/10 text-white text-[13px] rounded-lg px-2 py-1.5 border border-white/10 max-w-[12rem]';

function Toggle({ checked, onChange, label }: { checked: boolean; onChange: (value: boolean) => void; label: string }) {
  return (
    <button
      role="switch"
      aria-checked={checked}
      aria-label={label}
      onClick={() => onChange(!checked)}
      className={`relative w-11 h-6 rounded-full transition-colors ${checked ? 'bg-brand' : 'bg-white/20'}`}
    >
      <span className={`absolute top-0.5 left-0.5 w-5 h-5 rounded-full bg-white transition-transform ${checked ? 'translate-x-5' : ''}`} />
    </button>
  );
}

function Stepper({ value, unit = '', min, max, step, onChange, label }: { value: number; unit?: string; min: number; max: number; step: number; onChange: (value: number) => void; label: string }) {
  const round = (n: number) => Math.round(n * 100) / 100;
  return (
    <div className="flex items-center gap-2">
      <button className="w-7 h-7 rounded-lg bg-white/10 text-white disabled:opacity-40" disabled={value <= min} aria-label={`Decrease ${label}`} onClick={() => onChange(Math.max(min, round(value - step)))}>−</button>
      <span className="w-14 text-center text-white text-[13px] tabular-nums">{value}{unit}</span>
      <button className="w-7 h-7 rounded-lg bg-white/10 text-white disabled:opacity-40" disabled={value >= max} aria-label={`Increase ${label}`} onClick={() => onChange(Math.min(max, round(value + step)))}>+</button>
    </div>
  );
}

function Select<T extends string | number>({ value, options, onChange, label }: { value: T; options: Array<[T, string]>; onChange: (value: T) => void; label: string }) {
  return (
    <select
      aria-label={label}
      className={SELECT_CLASS}
      value={String(value)}
      onChange={(e) => onChange(options.find(([option]) => String(option) === e.target.value)?.[0] as T)}
    >
      {options.map(([option, name]) => <option key={String(option)} value={String(option)}>{name}</option>)}
    </select>
  );
}

function Color({ value, onChange, label }: { value: string; onChange: (value: string) => void; label: string }) {
  return (
    <input
      type="color"
      aria-label={label}
      value={value}
      onChange={(e) => onChange(e.target.value.toUpperCase())}
      className="w-9 h-7 rounded-md border border-white/20 bg-transparent cursor-pointer"
    />
  );
}

export default function PlayerSettings() {
  const navigate = useNavigate();
  const s = useSettings();

  return (
    <div className="min-h-screen pb-20">
      <div className="px-4 pt-6 pb-4 max-w-2xl mx-auto flex items-center gap-3">
        <button onClick={() => navigate('/settings')} aria-label="Back" className="-ml-2 flex items-center justify-center w-10 h-10 rounded-full hover:bg-white/10 transition-colors">
          <ChevronBackIcon size={24} color="#fff" />
        </button>
        <h1 className="text-white text-xl font-bold">Player</h1>
      </div>

      <div className="px-4 max-w-2xl mx-auto">
        <SettingsCard title="Playback">
          <SettingItem title="Small Seek" description="Left and right arrow keys" renderRight={() => <Stepper label="small seek" value={s.seekTimeSmall} unit="s" min={1} max={120} step={5} onChange={(seekTimeSmall) => saveSettings({ seekTimeSmall })} />} />
          <SettingItem title="Large Seek" description="Shift+arrows, J and L" renderRight={() => <Stepper label="large seek" value={s.seekTimeLarge} unit="s" min={1} max={120} step={10} onChange={(seekTimeLarge) => saveSettings({ seekTimeLarge })} />} />
          <SettingItem title="Default Speed" renderRight={() => <Select label="Default speed" value={s.defaultPlaybackSpeed} options={SPEED_OPTIONS.map((speed) => [speed, `${speed}x`])} onChange={(defaultPlaybackSpeed) => saveSettings({ defaultPlaybackSpeed })} />} />
          <SettingItem title="Aspect" description="How the picture fills the window" renderRight={() => <Select<PlayerAspectMode> label="Aspect" value={s.playerAspectMode} options={ASPECT_MODES.map((mode) => [mode.value, mode.label])} onChange={(playerAspectMode) => saveSettings({ playerAspectMode })} />} />
          <SettingItem title="Auto-Play Next Episode" isLast renderRight={() => <Toggle label="Auto-play next episode" checked={s.autoPlayNext} onChange={(autoPlayNext) => saveSettings({ autoPlayNext })} />} />
        </SettingsCard>

        <SettingsCard title="Tracks">
          <SettingItem title="Remember Track Choices" description="Per title and series" renderRight={() => <Toggle label="Remember track choices" checked={s.rememberTrackSelections} onChange={(rememberTrackSelections) => saveSettings({ rememberTrackSelections })} />} />
          <SettingItem title="Audio Language" renderRight={() => <Select label="Audio language" value={s.preferredAudioLanguage} options={[['', 'Default'], ['original', 'Original language'], ...LANGUAGE_OPTIONS]} onChange={(preferredAudioLanguage) => saveSettings({ preferredAudioLanguage })} />} />
          <SettingItem title="Subtitle Language" renderRight={() => <Select label="Subtitle language" value={s.preferredSubtitleLanguage} options={[['', 'None'], ...LANGUAGE_OPTIONS]} onChange={(preferredSubtitleLanguage) => saveSettings({ preferredSubtitleLanguage })} />} />
          <SettingItem title="Subtitle Source" description="Used for addon streams" renderRight={() => <Select<SubtitleSourcePreference> label="Subtitle source" value={s.subtitleSourcePreference} options={[['internal', 'Internal first'], ['external', 'External first'], ['any', 'Any']]} onChange={(subtitleSourcePreference) => saveSettings({ subtitleSourcePreference })} />} />
          <SettingItem title="Auto-Select Subtitles" description="Turn on the preferred language when found" isLast renderRight={() => <Toggle label="Auto-select subtitles" checked={s.enableSubtitleAutoSelect} onChange={(enableSubtitleAutoSelect) => saveSettings({ enableSubtitleAutoSelect })} />} />
        </SettingsCard>

        <SettingsCard title="Skip">
          <SettingItem title="Skip Intros" renderRight={() => <Toggle label="Skip intros" checked={s.skipIntroAutomatically} onChange={(skipIntroAutomatically) => saveSettings({ skipIntroAutomatically })} />} />
          <SettingItem title="Skip Credits" renderRight={() => <Toggle label="Skip credits" checked={s.skipCreditsAutomatically} onChange={(skipCreditsAutomatically) => saveSettings({ skipCreditsAutomatically })} />} />
          <SettingItem title="Skip Recaps" renderRight={() => <Toggle label="Skip recaps" checked={s.skipRecapAutomatically} onChange={(skipRecapAutomatically) => saveSettings({ skipRecapAutomatically })} />} />
          <SettingItem title="Auto-Skip Delay" renderRight={() => <Stepper label="auto-skip delay" value={s.autoSkipDelay} unit="s" min={1} max={30} step={1} onChange={(autoSkipDelay) => saveSettings({ autoSkipDelay })} />} />
          <SettingItem title="Credits Fallback" description="Up Next this long before the end, without credits data" renderRight={() => <Stepper label="credits fallback" value={s.creditsCountdownFallback} unit="s" min={10} max={120} step={5} onChange={(creditsCountdownFallback) => saveSettings({ creditsCountdownFallback })} />} />
          <SettingItem title="Community Skip Data" description="IntroDB, AniSkip and Anime-Skip" renderRight={() => <Toggle label="Community skip data" checked={s.communitySkipSegmentsEnabled} onChange={(communitySkipSegmentsEnabled) => saveSettings({ communitySkipSegmentsEnabled })} />} />
          <SettingItem
            title="Anime-Skip Client ID"
            description="Optional, for Anime-Skip lookups"
            isLast
            renderRight={() => (
              <input
                aria-label="Anime-Skip client ID"
                className={`${SELECT_CLASS} w-40`}
                value={s.animeSkipClientId}
                onChange={(e) => saveSettings({ animeSkipClientId: e.target.value })}
              />
            )}
          />
        </SettingsCard>

        <SettingsCard title="Subtitle Appearance">
          <SettingItem title="Font" renderRight={() => <Select label="Subtitle font" value={s.subtitleFontName} options={FONT_OPTIONS.map((font) => [font, font || 'Default'])} onChange={(subtitleFontName) => saveSettings({ subtitleFontName })} />} />
          <SettingItem title="Size" renderRight={() => <Stepper label="subtitle size" value={s.subtitleFontSize ?? 100} unit="%" min={50} max={200} step={10} onChange={(subtitleFontSize) => saveSettings({ subtitleFontSize })} />} />
          <SettingItem title="Position" description="Pixels above the default" renderRight={() => <Stepper label="subtitle position" value={s.subtitleOffset ?? 0} unit="px" min={-100} max={300} step={10} onChange={(subtitleOffset) => saveSettings({ subtitleOffset })} />} />
          <SettingItem title="Bold" renderRight={() => <Toggle label="Bold subtitles" checked={s.subtitleBold} onChange={(subtitleBold) => saveSettings({ subtitleBold })} />} />
          <SettingItem title="Text Color" renderRight={() => <Color label="Text color" value={s.subtitleTextColor} onChange={(subtitleTextColor) => saveSettings({ subtitleTextColor })} />} />
          <SettingItem title="Outline" renderRight={() => <Stepper label="subtitle outline" value={s.subtitleBorderSize} min={0} max={5} step={0.5} onChange={(subtitleBorderSize) => saveSettings({ subtitleBorderSize })} />} />
          <SettingItem title="Outline Color" renderRight={() => <Color label="Outline color" value={s.subtitleBorderColor} onChange={(subtitleBorderColor) => saveSettings({ subtitleBorderColor })} />} />
          <SettingItem title="Background Opacity" renderRight={() => <Stepper label="background opacity" value={s.subtitleBackgroundOpacity} min={0} max={1} step={0.1} onChange={(subtitleBackgroundOpacity) => saveSettings({ subtitleBackgroundOpacity })} />} />
          <SettingItem title="Background Color" renderRight={() => <Color label="Background color" value={s.subtitleBackgroundColor} onChange={(subtitleBackgroundColor) => saveSettings({ subtitleBackgroundColor })} />} />
          <SettingItem title="Remove Hearing-Impaired Text" description="Strip [MUSIC], (laughs) and speaker labels" isLast renderRight={() => <Toggle label="Remove hearing-impaired text" checked={s.subtitleFilterSDH} onChange={(subtitleFilterSDH) => saveSettings({ subtitleFilterSDH })} />} />
        </SettingsCard>
      </div>
    </div>
  );
}
