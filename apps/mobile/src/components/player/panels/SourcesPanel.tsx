import React, { useEffect, useMemo } from 'react';
import { ActivityIndicator, ScrollView, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useTheme } from '../../../hooks/useTheme';
import { resolutionBucket } from '../../../stremio/StremioSourceRanking';
import type { StremioPlayableStream } from '../../../stremio/types';
import PlayerPanel from './PlayerPanel';

type Props = {
  sources: StremioPlayableStream[];
  currentSourceId: string | null;
  isRefreshing: boolean;
  sourceId: (stream: StremioPlayableStream) => string;
  onAppear: () => void;
  onRefresh: () => void;
  onSelect: (stream: StremioPlayableStream) => void;
  onClose: () => void;
};

function formatSize(bytes: number): string {
  const gigabytes = bytes / (1024 * 1024 * 1024);
  if (gigabytes >= 1) return `${gigabytes.toFixed(gigabytes >= 10 ? 0 : 1)} GB`;
  return `${Math.round(bytes / (1024 * 1024))} MB`;
}

function badgesFor(stream: StremioPlayableStream): string[] {
  const badges: string[] = [];
  const bucket = resolutionBucket(stream);
  if (bucket) badges.push(bucket === 2160 ? '4K' : `${bucket}p`);
  if (stream.behaviorHints?.cached) badges.push('Cached');
  if (stream.isDebrid) badges.push('Debrid');
  if (stream.size && stream.size > 0) badges.push(formatSize(stream.size));
  return badges;
}

/** Switch addon source during playback. Playback continues from the same spot. */
export default function SourcesPanel({
  sources,
  currentSourceId,
  isRefreshing,
  sourceId,
  onAppear,
  onRefresh,
  onSelect,
  onClose,
}: Props) {
  const theme = useTheme();

  useEffect(() => {
    onAppear();
    // Runs once per open; onAppear is safe to skip when its identity changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const groups = useMemo(() => {
    const byAddon = new Map<string, StremioPlayableStream[]>();
    for (const source of sources) {
      if (!source.playable) continue;
      const addon = source.addonName || 'Stremio';
      byAddon.set(addon, [...(byAddon.get(addon) || []), source]);
    }
    return Array.from(byAddon.entries());
  }, [sources]);

  return (
    <PlayerPanel
      title="Sources"
      onClose={onClose}
      headerAccessory={
        isRefreshing ? (
          <ActivityIndicator size="small" color={theme.textSecondary} />
        ) : (
          <TouchableOpacity onPress={onRefresh} hitSlop={10} accessibilityRole="button" accessibilityLabel="Refresh sources">
            <Ionicons name="refresh" size={20} color={theme.textSecondary} />
          </TouchableOpacity>
        )
      }
    >
      <ScrollView contentContainerStyle={styles.content}>
        {groups.length === 0 ? (
          <Text style={[styles.empty, { color: theme.textSecondary }]}>
            {isRefreshing ? 'Looking for sources…' : 'No other sources found for this title.'}
          </Text>
        ) : null}
        {groups.map(([addon, streams]) => (
          <View key={addon}>
            <Text style={[styles.addon, { color: theme.textTertiary }]}>{addon}</Text>
            {streams.map((stream) => {
              const id = sourceId(stream);
              const isCurrent = id === currentSourceId;
              const badges = badgesFor(stream);
              return (
                <TouchableOpacity
                  key={id}
                  style={[styles.row, isCurrent && { backgroundColor: theme.accentSoft }]}
                  onPress={() => onSelect(stream)}
                  accessibilityRole="button"
                  accessibilityState={{ selected: isCurrent }}
                >
                  <Ionicons
                    name={isCurrent ? 'checkmark-circle' : 'ellipse-outline'}
                    size={20}
                    color={isCurrent ? theme.accentBright : theme.textTertiary}
                  />
                  <View style={styles.rowText}>
                    <Text style={[styles.rowTitle, { color: theme.textPrimary }]} numberOfLines={3}>
                      {stream.title || stream.name || 'Source'}
                    </Text>
                    {badges.length > 0 ? (
                      <View style={styles.badges}>
                        {badges.map((badge) => (
                          <Text
                            key={badge}
                            style={[styles.badge, { color: theme.textSecondary, backgroundColor: theme.surfaceOverlay }]}
                          >
                            {badge}
                          </Text>
                        ))}
                      </View>
                    ) : null}
                  </View>
                </TouchableOpacity>
              );
            })}
          </View>
        ))}
      </ScrollView>
    </PlayerPanel>
  );
}

const styles = StyleSheet.create({
  content: {
    padding: 8,
    paddingBottom: 16,
  },
  empty: {
    padding: 12,
    fontSize: 14,
  },
  addon: {
    fontSize: 12,
    fontWeight: '700',
    paddingHorizontal: 8,
    paddingTop: 10,
    paddingBottom: 6,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 10,
    padding: 8,
    borderRadius: 8,
  },
  rowText: {
    flex: 1,
    gap: 6,
  },
  rowTitle: {
    fontSize: 13,
    lineHeight: 18,
  },
  badges: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
  },
  badge: {
    overflow: 'hidden',
    fontSize: 11,
    fontWeight: '700',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
  },
});
