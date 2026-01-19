import React, { useState, useEffect, useCallback } from 'react';
import { View, Text, ScrollView, Pressable, StyleSheet, Platform, RefreshControl, Alert } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import * as Clipboard from 'expo-clipboard';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import { appLogger, type LogEntry, type LogLevel } from '../../core/AppLogger';

const LOG_COLORS: Record<LogLevel, string> = {
  debug: '#6b7280', // gray
  info: '#e5e7eb',  // white
  warn: '#f59e0b',  // yellow/amber
  error: '#ef4444', // red
};

export default function LogsScreen() {
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const headerHeight = insets.top + 52;

  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [refreshing, setRefreshing] = useState(false);

  const loadLogs = useCallback(() => {
    setLogs(appLogger.getLogs());
  }, []);

  useEffect(() => {
    loadLogs();
    // Listen for log changes
    const unsubscribe = appLogger.addListener(loadLogs);
    return unsubscribe;
  }, [loadLogs]);

  const onRefresh = useCallback(() => {
    setRefreshing(true);
    loadLogs();
    setRefreshing(false);
  }, [loadLogs]);

  const handleCopyAll = useCallback(async () => {
    const exportedLogs = appLogger.exportLogs();
    await Clipboard.setStringAsync(exportedLogs);
    Alert.alert('Copied', 'All logs copied to clipboard');
  }, []);

  const handleClearLogs = useCallback(() => {
    Alert.alert(
      'Clear Logs',
      'Are you sure you want to clear all logs?',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Clear',
          style: 'destructive',
          onPress: () => {
            appLogger.clearLogs();
            loadLogs();
          },
        },
      ]
    );
  }, [loadLogs]);

  const formatTimestamp = (date: Date) => {
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    const seconds = date.getSeconds().toString().padStart(2, '0');
    const ms = date.getMilliseconds().toString().padStart(3, '0');
    return `${hours}:${minutes}:${seconds}.${ms}`;
  };

  const getLevelBadgeStyle = (level: LogLevel) => ({
    backgroundColor: `${LOG_COLORS[level]}20`,
    borderColor: LOG_COLORS[level],
  });

  return (
    <View style={styles.container}>
      <SettingsHeader title="Logs" onBack={() => nav.goBack()} />
      <ScrollView
        contentContainerStyle={[
          styles.content,
          { paddingTop: headerHeight + 12, paddingBottom: insets.bottom + 100 },
        ]}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={onRefresh}
            tintColor="#fff"
          />
        }
      >
        {/* Header */}
        <View style={styles.logoHeader}>
          <View style={styles.logoContainer}>
            <Ionicons name="document-text-outline" size={32} color="#3b82f6" />
          </View>
          <Text style={styles.logoTitle}>App Logs</Text>
          <Text style={styles.logoSubtitle}>
            {logs.length} {logs.length === 1 ? 'entry' : 'entries'}
          </Text>
        </View>

        {/* Action Buttons */}
        <View style={styles.actionRow}>
          <Pressable style={styles.actionButton} onPress={handleCopyAll}>
            <Ionicons name="copy-outline" size={18} color="#e5e7eb" />
            <Text style={styles.actionButtonText}>Copy All</Text>
          </Pressable>
          <Pressable style={styles.actionButton} onPress={handleClearLogs}>
            <Ionicons name="trash-outline" size={18} color="#ef4444" />
            <Text style={[styles.actionButtonText, { color: '#ef4444' }]}>Clear</Text>
          </Pressable>
          <Pressable style={styles.actionButton} onPress={onRefresh}>
            <Ionicons name="refresh-outline" size={18} color="#e5e7eb" />
            <Text style={styles.actionButtonText}>Refresh</Text>
          </Pressable>
        </View>

        {/* Logs */}
        <SettingsCard title="LOG ENTRIES">
          <View style={styles.logsContainer}>
            {logs.length === 0 ? (
              <View style={styles.emptyState}>
                <Ionicons name="document-outline" size={48} color="#4b5563" />
                <Text style={styles.emptyStateText}>No logs yet</Text>
                <Text style={styles.emptyStateSubtext}>
                  Enable debug logging in Advanced settings to capture detailed logs
                </Text>
              </View>
            ) : (
              [...logs].reverse().map((log, index) => (
                <View key={`${log.timestamp.getTime()}-${index}`} style={styles.logEntry}>
                  <View style={styles.logHeader}>
                    <Text style={styles.logTime}>{formatTimestamp(log.timestamp)}</Text>
                    <View style={[styles.levelBadge, getLevelBadgeStyle(log.level)]}>
                      <Text style={[styles.levelText, { color: LOG_COLORS[log.level] }]}>
                        {log.level.toUpperCase()}
                      </Text>
                    </View>
                  </View>
                  <Text style={[styles.logMessage, { color: LOG_COLORS[log.level] }]}>
                    {log.message}
                  </Text>
                  {log.data && (
                    <Text style={styles.logData}>{log.data}</Text>
                  )}
                </View>
              ))
            )}
          </View>
        </SettingsCard>

        {/* Info Note */}
        <View style={styles.infoNote}>
          <Ionicons name="information-circle-outline" size={16} color="#9ca3af" />
          <Text style={styles.infoNoteText}>
            Logs are stored in memory and will be cleared when the app restarts.
            Sensitive data like tokens and passwords are automatically redacted.
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
    backgroundColor: 'rgba(59, 130, 246, 0.2)',
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
  actionRow: {
    flexDirection: 'row',
    gap: 10,
    marginBottom: 16,
  },
  actionButton: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(255,255,255,0.08)',
    borderRadius: 12,
    paddingVertical: 12,
    gap: 6,
  },
  actionButtonText: {
    color: '#e5e7eb',
    fontSize: 14,
    fontWeight: '600',
  },
  logsContainer: {
    padding: 12,
  },
  emptyState: {
    alignItems: 'center',
    paddingVertical: 40,
  },
  emptyStateText: {
    color: '#9ca3af',
    fontSize: 16,
    fontWeight: '600',
    marginTop: 12,
  },
  emptyStateSubtext: {
    color: '#6b7280',
    fontSize: 13,
    textAlign: 'center',
    marginTop: 4,
    paddingHorizontal: 20,
  },
  logEntry: {
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.06)',
    paddingVertical: 10,
  },
  logHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginBottom: 4,
  },
  logTime: {
    color: '#6b7280',
    fontSize: 11,
    fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
  },
  levelBadge: {
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
    borderWidth: 1,
  },
  levelText: {
    fontSize: 9,
    fontWeight: '700',
    fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
  },
  logMessage: {
    fontSize: 13,
    lineHeight: 18,
    fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
  },
  logData: {
    color: '#6b7280',
    fontSize: 11,
    fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
    marginTop: 4,
    paddingLeft: 8,
    borderLeftWidth: 2,
    borderLeftColor: 'rgba(255,255,255,0.1)',
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
});
