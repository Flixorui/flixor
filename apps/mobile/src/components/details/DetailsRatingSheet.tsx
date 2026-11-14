/**
 * Small sheet to rate a title on Trakt: 1-10 shown as five stars with halves.
 * macOS reference: Views/Details/DetailsRatingSheet.swift
 */

import React, { useEffect, useState } from 'react';
import { Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useTheme } from '../../hooks/useTheme';

const LABELS = ['', 'Weak', 'Very Weak', 'Poor', 'Mediocre', 'Fair', 'Good', 'Great', 'Excellent', 'Superb', 'Perfect'];
const STAR_SIZE = 40;

export default function DetailsRatingSheet({
  visible,
  title,
  initialRating,
  onSave,
  onRemove,
  onClose,
}: {
  visible: boolean;
  title: string;
  initialRating: number | null;
  onSave: (rating: number) => void;
  onRemove: () => void;
  onClose: () => void;
}) {
  const theme = useTheme();
  const [selection, setSelection] = useState(initialRating ?? 0);

  useEffect(() => {
    if (visible) setSelection(initialRating ?? 0);
  }, [visible, initialRating]);

  const iconFor = (star: number): keyof typeof Ionicons.glyphMap => {
    if (selection >= star * 2) return 'star';
    return selection === star * 2 - 1 ? 'star-half' : 'star-outline';
  };

  return (
    <Modal visible={visible} transparent animationType="fade" statusBarTranslucent onRequestClose={onClose}>
      <Pressable style={styles.scrim} onPress={onClose} accessibilityRole="button" accessibilityLabel="Close">
        <Pressable style={[styles.panel, { backgroundColor: theme.surfaceElevated }]} onPress={() => undefined}>
          <Text style={[styles.heading, { color: theme.textPrimary }]}>Rate on Trakt</Text>
          <Text numberOfLines={2} style={[styles.subheading, { color: theme.textSecondary }]}>
            {title}
          </Text>

          <View style={styles.stars} accessibilityLabel="Rating" accessibilityValue={{ text: selection ? `${selection} out of 10` : 'Not rated' }}>
            {[1, 2, 3, 4, 5].map((star) => (
              <View key={star} style={styles.star}>
                <Ionicons
                  name={iconFor(star)}
                  size={STAR_SIZE}
                  color={selection >= star * 2 - 1 ? theme.warning : theme.textTertiary}
                />
                <View style={styles.halves}>
                  <Pressable
                    style={styles.half}
                    onPress={() => setSelection(star * 2 - 1)}
                    accessibilityRole="button"
                    accessibilityLabel={`${star * 2 - 1} out of 10`}
                  />
                  <Pressable
                    style={styles.half}
                    onPress={() => setSelection(star * 2)}
                    accessibilityRole="button"
                    accessibilityLabel={`${star * 2} out of 10`}
                  />
                </View>
              </View>
            ))}
          </View>
          <Text style={[styles.valueLabel, { color: selection ? theme.textPrimary : theme.textTertiary }]}>
            {selection ? `${selection}/10 · ${LABELS[selection]}` : 'Choose a rating'}
          </Text>

          <View style={styles.buttons}>
            {initialRating != null ? (
              <Pressable onPress={onRemove} hitSlop={8} accessibilityRole="button">
                <Text style={[styles.buttonText, { color: theme.danger }]}>Remove</Text>
              </Pressable>
            ) : null}
            <View style={styles.spacer} />
            <Pressable onPress={onClose} hitSlop={8} accessibilityRole="button">
              <Text style={[styles.buttonText, { color: theme.textSecondary }]}>Cancel</Text>
            </Pressable>
            <Pressable
              disabled={selection === 0 || selection === initialRating}
              onPress={() => onSave(selection)}
              hitSlop={8}
              accessibilityRole="button"
              style={{ opacity: selection === 0 || selection === initialRating ? 0.4 : 1 }}
            >
              <Text style={[styles.buttonText, styles.save, { color: theme.accentBright }]}>Save</Text>
            </Pressable>
          </View>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

const styles = StyleSheet.create({
  scrim: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
    backgroundColor: 'rgba(0,0,0,0.6)',
  },
  panel: {
    width: '100%',
    maxWidth: 380,
    borderRadius: 18,
    padding: 20,
  },
  heading: {
    fontSize: 18,
    fontWeight: '700',
  },
  subheading: {
    fontSize: 14,
    marginTop: 4,
  },
  stars: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 6,
    marginTop: 20,
  },
  star: {
    width: STAR_SIZE,
    height: STAR_SIZE,
  },
  halves: {
    ...StyleSheet.absoluteFill,
    flexDirection: 'row',
  },
  half: {
    flex: 1,
  },
  valueLabel: {
    textAlign: 'center',
    fontSize: 14,
    fontWeight: '500',
    marginTop: 12,
    fontVariant: ['tabular-nums'],
  },
  buttons: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 22,
    gap: 22,
  },
  spacer: {
    flex: 1,
  },
  buttonText: {
    fontSize: 15,
    fontWeight: '600',
  },
  save: {
    fontWeight: '700',
  },
});
