/**
 * One heading style and one left edge for every section of the details page.
 * macOS reference: Views/Details/DetailsSectionHeading.swift
 */

import React from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useTheme } from '../../hooks/useTheme';

export const DetailsSectionStyle = {
  /** Left edge of every heading and row. */
  inset: 16,
  /** Space between a heading and its content. */
  headingGap: 12,
  /** Space between sections on the unified page. */
  sectionGap: 32,
  fontSize: 20,
} as const;

interface HeadingProps {
  title: string;
  /** Extra content on the right, such as a sort control. */
  right?: React.ReactNode;
  /** Adds a chevron and makes the title tappable. */
  onPress?: () => void;
  /** Muted text after the title, such as a count. */
  detail?: string;
}

export default function DetailsSectionHeading({ title, right, onPress, detail }: HeadingProps) {
  const theme = useTheme();
  const text = (
    <Text
      accessibilityRole="header"
      numberOfLines={1}
      style={[styles.title, { color: theme.textPrimary }]}
    >
      {title}
    </Text>
  );
  return (
    <View style={styles.row}>
      <View style={styles.titleWrap}>
        {onPress ? (
          <Pressable onPress={onPress} style={styles.titleWrap} accessibilityRole="button">
            {text}
            <Ionicons name="chevron-forward" size={18} color={theme.textPrimary} style={styles.chevron} />
          </Pressable>
        ) : (
          text
        )}
        {detail ? <Text style={[styles.detail, { color: theme.textTertiary }]}>{detail}</Text> : null}
      </View>
      {right}
    </View>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: DetailsSectionStyle.inset,
    marginBottom: DetailsSectionStyle.headingGap,
    gap: 12,
  },
  titleWrap: {
    flexDirection: 'row',
    alignItems: 'center',
    flexShrink: 1,
  },
  title: {
    fontSize: DetailsSectionStyle.fontSize,
    fontWeight: '700',
    letterSpacing: 0.2,
    includeFontPadding: false,
    flexShrink: 1,
  },
  chevron: {
    marginLeft: 4,
    marginTop: 1,
  },
  detail: {
    fontSize: 13,
    marginLeft: 8,
  },
});
