import SettingsCard from '@/components/SettingsCard';
import SettingItem, { SettingButton, SettingToggle } from '@/components/SettingItem';
import SettingsScreen from '@/components/settings/SettingsScreen';
import { ACCENT_PALETTES } from '@/state/accent';
import { type AccentPalette, saveSettings, SETTINGS_DEFAULTS, useSettings } from '@/state/settings';

const PALETTES = Object.entries(ACCENT_PALETTES) as [AccentPalette, (typeof ACCENT_PALETTES)[AccentPalette]][];

export default function AppearanceSettings() {
  const { accentPalette, pureBlack } = useSettings();
  const isDefault = accentPalette === SETTINGS_DEFAULTS.accentPalette && pureBlack === SETTINGS_DEFAULTS.pureBlack;

  return (
    <SettingsScreen title="Appearance">
      <SettingsCard title="ACCENT COLOR">
        <div className="p-[14px]">
          <div role="radiogroup" aria-label="Accent color" className="grid grid-cols-[repeat(auto-fill,minmax(76px,1fr))] gap-4">
            {PALETTES.map(([id, palette]) => {
              const selected = accentPalette === id;
              return (
                <button
                  key={id}
                  type="button"
                  role="radio"
                  aria-checked={selected}
                  onClick={() => saveSettings({ accentPalette: id })}
                  className="flex flex-col items-center gap-1.5"
                >
                  <span
                    className="p-1 rounded-full border-2 transition-colors"
                    style={{ borderColor: selected ? `rgb(${palette.bright})` : 'transparent' }}
                  >
                    <span
                      className="w-[34px] h-[34px] rounded-full flex items-center justify-center text-white"
                      style={{
                        background: `linear-gradient(135deg, rgb(${palette.bright}), rgb(${palette.base}), rgb(${palette.strong}))`,
                      }}
                    >
                      {selected && (
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                          <path d="M5 13l4 4L19 7" />
                        </svg>
                      )}
                    </span>
                  </span>
                  <span className={`text-[12px] truncate ${selected ? 'text-white font-semibold' : 'text-[#9ca3af]'}`}>
                    {palette.label}
                  </span>
                </button>
              );
            })}
          </div>
          <p className="mt-4 text-[12px] text-[#9ca3af]">
            Used for selection, toggles and highlights. The Flixor logo always stays red.
          </p>
        </div>
      </SettingsCard>

      <SettingsCard title="BACKGROUND">
        <SettingItem
          title="Pure Black Background"
          description="True black instead of near-black. Best on OLED displays."
          renderRight={() => <SettingToggle checked={pureBlack} onChange={(v) => saveSettings({ pureBlack: v })} />}
          isLast
        />
      </SettingsCard>

      <SettingsCard title="PREVIEW">
        <div className={`p-5 ${pureBlack ? 'bg-black' : 'bg-[#0a0a0a]'}`}>
          <div className="flex items-center gap-3">
            <span className="px-4 py-2 rounded-lg bg-brand text-white text-[13px] font-semibold">Play</span>
            <span className="px-4 py-2 rounded-lg bg-brand/20 text-brand-bright text-[13px] font-semibold">Selected</span>
          </div>
          <div className="mt-4 h-1 rounded-full bg-white/15 overflow-hidden">
            <div className="h-full w-3/5 bg-brand" />
          </div>
        </div>
      </SettingsCard>

      <div className="flex justify-end">
        <SettingButton
          disabled={isDefault}
          onClick={() =>
            saveSettings({ accentPalette: SETTINGS_DEFAULTS.accentPalette, pureBlack: SETTINGS_DEFAULTS.pureBlack })
          }
        >
          Reset to Default
        </SettingButton>
      </div>
    </SettingsScreen>
  );
}
