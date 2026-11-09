import { useEffect, useMemo, useState } from 'react';
import SettingsCard from '@/components/SettingsCard';
import SettingItem, { SettingToggle } from '@/components/SettingItem';
import type { StremioAddon } from '@/stremio';
import { StreamRuleMatcher, StreamRulesError, type RuleVerdict, type StreamRules } from '@/stremio/rules';
import { saveSettings, useSettings } from '@/state/settings';

const PREVIEW_BUDGET_MS = 500;
const PREVIEW_DEBOUNCE_MS = 200;

const EXAMPLES = [
  { text: 'Movie 2024 2160p WEB-DL DV HDR x265', resolution: 2160 },
  { text: 'Movie 2024 1080p BluRay x264 DTS', resolution: 1080 },
  { text: 'Movie 2024 720p WEBRip x265', resolution: 720 },
  { text: 'Movie 2024 HDCAM 720p x264', resolution: 720 },
  { text: 'Movie.2024.HDTS.1080p.x264', resolution: 1080 },
  { text: 'Movie 2024 TS 480p', resolution: 480 },
];

const ERROR_TEXT = {
  invalidInclude: "The include pattern isn't valid.",
  unsafeInclude: 'That pattern could hang the app. Avoid a repeat inside a repeat, like (a+)+, and keep it under 300 characters.',
  invalidExclude: "The exclude words aren't valid.",
};

const VERDICT_TEXT: Record<RuleVerdict, string> = {
  match: 'Allowed',
  missingInclude: 'Skipped: missing an include word',
  excluded: 'Skipped: has an excluded word',
  aboveResolutionLimit: 'Skipped: above your limit',
  timedOut: 'Pattern took too long',
};

const fieldClass =
  'w-full rounded-lg bg-white/[0.08] px-3 py-2 text-[14px] text-white placeholder:text-[#6b7280] focus:outline-none focus:ring-2 focus:ring-brand/60';

/** The "Match my rules" editor, with a live preview on example release names. */
export default function StreamRulesEditor({ streamAddons }: { streamAddons: StremioAddon[] }) {
  const settings = useSettings();
  const [verdicts, setVerdicts] = useState<RuleVerdict[] | null>(null);

  const rules: StreamRules = useMemo(
    () => ({
      include: settings.stremioRulesInclude,
      includeIsRegex: settings.stremioRulesIncludeRegex,
      exclude: settings.stremioRulesExclude,
      preferredAddonId: settings.stremioRulesPreferredAddon || undefined,
      maxResolution: settings.stremioRulesMaxResolution || undefined,
    }),
    [
      settings.stremioRulesInclude,
      settings.stremioRulesIncludeRegex,
      settings.stremioRulesExclude,
      settings.stremioRulesPreferredAddon,
      settings.stremioRulesMaxResolution,
    ],
  );

  const ruleError = useMemo(() => {
    try {
      new StreamRuleMatcher(rules);
      return null;
    } catch (err) {
      return err instanceof StreamRulesError ? ERROR_TEXT[err.code] : ERROR_TEXT.invalidInclude;
    }
  }, [rules]);

  useEffect(() => {
    setVerdicts(null);
    if (ruleError) return;
    let cancelled = false;
    const timer = setTimeout(async () => {
      const next = await new StreamRuleMatcher(rules, PREVIEW_BUDGET_MS).verdicts(EXAMPLES);
      if (!cancelled) setVerdicts(next);
    }, PREVIEW_DEBOUNCE_MS);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [rules, ruleError]);

  return (
    <SettingsCard title="Source rules">
      <div className="flex flex-col gap-3 p-[14px]">
        <label className="block">
          <span className="mb-1 block text-[13px] font-semibold text-[#f9fafb]">Include</span>
          <input
            value={settings.stremioRulesInclude}
            onChange={(event) => saveSettings({ stremioRulesInclude: event.target.value })}
            placeholder={settings.stremioRulesIncludeRegex ? 'Regular expression' : 'Words separated by | or ,'}
            spellCheck={false}
            className={fieldClass}
          />
        </label>
        <label className="block">
          <span className="mb-1 block text-[13px] font-semibold text-[#f9fafb]">Exclude</span>
          <input
            value={settings.stremioRulesExclude}
            onChange={(event) => saveSettings({ stremioRulesExclude: event.target.value })}
            placeholder="Words separated by | or ,"
            spellCheck={false}
            className={fieldClass}
          />
        </label>
        {ruleError && <p className="text-[13px] text-[#f87171]">{ruleError}</p>}
      </div>

      <SettingItem
        title="Treat Include as a Regular Expression"
        description="Word lists are safer and faster"
        renderRight={() => (
          <SettingToggle
            checked={settings.stremioRulesIncludeRegex}
            onChange={(value) => saveSettings({ stremioRulesIncludeRegex: value })}
          />
        )}
      />

      <SettingItem
        title="Preferred Addon"
        renderRight={() => (
          <select
            value={settings.stremioRulesPreferredAddon}
            onChange={(event) => saveSettings({ stremioRulesPreferredAddon: event.target.value })}
            aria-label="Preferred addon"
            className="max-w-[180px] rounded-lg bg-white/[0.08] px-2 py-1.5 text-[13px] text-white focus:outline-none"
          >
            <option value="">None</option>
            {streamAddons.map((addon) => (
              <option key={addon.installationId} value={addon.installationId}>{addon.name}</option>
            ))}
          </select>
        )}
      />

      <SettingItem
        title="Maximum Resolution"
        isLast
        renderRight={() => (
          <select
            value={settings.stremioRulesMaxResolution}
            onChange={(event) => saveSettings({ stremioRulesMaxResolution: Number(event.target.value) })}
            aria-label="Maximum resolution"
            className="rounded-lg bg-white/[0.08] px-2 py-1.5 text-[13px] text-white focus:outline-none"
          >
            <option value={0}>No limit</option>
            {[2160, 1080, 720, 480].map((limit) => (
              <option key={limit} value={limit}>{limit}p</option>
            ))}
          </select>
        )}
      />

      {!ruleError && verdicts && (
        <div className="border-t border-white/[0.08] p-[14px]">
          <span className="mb-2 block text-[11px] font-bold uppercase tracking-wide text-[#9ca3af]">Preview</span>
          <ul className="flex flex-col gap-1.5">
            {EXAMPLES.map((example, index) => (
              <li key={example.text} className="flex items-baseline justify-between gap-3 text-[12px]">
                <span className="truncate text-[#d1d5db]">{example.text}</span>
                <span className={`flex-shrink-0 ${verdicts[index] === 'match' ? 'text-[#4ade80]' : 'text-[#9ca3af]'}`}>
                  {VERDICT_TEXT[verdicts[index]]}
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </SettingsCard>
  );
}

