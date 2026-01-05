import React from 'react';
import { View, Text, Pressable, StyleSheet, ActivityIndicator, Alert } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import { useOverseerrStatus } from '../hooks/useOverseerrStatus';
import { isOverseerrReady, OverseerrStatus } from '../core/OverseerrService';
import OverseerrIcon from './icons/OverseerrIcon';

interface RequestButtonProps {
  tmdbId: number | string | undefined;
  mediaType: 'movie' | 'tv';
  title: string;
  compact?: boolean;
}

interface StatusConfig {
  label: string;
  icon: keyof typeof Ionicons.glyphMap;
  color: string;
  bgColor: string;
  pressable: boolean;
}

const STATUS_CONFIG: Record<OverseerrStatus, StatusConfig> = {
  not_requested: {
    label: 'Request',
    icon: 'add-circle-outline',
    color: '#fff',
    bgColor: '#6366f1',
    pressable: true,
  },
  pending: {
    label: 'Pending',
    icon: 'time-outline',
    color: '#fbbf24',
    bgColor: 'rgba(251, 191, 36, 0.15)',
    pressable: false,
  },
  approved: {
    label: 'Approved',
    icon: 'checkmark-circle-outline',
    color: '#22c55e',
    bgColor: 'rgba(34, 197, 94, 0.15)',
    pressable: false,
  },
  declined: {
    label: 'Declined',
    icon: 'close-circle-outline',
    color: '#ef4444',
    bgColor: 'rgba(239, 68, 68, 0.15)',
    pressable: true,
  },
  processing: {
    label: 'Processing',
    icon: 'sync-outline',
    color: '#3b82f6',
    bgColor: 'rgba(59, 130, 246, 0.15)',
    pressable: false,
  },
  partially_available: {
    label: 'Partial',
    icon: 'pie-chart-outline',
    color: '#f59e0b',
    bgColor: 'rgba(245, 158, 11, 0.15)',
    pressable: true,
  },
  available: {
    label: 'Available',
    icon: 'checkmark-circle',
    color: '#22c55e',
    bgColor: 'rgba(34, 197, 94, 0.15)',
    pressable: false,
  },
  unknown: {
    label: 'Request',
    icon: 'add-circle-outline',
    color: '#fff',
    bgColor: '#6366f1',
    pressable: true,
  },
};

export default function RequestButton({
  tmdbId,
  mediaType,
  title,
  compact = false,
}: RequestButtonProps) {
  const { status, canRequest, isLoading, isRequesting, submitRequest } = useOverseerrStatus(
    tmdbId,
    mediaType
  );

  // Don't render if Overseerr is not configured
  if (!isOverseerrReady()) {
    return null;
  }

  // Don't render if no tmdbId
  if (!tmdbId) {
    return null;
  }

  const config = STATUS_CONFIG[status];
  const isInteractive = config.pressable && canRequest;

  const handlePress = async () => {
    if (!isInteractive || isRequesting) return;

    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);

    // Show confirmation
    Alert.alert(
      `Request ${mediaType === 'movie' ? 'Movie' : 'TV Show'}`,
      `Do you want to request "${title}"?`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Request',
          onPress: async () => {
            Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
            const result = await submitRequest();

            if (result.success) {
              Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
              Alert.alert('Success', `"${title}" has been requested!`);
            } else {
              Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
              Alert.alert('Error', result.error || 'Failed to submit request');
            }
          },
        },
      ]
    );
  };

  if (isLoading) {
    return (
      <View style={[styles.button, styles.loadingButton, compact && styles.compact]}>
        <ActivityIndicator size="small" color="#9ca3af" />
      </View>
    );
  }

  return (
    <Pressable
      onPress={handlePress}
      disabled={!isInteractive || isRequesting}
      style={({ pressed }) => [
        styles.button,
        { backgroundColor: config.bgColor },
        compact && styles.compact,
        pressed && isInteractive && styles.pressed,
        !isInteractive && styles.nonInteractive,
      ]}
    >
      {isRequesting ? (
        <ActivityIndicator size="small" color={config.color} />
      ) : (
        <>
          {config.pressable ? (
            <OverseerrIcon size={compact ? 16 : 18} color={config.color} />
          ) : (
            <Ionicons name={config.icon} size={compact ? 16 : 18} color={config.color} />
          )}
          <Text style={[styles.label, { color: config.color }, compact && styles.compactLabel]}>
            {config.label}
          </Text>
        </>
      )}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  button: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 8,
    minWidth: 100,
  },
  compact: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    minWidth: 80,
  },
  loadingButton: {
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
  },
  pressed: {
    opacity: 0.8,
    transform: [{ scale: 0.98 }],
  },
  nonInteractive: {
    opacity: 0.9,
  },
  label: {
    fontSize: 14,
    fontWeight: '600',
  },
  compactLabel: {
    fontSize: 12,
  },
});
