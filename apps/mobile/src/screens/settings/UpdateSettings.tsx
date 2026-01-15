import React, { useState, useEffect, useCallback } from 'react';
import { View, Text, ScrollView, Pressable, StyleSheet, Switch, ActivityIndicator, Platform } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import AsyncStorage from '@react-native-async-storage/async-storage';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import UpdateService, { type UpdateState } from '../../core/UpdateService';

const STORAGE_KEYS = {
  OTA_ALERTS_ENABLED: 'flixor:ota_alerts_enabled',
};

type UpdateStatus = 'idle' | 'checking' | 'available' | 'downloading' | 'installing' | 'success' | 'error';

export default function UpdateSettings() {
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const headerHeight = insets.top + 52;

  const [updateStatus, setUpdateStatus] = useState<UpdateStatus>('idle');
  const [updateProgress, setUpdateProgress] = useState(0);
  const [updateAvailable, setUpdateAvailable] = useState(false);
  const [updateManifest, setUpdateManifest] = useState<any>(null);
  const [releaseNotes, setReleaseNotes] = useState<string>('');
  const [currentState, setCurrentState] = useState<UpdateState | null>(null);
  const [lastChecked, setLastChecked] = useState<Date | null>(null);
  const [statusMessage, setStatusMessage] = useState('Ready to check for updates');
  const [otaAlertsEnabled, setOtaAlertsEnabled] = useState(true);
  const [debugLogs, setDebugLogs] = useState<string[]>([]);

  // Load preferences and current state on mount
  useEffect(() => {
    const loadData = async () => {
      try {
        const enabled = await AsyncStorage.getItem(STORAGE_KEYS.OTA_ALERTS_ENABLED);
        if (enabled !== null) {
          setOtaAlertsEnabled(enabled === 'true');
        }

        const service = UpdateService.getInstance();
        setCurrentState(service.getUpdateState());
      } catch (error) {
        console.error('Failed to load update settings:', error);
      }
    };
    loadData();
    // Auto-check for updates on mount
    checkForUpdates();
  }, []);

  const checkForUpdates = useCallback(async () => {
    setUpdateStatus('checking');
    setStatusMessage('Checking for updates...');
    setUpdateProgress(0);

    try {
      const service = UpdateService.getInstance();
      // Use forceCheckForUpdates to bypass expo-updates caching
      const result = await service.forceCheckForUpdates();
      setLastChecked(new Date());

      if (result.isAvailable && result.manifest) {
        setUpdateAvailable(true);
        setUpdateManifest(result.manifest);
        setReleaseNotes(result.releaseNotes || '');
        setUpdateStatus('available');
        setStatusMessage('Update available');
      } else {
        setUpdateAvailable(false);
        setUpdateManifest(null);
        setReleaseNotes('');
        setUpdateStatus('idle');
        setStatusMessage('You\'re up to date');
      }
      // Capture debug logs
      setDebugLogs(service.getLogs().slice(-10));
    } catch (error) {
      setUpdateStatus('error');
      setStatusMessage(`Error: ${error instanceof Error ? error.message : 'Unknown error'}`);
      const service = UpdateService.getInstance();
      setDebugLogs(service.getLogs().slice(-10));
    }
  }, []);

  const installUpdate = useCallback(async () => {
    setUpdateStatus('downloading');
    setStatusMessage('Downloading update...');
    setUpdateProgress(0);

    // Simulate progress
    const progressInterval = setInterval(() => {
      setUpdateProgress(prev => {
        if (prev >= 90) return prev;
        return prev + Math.random() * 15;
      });
    }, 300);

    try {
      const service = UpdateService.getInstance();
      const success = await service.downloadAndApply();

      clearInterval(progressInterval);
      setUpdateProgress(100);

      if (success) {
        setUpdateStatus('success');
        setStatusMessage('Update installed! App will reload...');
      } else {
        setUpdateStatus('error');
        setStatusMessage('No update to install');
      }
    } catch (error) {
      clearInterval(progressInterval);
      setUpdateStatus('error');
      setStatusMessage(`Install failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
  }, []);

  const toggleOtaAlerts = useCallback(async (enabled: boolean) => {
    setOtaAlertsEnabled(enabled);
    await AsyncStorage.setItem(STORAGE_KEYS.OTA_ALERTS_ENABLED, enabled.toString());
  }, []);

  const getStatusIcon = () => {
    switch (updateStatus) {
      case 'checking':
        return 'refresh-outline';
      case 'available':
        return 'arrow-down-circle-outline';
      case 'downloading':
      case 'installing':
        return 'cloud-download-outline';
      case 'success':
        return 'checkmark-circle-outline';
      case 'error':
        return 'alert-circle-outline';
      default:
        return 'refresh-outline';
    }
  };

  const getStatusColor = () => {
    switch (updateStatus) {
      case 'available':
      case 'success':
        return '#22c55e';
      case 'error':
        return '#ef4444';
      case 'checking':
      case 'downloading':
      case 'installing':
        return '#3b82f6';
      default:
        return '#9ca3af';
    }
  };

  const formatDate = (date: Date) => {
    return date.toLocaleString();
  };

  const isLoading = updateStatus === 'checking' || updateStatus === 'downloading' || updateStatus === 'installing';

  return (
    <View style={styles.container}>
      <SettingsHeader title="App Updates" onBack={() => nav.goBack()} />
      <ScrollView contentContainerStyle={[styles.content, { paddingTop: headerHeight + 12, paddingBottom: insets.bottom + 100 }]}>
        {/* Header */}
        <View style={styles.logoHeader}>
          <View style={[styles.logoContainer, { backgroundColor: `${getStatusColor()}20` }]}>
            <Ionicons name={getStatusIcon()} size={32} color={getStatusColor()} />
          </View>
          <Text style={styles.logoTitle}>OTA Updates</Text>
          <Text style={styles.logoSubtitle}>Over-the-air update management</Text>
        </View>

        {/* Status Card */}
        <SettingsCard title="UPDATE STATUS">
          <View style={styles.statusSection}>
            <View style={styles.statusRow}>
              <View style={[styles.statusIndicator, { backgroundColor: `${getStatusColor()}30` }]}>
                {isLoading ? (
                  <ActivityIndicator size="small" color={getStatusColor()} />
                ) : (
                  <Ionicons name={getStatusIcon()} size={20} color={getStatusColor()} />
                )}
              </View>
              <View style={styles.statusContent}>
                <Text style={styles.statusTitle}>{statusMessage}</Text>
                {lastChecked && (
                  <Text style={styles.statusSubtitle}>Last checked: {formatDate(lastChecked)}</Text>
                )}
              </View>
            </View>

            {/* Progress Bar */}
            {(updateStatus === 'downloading' || updateStatus === 'installing') && (
              <View style={styles.progressSection}>
                <View style={styles.progressHeader}>
                  <Text style={styles.progressLabel}>
                    {updateStatus === 'downloading' ? 'Downloading' : 'Installing'}
                  </Text>
                  <Text style={styles.progressPercent}>{Math.round(updateProgress)}%</Text>
                </View>
                <View style={styles.progressBar}>
                  <View style={[styles.progressFill, { width: `${updateProgress}%` }]} />
                </View>
              </View>
            )}

            {/* Action Buttons */}
            <View style={styles.actionSection}>
              <Pressable
                style={[styles.primaryButton, isLoading && styles.buttonDisabled]}
                onPress={checkForUpdates}
                disabled={isLoading}
              >
                {updateStatus === 'checking' ? (
                  <ActivityIndicator size="small" color="#111827" />
                ) : (
                  <Ionicons name="refresh-outline" size={18} color="#111827" />
                )}
                <Text style={styles.primaryButtonText}>
                  {updateStatus === 'checking' ? 'Checking...' : 'Check for Updates'}
                </Text>
              </Pressable>

              {updateAvailable && updateStatus !== 'success' && (
                <Pressable
                  style={[styles.installButton, (updateStatus === 'downloading' || updateStatus === 'installing') && styles.buttonDisabled]}
                  onPress={installUpdate}
                  disabled={updateStatus === 'downloading' || updateStatus === 'installing'}
                >
                  {updateStatus === 'downloading' || updateStatus === 'installing' ? (
                    <ActivityIndicator size="small" color="#fff" />
                  ) : (
                    <Ionicons name="download-outline" size={18} color="#fff" />
                  )}
                  <Text style={styles.installButtonText}>
                    {updateStatus === 'downloading' ? 'Downloading...' : updateStatus === 'installing' ? 'Installing...' : 'Install Update'}
                  </Text>
                </Pressable>
              )}
            </View>
          </View>
        </SettingsCard>

        {/* Release Notes */}
        {updateAvailable && releaseNotes && (
          <SettingsCard title="RELEASE NOTES">
            <View style={styles.releaseNotesSection}>
              <Text style={styles.releaseNotes}>{releaseNotes}</Text>
            </View>
          </SettingsCard>
        )}

        {/* Current Version Info */}
        <SettingsCard title="VERSION INFO">
          <SettingItem
            title="Runtime Version"
            description={currentState?.runtimeVersion || 'Unknown'}
            icon="code-outline"
            isLast={false}
          />
          <SettingItem
            title="Update Channel"
            description={currentState?.channel || 'Default'}
            icon="git-branch-outline"
            isLast={false}
          />
          <SettingItem
            title="Updates Enabled"
            description={currentState?.isEnabled ? 'Yes' : 'No (Development Mode)'}
            icon="cloud-outline"
            isLast={false}
          />
          <SettingItem
            title="Current Bundle"
            description={currentState?.isEmbeddedLaunch ? 'Embedded (built-in)' : (currentState?.updateId?.substring(0, 12) + '...' || 'Unknown')}
            icon="cube-outline"
            isLast={true}
          />
        </SettingsCard>

        {/* Notification Settings */}
        <SettingsCard title="NOTIFICATIONS">
          <SettingItem
            title="Update Alerts"
            description="Show popup when updates are available"
            icon="notifications-outline"
            renderRight={() => (
              <Switch
                value={otaAlertsEnabled}
                onValueChange={toggleOtaAlerts}
              />
            )}
            isLast={true}
          />
        </SettingsCard>

        {/* Debug Logs */}
        {debugLogs.length > 0 && (
          <SettingsCard title="DEBUG LOGS">
            <View style={styles.debugSection}>
              {debugLogs.map((log, index) => (
                <Text key={index} style={styles.debugText}>{log}</Text>
              ))}
            </View>
          </SettingsCard>
        )}

        {/* Info Note */}
        <View style={styles.infoNote}>
          <Ionicons name="information-circle-outline" size={16} color="#9ca3af" />
          <Text style={styles.infoNoteText}>
            OTA updates allow instant app updates without going through the app store. Updates are downloaded in the background and applied on restart.
          </Text>
        </View>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0b0b0d',
  },
  content: {
    paddingHorizontal: 16,
    paddingBottom: 40,
  },
  logoHeader: {
    alignItems: 'center',
    marginBottom: 20,
    paddingVertical: 16,
  },
  logoContainer: {
    width: 64,
    height: 64,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 12,
  },
  logoTitle: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '700',
  },
  logoSubtitle: {
    color: '#9ca3af',
    fontSize: 13,
    marginTop: 4,
  },
  statusSection: {
    padding: 16,
  },
  statusRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 16,
  },
  statusIndicator: {
    width: 44,
    height: 44,
    borderRadius: 22,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 14,
  },
  statusContent: {
    flex: 1,
  },
  statusTitle: {
    color: '#f9fafb',
    fontSize: 16,
    fontWeight: '600',
  },
  statusSubtitle: {
    color: '#9ca3af',
    fontSize: 12,
    marginTop: 2,
  },
  progressSection: {
    marginBottom: 16,
  },
  progressHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 8,
  },
  progressLabel: {
    color: '#9ca3af',
    fontSize: 13,
    fontWeight: '500',
  },
  progressPercent: {
    color: '#3b82f6',
    fontSize: 13,
    fontWeight: '600',
  },
  progressBar: {
    height: 6,
    backgroundColor: 'rgba(59, 130, 246, 0.2)',
    borderRadius: 3,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    backgroundColor: '#3b82f6',
    borderRadius: 3,
  },
  actionSection: {
    gap: 10,
  },
  primaryButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#fff',
    borderRadius: 12,
    paddingVertical: 14,
    gap: 8,
  },
  primaryButtonText: {
    color: '#111827',
    fontSize: 15,
    fontWeight: '600',
  },
  installButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#22c55e',
    borderRadius: 12,
    paddingVertical: 14,
    gap: 8,
  },
  installButtonText: {
    color: '#fff',
    fontSize: 15,
    fontWeight: '600',
  },
  buttonDisabled: {
    opacity: 0.6,
  },
  releaseNotesSection: {
    padding: 14,
  },
  releaseNotes: {
    color: '#e5e7eb',
    fontSize: 14,
    lineHeight: 20,
  },
  infoNote: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 8,
    paddingHorizontal: 4,
    marginTop: 8,
  },
  infoNoteText: {
    flex: 1,
    color: '#9ca3af',
    fontSize: 12,
    lineHeight: 18,
  },
  debugSection: {
    padding: 12,
  },
  debugText: {
    color: '#6b7280',
    fontSize: 10,
    fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
    marginBottom: 4,
  },
});
