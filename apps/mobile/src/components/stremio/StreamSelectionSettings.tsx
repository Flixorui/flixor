import React, { useEffect, useState } from 'react';
import { Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import SettingsCard from '../settings/SettingsCard';
import SettingItem from '../settings/SettingItem';
import SettingsSwitch from '../settings/SettingsSwitch';
import type { StremioPlayAction, StremioStreamRules } from '../../core/SettingsData';
import { useAppSettings } from '../../hooks/useAppSettings';
import { useTheme } from '../../hooks/useTheme';
import { checkIncludePattern, describeRuleProblem } from '../../stremio/StreamAutoSelector';
import { stremioService } from '../../stremio/StremioService';
import type { StremioAddonManifest } from '../../stremio/types';

const PLAY_ACTIONS: Array<{ value: StremioPlayAction; label: string; description: string }> = [
  { value: 'showSources', label: 'Sources', description: 'Always open the list of sources' },
  { value: 'playBest', label: 'Best', description: 'Start the best playable source' },
  { value: 'matchRules', label: 'My Rules', description: 'Start the best source that fits your rules, or show the list if none does' },
  { value: 'addonOrder', label: 'Order', description: 'Try your first addon, then fall back to the next one in your addon order' },
];
const TIME_LIMITS = [3, 5, 8, 10, 15, 30];
const RESOLUTION_LIMITS: Array<StremioStreamRules['maxResolution']> = [undefined, 2160, 1080, 720, 480];

type SegmentOption<T> = { key: string; label: string; value: T };

function Segments<T>({
  options,
  selected,
  onSelect,
}: {
  options: Array<SegmentOption<T>>;
  selected: T;
  onSelect: (value: T) => void;
}) {
  const theme = useTheme();
  return (
    <View style={[styles.segments, { borderColor: theme.separatorStrong }]}>
      {options.map((option) => {
        const active = option.value === selected;
        return (
          <Pressable
            key={option.key}
            style={[styles.segment, active && styles.segmentActive]}
            onPress={() => onSelect(option.value)}
            accessibilityRole="button"
            accessibilityState={{ selected: active }}
          >
            <Text style={[styles.segmentText, { color: active ? '#111827' : theme.textPrimary }]} numberOfLines={1}>
              {option.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

function RuleInput({
  label,
  hint,
  value,
  placeholder,
  error,
  onCommit,
}: {
  label: string;
  hint: string;
  value: string;
  placeholder: string;
  error?: string | null;
  onCommit: (text: string) => void;
}) {
  const theme = useTheme();
  const [draft, setDraft] = useState(value);
  useEffect(() => setDraft(value), [value]);
  return (
    <View style={styles.group}>
      <Text style={[styles.label, { color: theme.textPrimary }]}>{label}</Text>
      <Text style={[styles.hint, { color: theme.textTertiary }]}>{hint}</Text>
      <TextInput
        value={draft}
        onChangeText={setDraft}
        onEndEditing={() => onCommit(draft)}
        placeholder={placeholder}
        placeholderTextColor={theme.textDisabled}
        autoCapitalize="none"
        autoCorrect={false}
        style={[styles.input, { color: theme.textPrimary, borderColor: error ? theme.danger : theme.separatorStrong }]}
      />
      {error ? <Text style={[styles.hint, { color: theme.danger }]}>{error}</Text> : null}
    </View>
  );
}

/** What Play does on addon content, and the "Match my rules" editor. */
export default function StreamSelectionSettings() {
  const theme = useTheme();
  const { settings, updateSetting } = useAppSettings();
  const [addons, setAddons] = useState<StremioAddonManifest[]>([]);
  const rules = settings.stremioStreamRules;
  const action = settings.stremioPlayAction;

  useEffect(() => {
    stremioService
      .getAddonSummary()
      .then((summary) => setAddons(summary.filter((addon) => addon.streamCapable)))
      .catch(() => setAddons([]));
  }, []);

  const updateRules = (patch: Partial<StremioStreamRules>) => {
    updateSetting('stremioStreamRules', { ...rules, ...patch });
  };

  const problem = rules.includeIsRegex ? checkIncludePattern(rules.include) : null;
  const addonOptions: Array<SegmentOption<string | undefined>> = [
    { key: 'any', label: 'Any', value: undefined },
    ...addons.map((addon) => ({ key: addon.installationId, label: addon.name, value: addon.installationId })),
  ];

  return (
    <>
      <SettingsCard title="WHEN I PRESS PLAY">
        <View style={styles.group}>
          <Segments
            options={PLAY_ACTIONS.map((option) => ({ key: option.value, label: option.label, value: option.value }))}
            selected={action}
            onSelect={(value) => updateSetting('stremioPlayAction', value)}
          />
          <Text style={[styles.hint, { color: theme.textTertiary }]}>
            {PLAY_ACTIONS.find((option) => option.value === action)?.description}
          </Text>
        </View>
        {action !== 'showSources' ? (
          <View style={styles.group}>
            <Text style={[styles.label, { color: theme.textPrimary }]}>Wait for Addons</Text>
            <Text style={[styles.hint, { color: theme.textTertiary }]}>
              Longest to wait before deciding with the sources that have arrived
            </Text>
            <Segments
              options={TIME_LIMITS.map((seconds) => ({ key: String(seconds), label: `${seconds}s`, value: seconds }))}
              selected={settings.stremioAutoPickTimeLimit}
              onSelect={(value) => updateSetting('stremioAutoPickTimeLimit', value)}
            />
          </View>
        ) : null}
      </SettingsCard>

      {action === 'matchRules' ? (
        <SettingsCard title="SOURCE RULES">
          <RuleInput
            label="Include"
            hint={rules.includeIsRegex ? 'A regular expression the source must match' : 'Words separated by | or commas. Any one is enough'}
            value={rules.include}
            placeholder={rules.includeIsRegex ? '(1080|2160)p.*remux' : 'remux | bluray'}
            error={problem ? describeRuleProblem(problem) : null}
            onCommit={(include) => updateRules({ include })}
          />
          <SettingItem
            title="Include Is a Regular Expression"
            description="Patterns that could freeze the app are rejected"
            icon="code-slash-outline"
            renderRight={() => (
              <SettingsSwitch
                value={rules.includeIsRegex}
                onValueChange={(includeIsRegex) => updateRules({ includeIsRegex })}
              />
            )}
            isLast={false}
          />
          <RuleInput
            label="Exclude"
            hint="Words separated by | or commas. Whole words only, so TS won't match DTS"
            value={rules.exclude}
            placeholder="CAM | TS"
            onCommit={(exclude) => updateRules({ exclude })}
          />
          <View style={styles.group}>
            <Text style={[styles.label, { color: theme.textPrimary }]}>Highest Resolution</Text>
            <Segments
              options={RESOLUTION_LIMITS.map((limit) => ({
                key: String(limit ?? 'any'),
                label: limit ? (limit === 2160 ? '4K' : `${limit}p`) : 'Any',
                value: limit,
              }))}
              selected={rules.maxResolution}
              onSelect={(maxResolution) => updateRules({ maxResolution })}
            />
          </View>
          {addons.length > 0 ? (
            <View style={styles.group}>
              <Text style={[styles.label, { color: theme.textPrimary }]}>Preferred Addon</Text>
              <Segments
                options={addonOptions}
                selected={rules.preferredAddonId}
                onSelect={(preferredAddonId) => updateRules({ preferredAddonId })}
              />
            </View>
          ) : null}
        </SettingsCard>
      ) : null}
    </>
  );
}

const styles = StyleSheet.create({
  group: {
    paddingHorizontal: 14,
    paddingVertical: 12,
    gap: 8,
  },
  label: {
    fontSize: 14,
    fontWeight: '600',
  },
  hint: {
    fontSize: 12,
    lineHeight: 17,
  },
  input: {
    borderWidth: 1,
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 14,
  },
  segments: {
    flexDirection: 'row',
    borderWidth: 1,
    borderRadius: 12,
    overflow: 'hidden',
    padding: 2,
  },
  segment: {
    flex: 1,
    minHeight: 38,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 9,
    paddingHorizontal: 4,
  },
  segmentActive: {
    backgroundColor: '#ffffff',
  },
  segmentText: {
    fontSize: 12,
    fontWeight: '600',
  },
});
