import React, { useState, useCallback } from 'react';
import {
  View,
  Text,
  Pressable,
  StyleSheet,
  ActivityIndicator,
  Alert,
  Modal,
  ScrollView,
  TouchableOpacity,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import { useOverseerrStatus } from '../hooks/useOverseerrStatus';
import {
  isOverseerrReady,
  OverseerrStatus,
  OverseerrSeason,
  isSeasonAvailable,
  isSeasonPartiallyAvailable,
  isSeasonProcessing,
  isSeasonPending,
  canRequestSeason,
} from '../core/OverseerrService';
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
  const {
    status,
    canRequest,
    isLoading,
    isRequesting,
    submitRequest,
    submitSeasonRequest,
    seasons,
    hasRequestableSeasons,
    isPartiallyAvailableTv,
  } = useOverseerrStatus(tmdbId, mediaType);

  const [showSeasonPicker, setShowSeasonPicker] = useState(false);
  const [selectedSeasons, setSelectedSeasons] = useState<Set<number>>(new Set());

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

  // Filter seasons for display (exclude season 0)
  const displaySeasons = seasons.filter(s => s.seasonNumber > 0).sort((a, b) => a.seasonNumber - b.seasonNumber);

  const toggleSeason = useCallback((seasonNumber: number) => {
    setSelectedSeasons(prev => {
      const next = new Set(prev);
      if (next.has(seasonNumber)) {
        next.delete(seasonNumber);
      } else {
        next.add(seasonNumber);
      }
      return next;
    });
  }, []);

  const selectAllSeasons = useCallback(() => {
    const requestable = displaySeasons.filter(s => canRequestSeason(s)).map(s => s.seasonNumber);
    setSelectedSeasons(new Set(requestable));
  }, [displaySeasons]);

  const handleSeasonRequest = useCallback(async () => {
    if (selectedSeasons.size === 0) return;

    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    const seasonsArray = Array.from(selectedSeasons).sort((a, b) => a - b);
    const result = await submitSeasonRequest(seasonsArray);

    if (result.success) {
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
      setShowSeasonPicker(false);
      setSelectedSeasons(new Set());
      Alert.alert('Success', `Requested ${seasonsArray.length} season(s) of "${title}"!`);
    } else {
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
      Alert.alert('Error', result.error || 'Failed to submit request');
    }
  }, [selectedSeasons, submitSeasonRequest, title]);

  const handlePress = async () => {
    if (!isInteractive || isRequesting) return;

    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);

    // For partially available TV shows, show season picker
    if (isPartiallyAvailableTv) {
      setSelectedSeasons(new Set());
      setShowSeasonPicker(true);
      return;
    }

    // Show confirmation for regular requests
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
    <>
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

      {/* Season Picker Modal */}
      <Modal
        visible={showSeasonPicker}
        animationType="slide"
        presentationStyle="pageSheet"
        onRequestClose={() => setShowSeasonPicker(false)}
      >
        <View style={styles.modalContainer}>
          {/* Header */}
          <View style={styles.modalHeader}>
            <View>
              <Text style={styles.modalTitle}>Request Seasons</Text>
              <Text style={styles.modalSubtitle} numberOfLines={1}>{title}</Text>
            </View>
            <TouchableOpacity onPress={() => setShowSeasonPicker(false)} style={styles.closeButton}>
              <Ionicons name="close-circle" size={28} color="#9ca3af" />
            </TouchableOpacity>
          </View>

          {/* Warning if no requestable seasons */}
          {!hasRequestableSeasons && (
            <View style={styles.warningBanner}>
              <Ionicons name="warning" size={24} color="#f59e0b" />
              <Text style={styles.warningText}>
                All unavailable seasons have some episodes already downloaded. Overseerr cannot request the remaining episodes for partially downloaded seasons.
              </Text>
            </View>
          )}

          {/* Season List */}
          <ScrollView style={styles.seasonList} contentContainerStyle={styles.seasonListContent}>
            {displaySeasons.map(season => (
              <SeasonRow
                key={season.seasonNumber}
                season={season}
                isSelected={selectedSeasons.has(season.seasonNumber)}
                onToggle={() => {
                  if (canRequestSeason(season)) {
                    toggleSeason(season.seasonNumber);
                  }
                }}
              />
            ))}
          </ScrollView>

          {/* Footer */}
          <View style={styles.modalFooter}>
            {hasRequestableSeasons && (
              <TouchableOpacity onPress={selectAllSeasons} style={styles.selectAllButton}>
                <Text style={styles.selectAllText}>Select All</Text>
              </TouchableOpacity>
            )}
            <View style={styles.footerActions}>
              <TouchableOpacity
                onPress={() => setShowSeasonPicker(false)}
                style={styles.cancelButton}
              >
                <Text style={styles.cancelText}>{hasRequestableSeasons ? 'Cancel' : 'Close'}</Text>
              </TouchableOpacity>
              {hasRequestableSeasons && (
                <TouchableOpacity
                  onPress={handleSeasonRequest}
                  disabled={selectedSeasons.size === 0 || isRequesting}
                  style={[
                    styles.requestButton,
                    (selectedSeasons.size === 0 || isRequesting) && styles.requestButtonDisabled,
                  ]}
                >
                  {isRequesting ? (
                    <ActivityIndicator size="small" color="#fff" />
                  ) : (
                    <Text style={styles.requestButtonText}>
                      Request {selectedSeasons.size} Season{selectedSeasons.size !== 1 ? 's' : ''}
                    </Text>
                  )}
                </TouchableOpacity>
              )}
            </View>
          </View>
        </View>
      </Modal>
    </>
  );
}

// Season Row Component
interface SeasonRowProps {
  season: OverseerrSeason;
  isSelected: boolean;
  onToggle: () => void;
}

function SeasonRow({ season, isSelected, onToggle }: SeasonRowProps) {
  const isRequestable = canRequestSeason(season);
  const available = isSeasonAvailable(season);
  const partiallyAvailable = isSeasonPartiallyAvailable(season);
  const processing = isSeasonProcessing(season);
  const pending = isSeasonPending(season);

  const getStatusText = () => {
    if (available) return 'Available';
    if (processing) return 'Processing';
    if (pending) return 'Pending';
    if (partiallyAvailable) return 'Partial';
    return 'Not Available';
  };

  const getStatusColor = () => {
    if (available) return '#22c55e';
    if (processing || pending) return '#f59e0b';
    if (partiallyAvailable) return '#eab308';
    return '#9ca3af';
  };

  const getIconName = (): keyof typeof Ionicons.glyphMap => {
    if (available) return 'checkmark-circle';
    if (partiallyAvailable) return 'alert-circle';
    if (isSelected) return 'checkmark-circle';
    return 'ellipse-outline';
  };

  const getIconColor = () => {
    if (available) return '#22c55e';
    if (partiallyAvailable) return '#eab308';
    if (isSelected) return '#6366f1';
    return '#6b7280';
  };

  return (
    <TouchableOpacity
      onPress={onToggle}
      disabled={!isRequestable}
      style={[
        styles.seasonRow,
        isSelected && isRequestable && styles.seasonRowSelected,
        !isRequestable && styles.seasonRowDisabled,
      ]}
      activeOpacity={isRequestable ? 0.7 : 1}
    >
      <View style={styles.seasonRowContent}>
        <Ionicons name={getIconName()} size={24} color={getIconColor()} />
        <Text style={[styles.seasonName, !isRequestable && styles.seasonNameDisabled]}>
          Season {season.seasonNumber}
        </Text>
        <Text style={[styles.seasonStatus, { color: getStatusColor() }]}>
          {getStatusText()}
        </Text>
      </View>
      {partiallyAvailable && (
        <Text style={styles.seasonWarning}>
          Some episodes available - Overseerr cannot request remaining
        </Text>
      )}
    </TouchableOpacity>
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
  // Modal styles
  modalContainer: {
    flex: 1,
    backgroundColor: '#111',
  },
  modalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    padding: 20,
    borderBottomWidth: 1,
    borderBottomColor: '#333',
  },
  modalTitle: {
    fontSize: 20,
    fontWeight: '600',
    color: '#fff',
  },
  modalSubtitle: {
    fontSize: 14,
    color: '#9ca3af',
    marginTop: 4,
  },
  closeButton: {
    padding: 4,
  },
  warningBanner: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 12,
    padding: 16,
    margin: 16,
    backgroundColor: 'rgba(245, 158, 11, 0.1)',
    borderRadius: 8,
  },
  warningText: {
    flex: 1,
    fontSize: 13,
    color: '#9ca3af',
    lineHeight: 18,
  },
  seasonList: {
    flex: 1,
  },
  seasonListContent: {
    padding: 16,
    gap: 8,
  },
  seasonRow: {
    backgroundColor: 'rgba(255, 255, 255, 0.05)',
    borderRadius: 8,
    padding: 16,
  },
  seasonRowSelected: {
    backgroundColor: 'rgba(99, 102, 241, 0.15)',
  },
  seasonRowDisabled: {
    opacity: 0.5,
  },
  seasonRowContent: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  seasonName: {
    flex: 1,
    fontSize: 16,
    fontWeight: '500',
    color: '#fff',
  },
  seasonNameDisabled: {
    color: '#9ca3af',
  },
  seasonStatus: {
    fontSize: 13,
    fontWeight: '500',
  },
  seasonWarning: {
    fontSize: 11,
    color: '#9ca3af',
    marginTop: 8,
    marginLeft: 36,
  },
  modalFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: 20,
    borderTopWidth: 1,
    borderTopColor: '#333',
  },
  selectAllButton: {
    paddingVertical: 8,
  },
  selectAllText: {
    fontSize: 14,
    color: '#6366f1',
    fontWeight: '500',
  },
  footerActions: {
    flexDirection: 'row',
    gap: 12,
  },
  cancelButton: {
    paddingHorizontal: 16,
    paddingVertical: 10,
  },
  cancelText: {
    fontSize: 14,
    color: '#9ca3af',
    fontWeight: '500',
  },
  requestButton: {
    backgroundColor: '#6366f1',
    paddingHorizontal: 20,
    paddingVertical: 10,
    borderRadius: 8,
    minWidth: 120,
    alignItems: 'center',
  },
  requestButtonDisabled: {
    backgroundColor: '#4b5563',
    opacity: 0.5,
  },
  requestButtonText: {
    fontSize: 14,
    color: '#fff',
    fontWeight: '600',
  },
});
