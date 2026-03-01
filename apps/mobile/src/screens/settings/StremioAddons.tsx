import React, { useCallback, useState } from 'react';
import {
  Alert,
  Linking,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useFocusEffect, useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingsHeader from '../../components/settings/SettingsHeader';
import { appLogger } from '../../core/AppLogger';
import { stremioService } from '../../stremio/StremioService';

type AddonSummary = Awaited<ReturnType<typeof stremioService.getAddonSummary>>[number];

export default function StremioAddons() {
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const headerHeight = insets.top + 52;
  const [manifestUrl, setManifestUrl] = useState('');
  const [addons, setAddons] = useState<AddonSummary[]>([]);
  const [installing, setInstalling] = useState(false);
  const [installError, setInstallError] = useState<string | null>(null);

  const loadAddons = useCallback(async () => {
    await stremioService.ensureInitialized({ installDefaults: true });
    const summary = await stremioService.getAddonSummary();
    setAddons(summary);
  }, []);

  useFocusEffect(
    useCallback(() => {
      loadAddons();
    }, [loadAddons])
  );

  const installAddon = useCallback(async () => {
    if (!manifestUrl.trim()) {
      return;
    }
    const requestedUrl = manifestUrl.trim();
    try {
      setInstalling(true);
      setInstallError(null);
      await stremioService.installAddon(requestedUrl);
      setManifestUrl('');
      await loadAddons();
    } catch (error: any) {
      const errorMessage = error?.message || 'Could not install this addon.';
      setInstallError(errorMessage);
      appLogger.warn('[Stremio] Install addon screen failed', {
        manifestUrl: requestedUrl,
        error: errorMessage,
      });
      Alert.alert('Install Failed', `${errorMessage}\n\nOpen Settings > Logs for full details.`);
    } finally {
      setInstalling(false);
    }
  }, [loadAddons, manifestUrl]);

  return (
    <View style={styles.container}>
      <SettingsHeader title="Stremio Addons" onBack={() => nav.goBack()} />
      <ScrollView
        contentContainerStyle={[
          styles.content,
          { paddingTop: headerHeight + 12, paddingBottom: insets.bottom + 100 },
        ]}
      >
        <SettingsCard title="INSTALL">
          <View style={styles.installCard}>
            <Text style={styles.label}>Manifest URL</Text>
            <TextInput
              value={manifestUrl}
              onChangeText={setManifestUrl}
              autoCapitalize="none"
              autoCorrect={false}
              placeholder="https://example.com/manifest.json"
              placeholderTextColor="#6b7280"
              style={styles.input}
            />
            <Pressable
              disabled={installing}
              onPress={installAddon}
              style={[styles.installButton, installing && styles.installButtonDisabled]}
            >
              <Text style={styles.installButtonText}>
                {installing ? 'Installing…' : 'Install Addon'}
              </Text>
            </Pressable>
            {installError ? (
              <View style={styles.errorCard}>
                <Text style={styles.errorTitle}>Last install error</Text>
                <Text selectable style={styles.errorText}>
                  {installError}
                </Text>
                <Text style={styles.errorHint}>Full details are also written to Settings &gt; Logs.</Text>
              </View>
            ) : null}
          </View>
        </SettingsCard>

        <SettingsCard title="INSTALLED">
          {addons.length === 0 ? (
            <View style={styles.emptyState}>
              <Text style={styles.emptyStateTitle}>No addons installed</Text>
              <Text style={styles.emptyStateText}>
                Install a stream addon to surface sources here. OpenSubtitles is added automatically when Stremio playback is first enabled.
              </Text>
            </View>
          ) : (
            addons.map((addon, index) => (
              <View key={addon.installationId} style={[styles.addonCard, index === addons.length - 1 && styles.addonCardLast]}>
                <View style={styles.addonHeader}>
                  <View style={styles.addonTitleBlock}>
                    <Text style={styles.addonTitle}>{addon.name}</Text>
                    <Text style={styles.addonSubtitle}>
                      {addon.version} · {addon.id}
                    </Text>
                  </View>
                  <View style={styles.badges}>
                    {addon.streamCapable ? <Text style={styles.badge}>Streams</Text> : null}
                    {addon.subtitleCapable ? <Text style={styles.badge}>Subtitles</Text> : null}
                  </View>
                </View>

                {addon.description ? (
                  <Text style={styles.description}>{addon.description}</Text>
                ) : null}

                <View style={styles.actions}>
                  <Pressable
                    onPress={async () => {
                      await stremioService.moveAddonUp(addon.installationId);
                      await loadAddons();
                    }}
                    style={styles.iconButton}
                  >
                    <Ionicons name="arrow-up" size={16} color="#f3f4f6" />
                  </Pressable>
                  <Pressable
                    onPress={async () => {
                      await stremioService.moveAddonDown(addon.installationId);
                      await loadAddons();
                    }}
                    style={styles.iconButton}
                  >
                    <Ionicons name="arrow-down" size={16} color="#f3f4f6" />
                  </Pressable>
                  <Pressable
                    disabled={!addon.configureUrl}
                    onPress={() => {
                      if (addon.configureUrl) {
                        Linking.openURL(addon.configureUrl);
                      }
                    }}
                    style={[styles.actionButton, !addon.configureUrl && styles.actionButtonDisabled]}
                  >
                    <Text style={styles.actionButtonText}>Configure</Text>
                  </Pressable>
                  <Pressable
                    onPress={() => {
                      Alert.alert(
                        'Remove Addon',
                        `Remove ${addon.name} from this profile?`,
                        [
                          { text: 'Cancel', style: 'cancel' },
                          {
                            text: 'Remove',
                            style: 'destructive',
                            onPress: async () => {
                              await stremioService.removeAddon(addon.installationId);
                              await loadAddons();
                            },
                          },
                        ]
                      );
                    }}
                    style={[styles.actionButton, styles.removeButton]}
                  >
                    <Text style={styles.actionButtonText}>Remove</Text>
                  </Pressable>
                </View>
              </View>
            ))
          )}
        </SettingsCard>
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
  },
  installCard: {
    padding: 14,
    gap: 12,
  },
  label: {
    color: '#f9fafb',
    fontSize: 14,
    fontWeight: '700',
  },
  input: {
    minHeight: 46,
    borderRadius: 12,
    paddingHorizontal: 14,
    color: '#f9fafb',
    backgroundColor: 'rgba(255,255,255,0.05)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
  },
  installButton: {
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: 44,
    borderRadius: 12,
    backgroundColor: '#ffffff',
  },
  installButtonDisabled: {
    opacity: 0.6,
  },
  installButtonText: {
    color: '#111827',
    fontSize: 14,
    fontWeight: '800',
  },
  errorCard: {
    gap: 6,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: 'rgba(239,68,68,0.35)',
    backgroundColor: 'rgba(127,29,29,0.22)',
    padding: 12,
  },
  errorTitle: {
    color: '#fecaca',
    fontSize: 13,
    fontWeight: '800',
  },
  errorText: {
    color: '#fee2e2',
    fontSize: 12,
    lineHeight: 18,
  },
  errorHint: {
    color: '#fca5a5',
    fontSize: 11,
    lineHeight: 16,
  },
  emptyState: {
    padding: 14,
    gap: 6,
  },
  emptyStateTitle: {
    color: '#f9fafb',
    fontSize: 15,
    fontWeight: '800',
  },
  emptyStateText: {
    color: '#d1d5db',
    fontSize: 13,
    lineHeight: 19,
  },
  addonCard: {
    paddingHorizontal: 14,
    paddingTop: 14,
    paddingBottom: 16,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.08)',
    gap: 10,
  },
  addonCardLast: {
    borderBottomWidth: 0,
  },
  addonHeader: {
    gap: 10,
  },
  addonTitleBlock: {
    gap: 4,
  },
  addonTitle: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: '800',
  },
  addonSubtitle: {
    color: '#9ca3af',
    fontSize: 12,
    fontWeight: '600',
  },
  badges: {
    flexDirection: 'row',
    gap: 8,
  },
  badge: {
    color: '#111827',
    backgroundColor: '#ffffff',
    borderRadius: 999,
    overflow: 'hidden',
    paddingHorizontal: 10,
    paddingVertical: 6,
    fontSize: 11,
    fontWeight: '800',
  },
  description: {
    color: '#d1d5db',
    fontSize: 13,
    lineHeight: 18,
  },
  actions: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  iconButton: {
    width: 36,
    height: 36,
    borderRadius: 10,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(255,255,255,0.08)',
  },
  actionButton: {
    minHeight: 36,
    paddingHorizontal: 12,
    borderRadius: 10,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(255,255,255,0.08)',
  },
  actionButtonDisabled: {
    opacity: 0.45,
  },
  removeButton: {
    backgroundColor: 'rgba(239,68,68,0.16)',
  },
  actionButtonText: {
    color: '#f9fafb',
    fontSize: 13,
    fontWeight: '700',
  },
});
