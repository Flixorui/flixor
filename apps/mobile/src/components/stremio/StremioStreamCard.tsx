import React from 'react';
import { Ionicons } from '@expo/vector-icons';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import type { StremioPlayableStream } from '../../stremio/types';

type Props = {
  stream: StremioPlayableStream;
  onPress: () => void;
  disabled?: boolean;
  isCached?: boolean;
  resumePositionLabel?: string;
};

function badgeLabel(stream: StremioPlayableStream): string[] {
  const badges: string[] = [];
  const title = `${stream.name || ''} ${stream.title || ''}`.trim();
  const qualityMatch = title.match(/(\d{3,4})p/i);
  if (qualityMatch) {
    badges.push(qualityMatch[1] + 'p');
  }
  if (stream.size) {
    const sizeGb = stream.size / (1024 * 1024 * 1024);
    if (sizeGb >= 0.1) {
      badges.push(`${sizeGb.toFixed(sizeGb >= 10 ? 0 : 1)} GB`);
    }
  }
  if (stream.behaviorHints?.cached) {
    badges.push('Cached');
  }
  if (stream.isDebrid) {
    badges.push('Debrid');
  }
  if (stream.subtitles && stream.subtitles.length > 0) {
    badges.push('Subs');
  }
  return badges;
}

export default function StremioStreamCard({
  stream,
  onPress,
  disabled,
  isCached,
  resumePositionLabel,
}: Props) {
  const badges = badgeLabel(stream);

  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      style={[styles.card, disabled && styles.cardDisabled, isCached && styles.cardCached]}
    >
      <View style={styles.header}>
        <View style={styles.titleBlock}>
          <Text style={styles.title} numberOfLines={2}>
            {stream.name || stream.title || 'Unnamed stream'}
          </Text>
          {stream.description ? (
            <Text style={styles.description} numberOfLines={3}>
              {stream.description}
            </Text>
          ) : null}
        </View>
        <Ionicons
          name={disabled ? 'close-circle-outline' : 'play-circle-outline'}
          size={22}
          color={disabled ? '#fca5a5' : '#f9fafb'}
        />
      </View>

      {badges.length > 0 ? (
        <View style={styles.badges}>
          {badges.map((badge) => (
            <View key={badge} style={styles.badge}>
              <Text style={styles.badgeText}>{badge}</Text>
            </View>
          ))}
        </View>
      ) : null}

      {isCached || resumePositionLabel || stream.disabledReason ? (
        <View style={styles.footer}>
          {isCached ? (
            <Text style={styles.footerText}>Cached source</Text>
          ) : resumePositionLabel ? (
            <Text style={styles.footerText}>Resume {resumePositionLabel}</Text>
          ) : null}
          {stream.disabledReason ? (
            <Text style={styles.footerTextDanger}>{stream.disabledReason}</Text>
          ) : null}
        </View>
      ) : null}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  card: {
    borderRadius: 18,
    padding: 16,
    backgroundColor: 'rgba(20,20,24,0.92)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    gap: 12,
  },
  cardDisabled: {
    opacity: 0.7,
  },
  cardCached: {
    borderColor: '#f59e0b',
    backgroundColor: 'rgba(52, 33, 6, 0.85)',
  },
  header: {
    flexDirection: 'row',
    gap: 12,
    alignItems: 'flex-start',
  },
  titleBlock: {
    flex: 1,
    gap: 6,
  },
  title: {
    color: '#f9fafb',
    fontSize: 16,
    fontWeight: '800',
  },
  description: {
    color: '#d1d5db',
    fontSize: 13,
    lineHeight: 18,
  },
  badges: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  badge: {
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 999,
    backgroundColor: 'rgba(255,255,255,0.08)',
  },
  badgeText: {
    color: '#e5e7eb',
    fontSize: 12,
    fontWeight: '700',
  },
  footer: {
    gap: 4,
  },
  footerText: {
    color: '#fde68a',
    fontSize: 12,
    fontWeight: '700',
  },
  footerTextDanger: {
    color: '#fca5a5',
    fontSize: 12,
    fontWeight: '700',
  },
});
