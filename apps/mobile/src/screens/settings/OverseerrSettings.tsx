import React, { useEffect, useMemo, useState } from 'react';
import {
  View,
  Text,
  ScrollView,
  TextInput,
  Pressable,
  StyleSheet,
  Switch,
  Linking,
  ActivityIndicator,
} from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import OverseerrIcon from '../../components/icons/OverseerrIcon';
import { useAppSettings } from '../../hooks/useAppSettings';
import {
  validateOverseerrConnection,
  authenticateWithPlex,
  validatePlexSession,
  signOutOverseerr,
  clearOverseerrCache,
} from '../../core/OverseerrService';

export default function OverseerrSettings() {
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const headerHeight = insets.top + 52;
  const { settings, updateSetting } = useAppSettings();

  const [url, setUrl] = useState(settings.overseerrUrl || '');
  const [apiKey, setApiKey] = useState(settings.overseerrApiKey || '');
  const [authMethod, setAuthMethod] = useState<'api_key' | 'plex'>(
    settings.overseerrAuthMethod || 'plex'
  );
  const [testing, setTesting] = useState(false);
  const [saved, setSaved] = useState(false);
  const [testResult, setTestResult] = useState<{
    success: boolean;
    message: string;
    username?: string;
  } | null>(null);

  // Sync local state when settings are loaded/changed
  useEffect(() => {
    if (settings.overseerrUrl && !url) {
      setUrl(settings.overseerrUrl);
    }
    if (settings.overseerrApiKey && !apiKey) {
      setApiKey(settings.overseerrApiKey);
    }
    if (settings.overseerrAuthMethod) {
      setAuthMethod(settings.overseerrAuthMethod);
    }
    // If settings are already configured, mark as saved
    const isConfiguredForMethod =
      settings.overseerrUrl &&
      ((settings.overseerrAuthMethod === 'api_key' && settings.overseerrApiKey) ||
        (settings.overseerrAuthMethod === 'plex' && settings.overseerrSessionCookie));
    if (isConfiguredForMethod) {
      setSaved(true);
    }
  }, [
    settings.overseerrUrl,
    settings.overseerrApiKey,
    settings.overseerrAuthMethod,
    settings.overseerrSessionCookie,
  ]);

  const hasUrl = useMemo(() => url.trim().length > 0, [url]);
  const hasKey = useMemo(() => apiKey.trim().length > 0, [apiKey]);

  // Check if current values match saved settings
  const hasChanges = useMemo(() => {
    if (authMethod === 'api_key') {
      return (
        url.trim() !== (settings.overseerrUrl || '') ||
        apiKey.trim() !== (settings.overseerrApiKey || '')
      );
    }
    return url.trim() !== (settings.overseerrUrl || '');
  }, [url, apiKey, authMethod, settings.overseerrUrl, settings.overseerrApiKey]);

  // Different conditions for each auth method
  const canTestApiKey = hasUrl && hasKey && settings.overseerrEnabled && (!saved || hasChanges);
  const canTestPlex = hasUrl && settings.overseerrEnabled;

  const isConfigured =
    settings.overseerrEnabled &&
    settings.overseerrUrl &&
    ((authMethod === 'api_key' && settings.overseerrApiKey) ||
      (authMethod === 'plex' && settings.overseerrSessionCookie));

  // Check if signed in with Plex
  const isPlexSignedIn = authMethod === 'plex' && settings.overseerrSessionCookie;
  const plexUsername = settings.overseerrPlexUsername;

  const toggleEnabled = async (value: boolean) => {
    await updateSetting('overseerrEnabled', value);
    if (!value) {
      clearOverseerrCache();
      setTestResult(null);
      setSaved(false);
    } else {
      // Reset saved state when re-enabling to allow re-testing
      setSaved(false);
    }
  };

  const handleAuthMethodChange = async (method: 'api_key' | 'plex') => {
    setAuthMethod(method);
    await updateSetting('overseerrAuthMethod', method);
    setTestResult(null);
    setSaved(false);
  };

  const testApiKeyConnection = async () => {
    if (!canTestApiKey) return;

    setTesting(true);
    setTestResult(null);
    setSaved(false);

    try {
      const result = await validateOverseerrConnection(url.trim(), apiKey.trim());

      if (result.valid) {
        // Save settings on successful test
        await updateSetting('overseerrUrl', url.trim());
        await updateSetting('overseerrApiKey', apiKey.trim());
        await updateSetting('overseerrAuthMethod', 'api_key');
        clearOverseerrCache();
        setSaved(true);

        setTestResult({
          success: true,
          message: 'Connected successfully!',
          username: result.username,
        });
      } else {
        setTestResult({
          success: false,
          message: result.error || 'Connection failed',
        });
      }
    } catch (error) {
      setTestResult({
        success: false,
        message: 'Connection failed',
      });
    } finally {
      setTesting(false);
    }
  };

  const signInWithPlex = async () => {
    if (!canTestPlex) return;

    setTesting(true);
    setTestResult(null);
    setSaved(false);

    try {
      // Save URL first
      await updateSetting('overseerrUrl', url.trim());
      await updateSetting('overseerrAuthMethod', 'plex');

      const result = await authenticateWithPlex(url.trim());

      if (result.valid) {
        clearOverseerrCache();
        setSaved(true);

        setTestResult({
          success: true,
          message: 'Signed in successfully!',
          username: result.username,
        });
      } else {
        setTestResult({
          success: false,
          message: result.error || 'Sign in failed',
        });
      }
    } catch (error) {
      setTestResult({
        success: false,
        message: 'Sign in failed',
      });
    } finally {
      setTesting(false);
    }
  };

  const handleSignOut = async () => {
    await signOutOverseerr();
    setSaved(false);
    setTestResult(null);
  };

  const getStatusInfo = () => {
    if (!settings.overseerrEnabled) {
      return {
        icon: 'alert-circle' as const,
        color: '#6b7280',
        title: 'Overseerr Disabled',
        desc: 'Enable Overseerr to request movies and shows.',
      };
    }
    if (!hasUrl) {
      return {
        icon: 'alert-circle' as const,
        color: '#f59e0b',
        title: 'Configuration Required',
        desc: 'Enter your Overseerr server URL.',
      };
    }
    if (authMethod === 'api_key' && !hasKey) {
      return {
        icon: 'alert-circle' as const,
        color: '#f59e0b',
        title: 'API Key Required',
        desc: 'Enter your Overseerr API key.',
      };
    }
    if (testResult?.success) {
      return {
        icon: 'checkmark-circle' as const,
        color: '#22c55e',
        title: `Connected as ${testResult.username || 'user'}`,
        desc: 'You can now request movies and shows.',
      };
    }
    if (testResult && !testResult.success) {
      return {
        icon: 'close-circle' as const,
        color: '#ef4444',
        title: 'Connection Failed',
        desc: testResult.message,
      };
    }
    if (isConfigured) {
      const displayName = authMethod === 'plex' ? plexUsername : 'API Key';
      return {
        icon: 'checkmark-circle' as const,
        color: '#22c55e',
        title: `Connected${displayName ? ` as ${displayName}` : ''}`,
        desc: 'Request movies and shows from Details screen.',
      };
    }
    if (authMethod === 'plex') {
      return {
        icon: 'alert-circle' as const,
        color: '#f59e0b',
        title: 'Sign In Required',
        desc: 'Sign in with your Plex account.',
      };
    }
    return {
      icon: 'alert-circle' as const,
      color: '#f59e0b',
      title: 'Test Connection',
      desc: 'Test your connection to save settings.',
    };
  };

  const statusInfo = getStatusInfo();

  return (
    <View style={styles.container}>
      <SettingsHeader title="Overseerr" onBack={() => nav.goBack()} />
      <ScrollView
        contentContainerStyle={[
          styles.content,
          { paddingTop: headerHeight + 12, paddingBottom: insets.bottom + 100 },
        ]}
      >
        {/* Header with Overseerr logo */}
        <View style={styles.logoHeader}>
          <View style={styles.logoContainer}>
            <OverseerrIcon size={32} color="#6366f1" />
          </View>
          <Text style={styles.logoTitle}>Overseerr</Text>
          <Text style={styles.logoSubtitle}>Media request management</Text>
        </View>

        {/* Status Card */}
        <View
          style={[
            styles.statusCard,
            { borderColor: `${statusInfo.color}33`, backgroundColor: `${statusInfo.color}11` },
          ]}
        >
          <Ionicons name={statusInfo.icon} size={24} color={statusInfo.color} />
          <View style={styles.statusTextWrap}>
            <Text style={styles.statusTitle}>{statusInfo.title}</Text>
            <Text style={styles.statusDesc}>{statusInfo.desc}</Text>
          </View>
        </View>

        {/* Enable Toggle */}
        <SettingsCard title="ENABLE OVERSEERR">
          <SettingItem
            title="Enable Overseerr Integration"
            description="Request movies and TV shows"
            icon="cloud-download-outline"
            renderRight={() => (
              <Switch value={settings.overseerrEnabled} onValueChange={toggleEnabled} />
            )}
            isLast={true}
          />
        </SettingsCard>

        {/* Server URL */}
        <SettingsCard title="SERVER URL">
          <View style={[styles.inputWrap, !settings.overseerrEnabled && styles.disabled]}>
            <TextInput
              value={url}
              onChangeText={(text) => {
                setUrl(text);
                setTestResult(null);
                setSaved(false);
              }}
              placeholder="https://overseerr.example.com"
              placeholderTextColor="#6b7280"
              style={[styles.input, !settings.overseerrEnabled && styles.inputDisabled]}
              autoCapitalize="none"
              autoCorrect={false}
              keyboardType="url"
              editable={settings.overseerrEnabled}
            />
          </View>
          <Text style={styles.note}>
            Enter your Overseerr server URL (including https://)
          </Text>
        </SettingsCard>

        {/* Authentication Method */}
        <SettingsCard title="AUTHENTICATION">
          <View style={[styles.authMethodWrap, !settings.overseerrEnabled && styles.disabled]}>
            <Pressable
              style={[
                styles.authMethodOption,
                authMethod === 'plex' && styles.authMethodSelected,
              ]}
              onPress={() => handleAuthMethodChange('plex')}
              disabled={!settings.overseerrEnabled}
            >
              <Ionicons
                name="logo-apple"
                size={20}
                color={authMethod === 'plex' ? '#fff' : '#9ca3af'}
              />
              <Text
                style={[
                  styles.authMethodText,
                  authMethod === 'plex' && styles.authMethodTextSelected,
                ]}
              >
                Sign in with Plex
              </Text>
              {authMethod === 'plex' && (
                <Ionicons name="checkmark-circle" size={18} color="#22c55e" />
              )}
            </Pressable>

            <Pressable
              style={[
                styles.authMethodOption,
                authMethod === 'api_key' && styles.authMethodSelected,
              ]}
              onPress={() => handleAuthMethodChange('api_key')}
              disabled={!settings.overseerrEnabled}
            >
              <Ionicons
                name="key-outline"
                size={20}
                color={authMethod === 'api_key' ? '#fff' : '#9ca3af'}
              />
              <Text
                style={[
                  styles.authMethodText,
                  authMethod === 'api_key' && styles.authMethodTextSelected,
                ]}
              >
                API Key
              </Text>
              {authMethod === 'api_key' && (
                <Ionicons name="checkmark-circle" size={18} color="#22c55e" />
              )}
            </Pressable>
          </View>
          <Text style={styles.note}>
            {authMethod === 'plex'
              ? 'Use your existing Plex account to sign in (recommended)'
              : 'Use an API key for authentication'}
          </Text>
        </SettingsCard>

        {/* Plex Auth Section */}
        {authMethod === 'plex' && (
          <SettingsCard title="PLEX SIGN IN">
            <View style={[styles.inputWrap, !settings.overseerrEnabled && styles.disabled]}>
              {/* Sign in / Signed in button */}
              <Pressable
                style={[
                  styles.plexSignInButton,
                  isPlexSignedIn && styles.plexSignedInButton,
                  (!canTestPlex || testing) && !isPlexSignedIn && styles.buttonDisabled,
                ]}
                onPress={isPlexSignedIn ? undefined : signInWithPlex}
                disabled={isPlexSignedIn || !canTestPlex || testing}
              >
                {testing ? (
                  <ActivityIndicator size="small" color="#fff" />
                ) : isPlexSignedIn ? (
                  <>
                    <Ionicons name="checkmark-circle" size={20} color="#fff" />
                    <Text style={styles.plexSignInButtonText}>
                      Signed in as {plexUsername || 'Plex User'}
                    </Text>
                  </>
                ) : (
                  <>
                    <Ionicons name="log-in-outline" size={20} color="#fff" />
                    <Text style={styles.plexSignInButtonText}>Sign in with Plex</Text>
                  </>
                )}
              </Pressable>

              {/* Sign out button - only shown when signed in */}
              {isPlexSignedIn && (
                <Pressable style={styles.signOutButton} onPress={handleSignOut}>
                  <Text style={styles.signOutButtonText}>Sign Out</Text>
                </Pressable>
              )}
            </View>
            <Text style={styles.note}>
              {isPlexSignedIn
                ? 'You can now request movies and shows from the Details screen.'
                : 'Uses your existing Plex account to authenticate with Overseerr. Your Plex account must have access to the Overseerr server.'}
            </Text>
          </SettingsCard>
        )}

        {/* API Key Section */}
        {authMethod === 'api_key' && (
          <>
            <SettingsCard title="API KEY">
              <View style={[styles.inputWrap, !settings.overseerrEnabled && styles.disabled]}>
                <TextInput
                  value={apiKey}
                  onChangeText={(text) => {
                    setApiKey(text);
                    setTestResult(null);
                    setSaved(false);
                  }}
                  placeholder="Enter your Overseerr API key"
                  placeholderTextColor="#6b7280"
                  style={[styles.input, !settings.overseerrEnabled && styles.inputDisabled]}
                  autoCapitalize="none"
                  autoCorrect={false}
                  secureTextEntry
                  editable={settings.overseerrEnabled}
                />
                <Pressable
                  style={[
                    styles.testButton,
                    (!canTestApiKey || (saved && !hasChanges)) && styles.buttonDisabled,
                    saved && !hasChanges && styles.savedButton,
                  ]}
                  onPress={testApiKeyConnection}
                  disabled={!canTestApiKey || testing || (saved && !hasChanges)}
                >
                  {testing ? (
                    <ActivityIndicator size="small" color="#0b0b0d" />
                  ) : saved && !hasChanges ? (
                    <Text style={[styles.testButtonText, styles.savedButtonText]}>Saved</Text>
                  ) : (
                    <Text style={[styles.testButtonText, !canTestApiKey && styles.buttonTextDisabled]}>
                      Test & Save
                    </Text>
                  )}
                </Pressable>
              </View>
              <Text style={styles.note}>
                Find your API key in Overseerr Settings {'>'} General {'>'} API Key
              </Text>
            </SettingsCard>

            {/* Instructions for API Key */}
            <SettingsCard title="HOW TO GET YOUR API KEY">
              <View style={styles.stepsWrap}>
                <View style={styles.step}>
                  <Text style={styles.stepNumber}>1.</Text>
                  <Text style={styles.stepText}>
                    Open your <Text style={styles.highlight}>Overseerr</Text> web interface
                  </Text>
                </View>
                <View style={styles.step}>
                  <Text style={styles.stepNumber}>2.</Text>
                  <Text style={styles.stepText}>
                    Go to <Text style={styles.highlight}>Settings</Text> {'>'}{' '}
                    <Text style={styles.highlight}>General</Text>
                  </Text>
                </View>
                <View style={styles.step}>
                  <Text style={styles.stepNumber}>3.</Text>
                  <Text style={styles.stepText}>
                    Copy the <Text style={styles.highlight}>API Key</Text> and paste above
                  </Text>
                </View>
                <Pressable
                  style={styles.linkButton}
                  onPress={() => Linking.openURL('https://docs.overseerr.dev/')}
                >
                  <Text style={styles.linkButtonText}>Overseerr Documentation</Text>
                  <Ionicons name="open-outline" size={16} color="#3b82f6" />
                </Pressable>
              </View>
            </SettingsCard>
          </>
        )}

        {/* About */}
        <SettingsCard title="ABOUT OVERSEERR">
          <View style={styles.aboutWrap}>
            <Text style={styles.aboutText}>
              Overseerr is a request management and media discovery tool for your Plex ecosystem.
              When enabled, you can request movies and TV shows directly from Flixor when they're
              not available in your library.
            </Text>
            <View style={styles.featureList}>
              <View style={styles.featureItem}>
                <Ionicons name="checkmark" size={16} color="#22c55e" />
                <Text style={styles.featureText}>Request movies and TV shows</Text>
              </View>
              <View style={styles.featureItem}>
                <Ionicons name="checkmark" size={16} color="#22c55e" />
                <Text style={styles.featureText}>See request status</Text>
              </View>
              <View style={styles.featureItem}>
                <Ionicons name="checkmark" size={16} color="#22c55e" />
                <Text style={styles.featureText}>Works with Radarr/Sonarr</Text>
              </View>
            </View>
          </View>
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
  logoHeader: {
    alignItems: 'center',
    marginBottom: 20,
    paddingVertical: 16,
  },
  logoContainer: {
    width: 64,
    height: 64,
    borderRadius: 16,
    backgroundColor: 'rgba(99, 102, 241, 0.1)',
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
  statusCard: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 14,
    borderRadius: 12,
    marginBottom: 16,
    gap: 12,
    borderWidth: 1,
  },
  statusTextWrap: {
    flex: 1,
  },
  statusTitle: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  statusDesc: {
    color: '#9ca3af',
    fontSize: 13,
    marginTop: 2,
  },
  inputWrap: {
    padding: 14,
    gap: 10,
  },
  input: {
    backgroundColor: 'rgba(255,255,255,0.06)',
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 10,
    color: '#fff',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    fontSize: 14,
  },
  inputDisabled: {
    backgroundColor: 'rgba(255,255,255,0.02)',
    color: '#6b7280',
  },
  // Auth method picker styles
  authMethodWrap: {
    padding: 14,
    gap: 10,
  },
  authMethodOption: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    padding: 14,
    borderRadius: 10,
    backgroundColor: 'rgba(255,255,255,0.04)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.06)',
  },
  authMethodSelected: {
    backgroundColor: 'rgba(99, 102, 241, 0.15)',
    borderColor: 'rgba(99, 102, 241, 0.4)',
  },
  authMethodText: {
    flex: 1,
    color: '#9ca3af',
    fontSize: 15,
    fontWeight: '500',
  },
  authMethodTextSelected: {
    color: '#fff',
  },
  // Plex sign in styles
  plexSignInButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 10,
    backgroundColor: '#e5a00d',
    borderRadius: 10,
    paddingVertical: 14,
    minHeight: 48,
  },
  plexSignedInButton: {
    backgroundColor: '#22c55e',
  },
  plexSignInButtonText: {
    color: '#fff',
    fontWeight: '700',
    fontSize: 15,
  },
  signOutButton: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 12,
    borderRadius: 10,
    backgroundColor: 'rgba(239, 68, 68, 0.15)',
    borderWidth: 1,
    borderColor: 'rgba(239, 68, 68, 0.3)',
  },
  signOutButtonText: {
    color: '#ef4444',
    fontWeight: '600',
    fontSize: 14,
  },
  testButton: {
    backgroundColor: '#fff',
    borderRadius: 10,
    paddingVertical: 12,
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: 44,
  },
  testButtonText: {
    color: '#0b0b0d',
    fontWeight: '700',
    fontSize: 14,
  },
  buttonDisabled: {
    backgroundColor: 'rgba(255,255,255,0.1)',
  },
  savedButton: {
    backgroundColor: 'rgba(34, 197, 94, 0.2)',
  },
  savedButtonText: {
    color: '#22c55e',
  },
  buttonTextDisabled: {
    color: '#6b7280',
  },
  note: {
    color: '#9ca3af',
    fontSize: 12,
    paddingHorizontal: 14,
    paddingBottom: 12,
  },
  disabled: {
    opacity: 0.5,
  },
  stepsWrap: {
    padding: 14,
    gap: 10,
  },
  step: {
    flexDirection: 'row',
    gap: 8,
  },
  stepNumber: {
    color: '#6b7280',
    fontSize: 14,
    width: 20,
  },
  stepText: {
    flex: 1,
    color: '#e5e7eb',
    fontSize: 14,
    lineHeight: 20,
  },
  highlight: {
    color: '#fff',
    fontWeight: '600',
  },
  linkButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    marginTop: 8,
    paddingVertical: 10,
    paddingHorizontal: 14,
    backgroundColor: 'rgba(59, 130, 246, 0.1)',
    borderRadius: 10,
    alignSelf: 'flex-start',
  },
  linkButtonText: {
    color: '#3b82f6',
    fontWeight: '600',
  },
  aboutWrap: {
    padding: 14,
    gap: 12,
  },
  aboutText: {
    color: '#9ca3af',
    fontSize: 13,
    lineHeight: 20,
  },
  featureList: {
    gap: 8,
    marginTop: 4,
  },
  featureItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  featureText: {
    color: '#e5e7eb',
    fontSize: 13,
  },
});
