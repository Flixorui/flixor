import React from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import ConditionalBlurView from './ConditionalBlurView';
import LiquidGlass, { liquidGlassAvailable } from './LiquidGlass';
import * as Haptics from 'expo-haptics';
import CategoriesMenu, { type CategoryPick } from './CategoriesMenu';

type Props = {
  selected: 'all'|'movies'|'shows';
  onChange: (tab: 'all'|'movies'|'shows') => void;
  onOpenCategories?: () => void;
  /** When given, Explore More opens the native Categories menu instead of the sheet. */
  onSelectCategory?: (pick: CategoryPick) => void;
  onClose?: () => void;
  activeGenre?: string;
  onClearGenre?: () => void;
  customPillLabel?: string; // Custom label for the active pill (e.g., library name)
};

/*
 * Netflix-style pills, measured from the Netflix iOS app: 40 pt rounded rectangles with a
 * 12 pt corner, frosted grey glass, a faint lighter top edge and no outline. The selected
 * pill is white with black text (Flixor's rule: neutral controls, red only for switches
 * and progress).
 */
const PILL_HEIGHT = 40;
const PILL_RADIUS = 12;

function Glass() {
  // iOS 26: Apple's Liquid Glass, as in the Netflix app; older systems keep the frosted look
  if (liquidGlassAvailable) return <LiquidGlass radius={PILL_RADIUS} />;
  return (
    <View pointerEvents="none" style={StyleSheet.absoluteFill}>
      <ConditionalBlurView intensity={30} tint="dark" style={StyleSheet.absoluteFill} />
      <View style={[StyleSheet.absoluteFill, styles.glassFill]} />
      <LinearGradient
        colors={['rgba(255,255,255,0.14)', 'rgba(255,255,255,0)']}
        start={{ x: 0.5, y: 0 }}
        end={{ x: 0.5, y: 0.45 }}
        style={StyleSheet.absoluteFill}
        pointerEvents="none"
      />
    </View>
  );
}

function Pill({ active, label, onPress, trailing }: { active?: boolean; label: string; onPress?: () => void; trailing?: React.ReactNode }) {
  const handlePress = () => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    onPress?.();
  };
  return (
    <Pressable
      onPress={handlePress}
      accessibilityRole="button"
      accessibilityState={{ selected: !!active }}
      style={({ pressed }) => [styles.pill, active && styles.pillActive, pressed && { opacity: 0.75 }]}
    >
      {active ? null : <Glass />}
      <Text style={[styles.label, active && styles.labelActive]}>{label}</Text>
      {trailing}
    </Pressable>
  );
}

function CloseButton({ onPress }: { onPress: () => void }) {
  return (
    <Pressable
      onPress={() => { Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light); onPress(); }}
      accessibilityRole="button"
      accessibilityLabel="Clear filter"
      style={({ pressed }) => [styles.close, pressed && { opacity: 0.75 }]}
    >
      <Glass />
      <Ionicons name="close" color="#fff" size={20} />
    </Pressable>
  );
}

export default function Pills({ selected, onChange, onOpenCategories, onSelectCategory, onClose, activeGenre, onClearGenre, customPillLabel }: Props) {
  // Determine pill labels - use custom label if provided, otherwise default
  const showsLabel = (selected === 'shows' && customPillLabel) ? customPillLabel : 'Shows';
  const moviesLabel = (selected === 'movies' && customPillLabel) ? customPillLabel : 'Movies';
  const backToAll = () => { onClose && onClose(); onChange('all'); };

  return (
    <View style={styles.row}>
      {selected === 'all' && (
        <>
          <Pill label="Shows" onPress={() => onChange('shows')} />
          <Pill label="Movies" onPress={() => onChange('movies')} />
        </>
      )}

      {selected === 'shows' && (
        <>
          <CloseButton onPress={backToAll} />
          <Pill label={showsLabel} active onPress={() => onChange('shows')} />
        </>
      )}

      {selected === 'movies' && (
        <>
          <CloseButton onPress={backToAll} />
          <Pill label={moviesLabel} active onPress={() => onChange('movies')} />
        </>
      )}

      {activeGenre ? (
        <>
          <CloseButton onPress={() => onClearGenre?.()} />
          <Pill label={activeGenre} active onPress={() => onOpenCategories?.()} />
        </>
      ) : (
        onSelectCategory ? (
          <CategoriesMenu onPick={onSelectCategory}>
            <View style={styles.pill}>
              <Glass />
              <Text style={styles.label}>Explore More</Text>
              <Ionicons name="chevron-down" color="#fff" size={15} style={{ marginLeft: 5 }} />
            </View>
          </CategoriesMenu>
        ) : (
          <Pill
            label="Explore More"
            onPress={() => onOpenCategories?.()}
            trailing={<Ionicons name="chevron-down" color="#fff" size={15} style={{ marginLeft: 5 }} />}
          />
        )
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingVertical: 4 },
  pill: {
    height: PILL_HEIGHT,
    paddingHorizontal: 15,
    borderRadius: PILL_RADIUS,
    overflow: 'hidden',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
  },
  pillActive: { backgroundColor: '#fff' },
  glassFill: {
    backgroundColor: 'rgba(118,124,132,0.30)',
    borderRadius: PILL_RADIUS,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.10)',
  },
  label: { color: '#fff', fontSize: 15, fontWeight: '600' },
  labelActive: { color: '#000' },
  close: {
    width: PILL_HEIGHT,
    height: PILL_HEIGHT,
    borderRadius: PILL_RADIUS,
    overflow: 'hidden',
    alignItems: 'center',
    justifyContent: 'center',
  },
});
