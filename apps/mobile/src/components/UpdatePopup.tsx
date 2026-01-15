/**
 * UpdatePopup - OTA Update notification modal
 *
 * Shows when a new update is available with options to:
 * - Update Now (downloads and reloads app)
 * - Later (snoozes for 6 hours)
 * - Dismiss (hides until next update version)
 */

import React from 'react';
import {
  View,
  Text,
  Modal,
  Pressable,
  StyleSheet,
  ActivityIndicator,
  ScrollView,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import type { UpdateInfo } from '../core/UpdateService';

interface UpdatePopupProps {
  visible: boolean;
  updateInfo: UpdateInfo | null;
  isDownloading: boolean;
  onUpdateNow: () => void;
  onUpdateLater: () => void;
  onDismiss: () => void;
}

export default function UpdatePopup({
  visible,
  updateInfo,
  isDownloading,
  onUpdateNow,
  onUpdateLater,
  onDismiss,
}: UpdatePopupProps) {
  if (!visible || !updateInfo) return null;

  const releaseNotes = updateInfo.releaseNotes;

  return (
    <Modal
      visible={visible}
      transparent
      animationType="fade"
      onRequestClose={onDismiss}
    >
      <View style={styles.overlay}>
        <View style={styles.container}>
          {/* Header */}
          <View style={styles.header}>
            <View style={styles.iconContainer}>
              <Ionicons name="rocket-outline" size={32} color="#10B981" />
            </View>
            <Text style={styles.title}>Update Available</Text>
            <Text style={styles.subtitle}>
              A new version of Flixor is ready to install
            </Text>
          </View>

          {/* Release Notes */}
          {releaseNotes && (
            <View style={styles.notesContainer}>
              <Text style={styles.notesLabel}>What's New</Text>
              <ScrollView style={styles.notesScroll} showsVerticalScrollIndicator={false}>
                <Text style={styles.notesText}>{releaseNotes}</Text>
              </ScrollView>
            </View>
          )}

          {/* Buttons */}
          <View style={styles.buttonContainer}>
            {/* Update Now Button */}
            <Pressable
              style={[styles.button, styles.primaryButton]}
              onPress={onUpdateNow}
              disabled={isDownloading}
            >
              {isDownloading ? (
                <ActivityIndicator color="#000" size="small" />
              ) : (
                <>
                  <Ionicons name="download-outline" size={20} color="#000" />
                  <Text style={styles.primaryButtonText}>Update Now</Text>
                </>
              )}
            </Pressable>

            {/* Later Button */}
            <Pressable
              style={[styles.button, styles.secondaryButton]}
              onPress={onUpdateLater}
              disabled={isDownloading}
            >
              <Ionicons name="time-outline" size={20} color="#fff" />
              <Text style={styles.secondaryButtonText}>Later</Text>
            </Pressable>

            {/* Dismiss Link */}
            <Pressable
              style={styles.dismissButton}
              onPress={onDismiss}
              disabled={isDownloading}
            >
              <Text style={styles.dismissText}>Don't show again for this update</Text>
            </Pressable>
          </View>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.8)',
    justifyContent: 'center',
    alignItems: 'center',
    padding: 24,
  },
  container: {
    backgroundColor: '#1a1a1a',
    borderRadius: 16,
    width: '100%',
    maxWidth: 400,
    padding: 24,
    borderWidth: 1,
    borderColor: 'rgba(255, 255, 255, 0.1)',
  },
  header: {
    alignItems: 'center',
    marginBottom: 20,
  },
  iconContainer: {
    width: 64,
    height: 64,
    borderRadius: 32,
    backgroundColor: 'rgba(16, 185, 129, 0.15)',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 16,
  },
  title: {
    fontSize: 22,
    fontWeight: '700',
    color: '#fff',
    marginBottom: 8,
  },
  subtitle: {
    fontSize: 14,
    color: 'rgba(255, 255, 255, 0.6)',
    textAlign: 'center',
  },
  notesContainer: {
    backgroundColor: 'rgba(255, 255, 255, 0.05)',
    borderRadius: 12,
    padding: 16,
    marginBottom: 20,
    maxHeight: 150,
  },
  notesLabel: {
    fontSize: 12,
    fontWeight: '600',
    color: 'rgba(255, 255, 255, 0.5)',
    marginBottom: 8,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  notesScroll: {
    maxHeight: 100,
  },
  notesText: {
    fontSize: 14,
    color: 'rgba(255, 255, 255, 0.8)',
    lineHeight: 20,
  },
  buttonContainer: {
    gap: 12,
  },
  button: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 14,
    paddingHorizontal: 24,
    borderRadius: 10,
    gap: 8,
  },
  primaryButton: {
    backgroundColor: '#10B981',
  },
  primaryButtonText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#000',
  },
  secondaryButton: {
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
  },
  secondaryButtonText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#fff',
  },
  dismissButton: {
    alignItems: 'center',
    paddingVertical: 8,
  },
  dismissText: {
    fontSize: 13,
    color: 'rgba(255, 255, 255, 0.4)',
    textDecorationLine: 'underline',
  },
});
