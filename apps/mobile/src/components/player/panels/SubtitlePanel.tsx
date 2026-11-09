import React, { useMemo, useState } from 'react';
import { ScrollView, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import Slider from '@react-native-community/slider';
import SettingsSwitch from '../../settings/SettingsSwitch';
import { useAppSettings } from '../../../hooks/useAppSettings';
import { useTheme } from '../../../hooks/useTheme';
import type { SubtitleCue } from '../../../stremio/types';
import PlayerPanel from './PlayerPanel';

export const SUBTITLE_TEXT_COLORS = [
  { name: 'White', hex: '#FFFFFF' },
  { name: 'Yellow', hex: '#FFD60A' },
  { name: 'Cyan', hex: '#64D2FF' },
  { name: 'Green', hex: '#30D158' },
  { name: 'Black', hex: '#000000' },
];

const DELAY_STEP_MS = 250;
const NEARBY_CUES = 8;

type Props = {
  /** An addon subtitle is showing, so delay and line sync apply. */
  externalActive: boolean;
  cues: SubtitleCue[];
  currentTimeMs: number;
  delayMs: number;
  onDelayChange: (delayMs: number) => void;
  onClose: () => void;
};

type SliderRowProps = {
  label: string;
  value: number;
  minimum: number;
  maximum: number;
  step: number;
  format?: (value: number) => string;
  onCommit: (value: number) => void;
};

function SliderRow({ label, value, minimum, maximum, step, format, onCommit }: SliderRowProps) {
  const theme = useTheme();
  const [draft, setDraft] = useState<number | null>(null);
  const shown = draft ?? value;
  return (
    <View style={styles.sliderRow}>
      <View style={styles.sliderHeader}>
        <Text style={[styles.label, { color: theme.textPrimary }]}>{label}</Text>
        <Text style={[styles.value, { color: theme.textSecondary }]}>{format ? format(shown) : shown}</Text>
      </View>
      <Slider
        value={value}
        minimumValue={minimum}
        maximumValue={maximum}
        step={step}
        minimumTrackTintColor={theme.accent}
        maximumTrackTintColor={theme.separatorStrong}
        thumbTintColor="#fff"
        onValueChange={setDraft}
        onSlidingComplete={(next: number) => {
          setDraft(null);
          onCommit(next);
        }}
      />
    </View>
  );
}

function formatDelay(delayMs: number): string {
  const seconds = delayMs / 1000;
  return `${seconds > 0 ? '+' : ''}${seconds.toFixed(2)} s`;
}

function formatCueTime(seconds: number): string {
  const whole = Math.max(0, Math.floor(seconds));
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`;
}

export default function SubtitlePanel({
  externalActive,
  cues,
  currentTimeMs,
  delayMs,
  onDelayChange,
  onClose,
}: Props) {
  const theme = useTheme();
  const { settings, updateSetting } = useAppSettings();
  const [syncAnchorMs, setSyncAnchorMs] = useState<number | null>(null);

  // The list holds still until refreshed, so a row can't move as it is tapped.
  const nearbyCues = useMemo(() => {
    if (syncAnchorMs === null) return [];
    const cueTime = (syncAnchorMs - delayMs) / 1000;
    const nextIndex = cues.findIndex((cue) => cue.endTime >= cueTime);
    const center = nextIndex < 0 ? cues.length : nextIndex;
    return cues.slice(Math.max(0, center - NEARBY_CUES), center + NEARBY_CUES);
    // delayMs is read at the moment the list is opened or refreshed.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cues, syncAnchorMs]);

  return (
    <PlayerPanel title="Subtitle Style" onClose={onClose}>
      <ScrollView contentContainerStyle={styles.content}>
        <SliderRow
          label="Size"
          value={settings.subtitleFontSize}
          minimum={30}
          maximum={80}
          step={5}
          onCommit={(value) => updateSetting('subtitleFontSize', value)}
        />
        <SliderRow
          label="Position"
          value={Math.min(100, settings.subtitlePosition)}
          minimum={0}
          maximum={100}
          step={5}
          onCommit={(value) => updateSetting('subtitlePosition', value)}
        />
        <SliderRow
          label="Outline"
          value={settings.subtitleBorderSize}
          minimum={0}
          maximum={5}
          step={0.5}
          format={(value) => value.toFixed(1)}
          onCommit={(value) => updateSetting('subtitleBorderSize', value)}
        />

        <Text style={[styles.label, styles.colorLabel, { color: theme.textPrimary }]}>Color</Text>
        <View style={styles.swatches}>
          {SUBTITLE_TEXT_COLORS.map((option) => {
            const selected = settings.subtitleTextColor.toUpperCase() === option.hex;
            return (
              <TouchableOpacity
                key={option.hex}
                onPress={() => updateSetting('subtitleTextColor', option.hex)}
                accessibilityRole="button"
                accessibilityLabel={`${option.name} text`}
                accessibilityState={{ selected }}
                style={[styles.swatchRing, selected && { borderColor: theme.focusRing }]}
              >
                <View style={[styles.swatch, { backgroundColor: option.hex, borderColor: theme.separatorStrong }]} />
              </TouchableOpacity>
            );
          })}
        </View>

        <View style={[styles.switchRow, { borderTopColor: theme.separator }]}>
          <View style={styles.switchText}>
            <Text style={[styles.label, { color: theme.textPrimary }]}>Remove hearing-impaired text</Text>
            <Text style={[styles.hint, { color: theme.textTertiary }]}>Applies to addon subtitles</Text>
          </View>
          <SettingsSwitch
            value={settings.subtitleFilterSDH}
            onValueChange={(value) => updateSetting('subtitleFilterSDH', value)}
          />
        </View>

        {externalActive ? (
          <View style={[styles.syncSection, { borderTopColor: theme.separator }]}>
            <View style={styles.delayRow}>
              <Text style={[styles.label, { color: theme.textPrimary }]}>Delay</Text>
              <View style={styles.delayControls}>
                <TouchableOpacity
                  style={[styles.delayButton, { backgroundColor: theme.surfaceOverlay }]}
                  onPress={() => onDelayChange(delayMs - DELAY_STEP_MS)}
                  accessibilityRole="button"
                  accessibilityLabel="Show subtitles earlier"
                >
                  <Text style={[styles.delayButtonText, { color: theme.textPrimary }]}>−</Text>
                </TouchableOpacity>
                <Text style={[styles.value, styles.delayValue, { color: theme.textPrimary }]}>{formatDelay(delayMs)}</Text>
                <TouchableOpacity
                  style={[styles.delayButton, { backgroundColor: theme.surfaceOverlay }]}
                  onPress={() => onDelayChange(delayMs + DELAY_STEP_MS)}
                  accessibilityRole="button"
                  accessibilityLabel="Show subtitles later"
                >
                  <Text style={[styles.delayButtonText, { color: theme.textPrimary }]}>+</Text>
                </TouchableOpacity>
                {delayMs !== 0 ? (
                  <TouchableOpacity onPress={() => onDelayChange(0)} accessibilityRole="button">
                    <Text style={[styles.link, { color: theme.accentBright }]}>Reset</Text>
                  </TouchableOpacity>
                ) : null}
              </View>
            </View>

            <TouchableOpacity onPress={() => setSyncAnchorMs(currentTimeMs)} accessibilityRole="button">
              <Text style={[styles.link, { color: theme.accentBright }]}>
                {syncAnchorMs === null ? 'Sync by Line' : 'Refresh Lines'}
              </Text>
            </TouchableOpacity>
            {syncAnchorMs !== null ? (
              <>
                <Text style={[styles.hint, { color: theme.textTertiary }]}>
                  Tap a line the moment it is spoken. The subtitles shift so that line appears right now.
                </Text>
                {nearbyCues.map((cue) => (
                  <TouchableOpacity
                    key={`${cue.startTime}-${cue.endTime}`}
                    style={styles.cueRow}
                    onPress={() => onDelayChange(Math.round(currentTimeMs - cue.startTime * 1000))}
                    accessibilityRole="button"
                  >
                    <Text style={[styles.cueTime, { color: theme.textTertiary }]}>{formatCueTime(cue.startTime)}</Text>
                    <Text style={[styles.cueText, { color: theme.textPrimary }]} numberOfLines={2}>
                      {cue.text}
                    </Text>
                  </TouchableOpacity>
                ))}
              </>
            ) : null}
          </View>
        ) : null}
      </ScrollView>
    </PlayerPanel>
  );
}

const styles = StyleSheet.create({
  content: {
    padding: 16,
    gap: 12,
  },
  sliderRow: {
    gap: 4,
  },
  sliderHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  label: {
    fontSize: 14,
    fontWeight: '600',
  },
  value: {
    fontSize: 13,
    fontVariant: ['tabular-nums'],
  },
  colorLabel: {
    marginTop: 4,
  },
  swatches: {
    flexDirection: 'row',
    gap: 10,
  },
  swatchRing: {
    padding: 2,
    borderRadius: 18,
    borderWidth: 2,
    borderColor: 'transparent',
  },
  swatch: {
    width: 26,
    height: 26,
    borderRadius: 13,
    borderWidth: StyleSheet.hairlineWidth,
  },
  switchRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
    paddingTop: 12,
    borderTopWidth: StyleSheet.hairlineWidth,
  },
  switchText: {
    flex: 1,
    gap: 2,
  },
  hint: {
    fontSize: 12,
    lineHeight: 17,
  },
  syncSection: {
    gap: 12,
    paddingTop: 12,
    borderTopWidth: StyleSheet.hairlineWidth,
  },
  delayRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  delayControls: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  delayButton: {
    width: 32,
    height: 32,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  delayButtonText: {
    fontSize: 18,
    fontWeight: '700',
  },
  delayValue: {
    minWidth: 62,
    textAlign: 'center',
  },
  link: {
    fontSize: 14,
    fontWeight: '700',
  },
  cueRow: {
    flexDirection: 'row',
    gap: 10,
    paddingVertical: 6,
  },
  cueTime: {
    width: 44,
    fontSize: 12,
    fontVariant: ['tabular-nums'],
  },
  cueText: {
    flex: 1,
    fontSize: 13,
    lineHeight: 18,
  },
});
