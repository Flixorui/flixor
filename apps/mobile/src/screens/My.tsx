import React, { useEffect, useRef, useState } from 'react';
import { View, Text, Pressable, ActivityIndicator, Linking, ScrollView, Animated, StyleSheet, Alert, TextInput } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { Ionicons } from '@expo/vector-icons';
import { useNavigation, useIsFocused } from '@react-navigation/native';
import { useFlixor } from '../core/FlixorContext';
import {
  getTraktProfile,
  startTraktDeviceAuth,
  pollTraktToken,
  saveTraktTokens,
  signOutTrakt,
  getPlexUser,
  getAppVersion,
  getConnectedServerInfo,
  getPlexServers,
  selectPlexServer,
  getServerConnections,
  selectServerEndpoint,
  getAppSettings,
  setAppSettings,
  loadAppSettings,
  type PlexServerInfo,
  type PlexConnectionInfo,
} from '../core/SettingsData';
import { reinitializeFlixorCore } from '../core/index';
import { TopBarStore, useTopBarStore } from '../components/TopBarStore';

let WebBrowser: any = null;
try { WebBrowser = require('expo-web-browser'); } catch {}

interface MyProps {
  onLogout: () => Promise<void>;
}

export default function My({ onLogout }: MyProps) {
  const { isLoading: flixorLoading, isConnected } = useFlixor();
  const nav: any = useNavigation();
  const isFocused = useIsFocused();
  const [loading, setLoading] = useState(true);
  const [traktProfile, setTraktProfile] = useState<any | null>(null);
  const [plexUser, setPlexUser] = useState<any | null>(null);
  const [deviceCode, setDeviceCode] = useState<any | null>(null);
  const [servers, setServers] = useState<PlexServerInfo[]>([]);
  const [showServerEndpoints, setShowServerEndpoints] = useState<string | null>(null);
  const [endpoints, setEndpoints] = useState<PlexConnectionInfo[]>([]);

  // Settings state
  const [watchlistProvider, setWatchlistProvider] = useState<'trakt' | 'plex'>('trakt');
  const [tmdbApiKey, setTmdbApiKey] = useState<string>('');
  const [serverInfo, setServerInfo] = useState<{ name: string; url: string } | null>(null);

  const pollRef = useRef<any>(null);
  const y = useRef(new Animated.Value(0)).current;
  const barHeight = useTopBarStore(s => s.height || 60);

  // Set scrollY and configure TopBar when screen is focused
  React.useLayoutEffect(() => {
    if (isFocused) {
      TopBarStore.setScrollY(y);
    }
  }, [isFocused, y]);

  useEffect(() => {
    if (!isFocused) return;

    TopBarStore.setVisible(true);
    TopBarStore.setShowFilters(false);
    TopBarStore.setUsername('My Netflix');
    TopBarStore.setSelected('all');
    TopBarStore.setCompact(false);
    TopBarStore.setCustomFilters(undefined);
    TopBarStore.setHandlers({
      onNavigateLibrary: undefined,
      onClose: undefined,
      onSearch: () => nav.navigate('HomeTab', { screen: 'Search' })
    });
  }, [isFocused, nav]);

  useEffect(() => {
    if (flixorLoading || !isConnected) return;

    (async () => {
      await loadCurrentSettings();
      await refreshTraktProfile();
      await loadPlexUser();
      await loadServers();
      loadServerInfo();
      setLoading(false);
    })();
    return () => { if (pollRef.current) clearInterval(pollRef.current); };
  }, [flixorLoading, isConnected]);

  async function loadCurrentSettings() {
    const settings = await loadAppSettings();
    setWatchlistProvider(settings.watchlistProvider);
    setTmdbApiKey(settings.tmdbApiKey || '');
  }

  async function saveSettings() {
    try {
      await setAppSettings({ watchlistProvider });
      Alert.alert('Success', 'Settings saved');
    } catch (e: any) {
      Alert.alert('Error', e?.message || 'Failed to save settings');
    }
  }

  async function saveTmdbApiKey() {
    try {
      const keyToSave = tmdbApiKey.trim() || undefined;
      await setAppSettings({ tmdbApiKey: keyToSave });

      // Reinitialize FlixorCore with the new API key
      await reinitializeFlixorCore();

      Alert.alert(
        'Success',
        keyToSave
          ? 'TMDB API key saved. The app will use your custom key.'
          : 'TMDB API key cleared. The app will use the default key.'
      );
    } catch (e: any) {
      Alert.alert('Error', e?.message || 'Failed to save TMDB API key');
    }
  }

  async function refreshTraktProfile() {
    try {
      const p = await getTraktProfile();
      setTraktProfile(p);
    } catch (e: any) {
      setTraktProfile(null);
    }
  }

  async function loadPlexUser() {
    try {
      const user = await getPlexUser();
      setPlexUser(user);
    } catch (e) {
      console.log('[My] Failed to load Plex user:', e);
    }
  }

  function loadServerInfo() {
    const info = getConnectedServerInfo();
    setServerInfo(info);
  }

  async function loadServers() {
    try {
      const res = await getPlexServers();
      setServers(res || []);
    } catch (e) {
      console.error('[My] Failed to load servers:', e);
    }
  }

  async function handleSignOutTrakt() {
    try {
      await signOutTrakt();
      setTraktProfile(null);
      Alert.alert('Success', 'Signed out from Trakt');
    } catch (e: any) {
      Alert.alert('Error', e?.message || 'Failed to sign out');
    }
  }

  async function startTraktAuth() {
    try {
      const dc = await startTraktDeviceAuth();
      if (!dc) {
        Alert.alert('Error', 'Failed to start Trakt auth');
        return;
      }
      setDeviceCode(dc);

      try {
        if (WebBrowser && WebBrowser.openBrowserAsync) await WebBrowser.openBrowserAsync(dc.verification_url);
        else Linking.openURL(dc.verification_url);
      } catch {}

      if (pollRef.current) clearInterval(pollRef.current);
      pollRef.current = setInterval(async () => {
        try {
          const res = await pollTraktToken(dc.device_code);
          if (res && res.access_token) {
            await saveTraktTokens(res);
            clearInterval(pollRef.current);
            setDeviceCode(null);
            await refreshTraktProfile();
          }
        } catch (err: any) {
          const msg = String(err?.message || '');
          if (msg.includes('expired')) {
            clearInterval(pollRef.current);
            setDeviceCode(null);
            Alert.alert('Error', 'Device code expired. Please try again.');
          }
        }
      }, Math.max(5, Number(dc.interval || 5)) * 1000);

      setTimeout(() => {
        try { if (pollRef.current) clearInterval(pollRef.current); } catch {}
      }, Math.max(30, Number(dc.expires_in || 600)) * 1000);
    } catch (e: any) {
      Alert.alert('Error', e?.message || 'Failed to start Trakt auth');
    }
  }

  async function handleSelectServer(server: PlexServerInfo) {
    try {
      await selectPlexServer(server);
      Alert.alert('Success', `Connected to ${server.name}`);
      await loadServers();
      loadServerInfo();
    } catch (e: any) {
      Alert.alert('Error', e?.message || 'Failed to set server');
    }
  }

  async function loadEndpoints(serverId: string) {
    try {
      const res = await getServerConnections(serverId);
      setEndpoints(res || []);
      setShowServerEndpoints(serverId);
    } catch (e: any) {
      console.error('[My] Failed to load endpoints:', e);
      Alert.alert('Error', e?.message || 'Failed to load endpoints');
    }
  }

  async function handleSelectEndpoint(serverId: string, uri: string) {
    try {
      await selectServerEndpoint(serverId, uri);
      Alert.alert('Success', 'Endpoint updated');
      setShowServerEndpoints(null);
      await loadServers();
      loadServerInfo();
    } catch (e: any) {
      Alert.alert('Error', e?.message || 'Endpoint unreachable');
    }
  }

  async function handleLogout() {
    Alert.alert(
      'Logout',
      'Are you sure you want to logout? You will need to sign in again.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Logout',
          style: 'destructive',
          onPress: async () => {
            await onLogout();
          }
        }
      ]
    );
  }

  const Card = ({ children, title }: { children: any; title?: string }) => (
    <View style={styles.card}>
      {title && <Text style={styles.cardTitle}>{title}</Text>}
      {children}
    </View>
  );

  const Button = ({ onPress, title, variant = 'primary' }: { onPress: () => void; title: string; variant?: 'primary' | 'secondary' }) => (
    <Pressable
      onPress={onPress}
      style={[styles.button, variant === 'primary' ? styles.buttonPrimary : styles.buttonSecondary]}
    >
      <Text style={[styles.buttonText, variant === 'primary' ? styles.buttonTextPrimary : styles.buttonTextSecondary]}>
        {title}
      </Text>
    </Pressable>
  );

  if (flixorLoading || loading) {
    return (
      <View style={{ flex: 1, backgroundColor: '#0a0a0a', alignItems: 'center', justifyContent: 'center' }}>
        <ActivityIndicator color="#fff" />
      </View>
    );
  }

  return (
    <View style={{ flex: 1, backgroundColor: '#0a0a0a' }}>
      <LinearGradient
        colors={['#0a0a0a', '#0f0f10', '#0b0c0d']}
        start={{ x: 0.5, y: 0 }} end={{ x: 0.5, y: 1 }}
        style={StyleSheet.absoluteFillObject}
      />

      <Animated.ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingTop: barHeight, paddingBottom: 100, paddingHorizontal: 16 }}
        scrollEventThrottle={16}
        onScroll={Animated.event([
          { nativeEvent: { contentOffset: { y } } }
        ], { useNativeDriver: false })}
      >
        {/* Plex Account Section */}
        <Card title="Plex Account">
          {plexUser ? (
            <View>
              <View style={styles.row}>
                <Ionicons name="checkmark-circle" size={20} color="#4ade80" />
                <Text style={styles.connectedText}>Connected</Text>
              </View>
              <Text style={styles.username}>{plexUser?.username || plexUser?.title || 'Plex User'}</Text>
              {serverInfo && (
                <Text style={styles.hint}>Server: {serverInfo.name} ({serverInfo.url})</Text>
              )}
            </View>
          ) : (
            <View>
              <Text style={styles.description}>Not connected to Plex</Text>
            </View>
          )}
        </Card>

        {/* Trakt Account Section */}
        <Card title="Trakt Account">
          {traktProfile ? (
            <View>
              <View style={styles.row}>
                <Ionicons name="checkmark-circle" size={20} color="#4ade80" />
                <Text style={styles.connectedText}>Connected</Text>
              </View>
              <Text style={styles.username}>@{traktProfile?.username || traktProfile?.ids?.slug}</Text>
              <Text style={styles.hint}>Personalized rows are enabled on Home</Text>
              <Button onPress={handleSignOutTrakt} title="Sign Out" variant="secondary" />
            </View>
          ) : (
            <View>
              <Text style={styles.description}>
                Sign in to Trakt to enable Watchlist, Recently Watched, and Recommendations.
              </Text>
              {deviceCode ? (
                <View style={{ marginTop: 12 }}>
                  <Text style={styles.codeLabel}>1) Open: {deviceCode.verification_url}</Text>
                  <Text style={styles.codeLabel}>2) Enter code:</Text>
                  <Text style={styles.codeValue}>{deviceCode.user_code}</Text>
                  <Button onPress={() => Linking.openURL(deviceCode.verification_url)} title="Open Verification Page" variant="secondary" />
                  <Text style={styles.waiting}>Waiting for authorization…</Text>
                </View>
              ) : (
                <Button onPress={startTraktAuth} title="Connect Trakt" variant="primary" />
              )}
            </View>
          )}
        </Card>

        {/* App Settings Section */}
        <Card title="App Settings">
          <View style={styles.inputGroup}>
            <Text style={styles.inputLabel}>Watchlist Provider</Text>
            <View style={styles.pickerContainer}>
              <Pressable
                onPress={() => setWatchlistProvider('trakt')}
                style={[styles.pickerOption, watchlistProvider === 'trakt' && styles.pickerOptionActive]}
              >
                <Text style={[styles.pickerText, watchlistProvider === 'trakt' && styles.pickerTextActive]}>
                  Trakt
                </Text>
              </Pressable>
              <Pressable
                onPress={() => setWatchlistProvider('plex')}
                style={[styles.pickerOption, watchlistProvider === 'plex' && styles.pickerOptionActive]}
              >
                <Text style={[styles.pickerText, watchlistProvider === 'plex' && styles.pickerTextActive]}>
                  Plex
                </Text>
              </Pressable>
            </View>
          </View>

          <Button onPress={saveSettings} title="Save Settings" variant="primary" />
        </Card>

        {/* TMDB API Key Section */}
        <Card title="TMDB API Key">
          <Text style={styles.description}>
            Optionally provide your own TMDB API key. Leave empty to use the default key.
          </Text>
          <Text style={styles.hint}>
            Get a free API key at themoviedb.org
          </Text>
          <View style={styles.inputGroup}>
            <TextInput
              value={tmdbApiKey}
              onChangeText={setTmdbApiKey}
              placeholder="Enter your TMDB API key..."
              placeholderTextColor="#666"
              style={styles.textInput}
              autoCapitalize="none"
              autoCorrect={false}
              secureTextEntry={false}
            />
          </View>
          <Button onPress={saveTmdbApiKey} title={tmdbApiKey.trim() ? "Save API Key" : "Clear & Use Default"} variant="primary" />
        </Card>

        {/* Plex Servers Section */}
        <Card title="Plex Servers">
          <Text style={styles.description}>
            Select which Plex server to use for your library.
          </Text>
          <Button onPress={loadServers} title="Refresh Servers" variant="secondary" />

          {servers.length > 0 && (
            <View style={{ marginTop: 16 }}>
              {servers.map((server, idx) => (
                <View key={idx} style={styles.serverItem}>
                  <View style={{ flex: 1 }}>
                    <Text style={styles.serverName}>{server.name}</Text>
                    <Text style={styles.serverDetails}>
                      {server.protocol}://{server.host}:{server.port}
                    </Text>
                    {server.isActive && (
                      <Text style={styles.activeLabel}>• Active</Text>
                    )}
                  </View>
                  <View style={{ flexDirection: 'row', gap: 8 }}>
                    {!server.isActive && (
                      <Pressable onPress={() => handleSelectServer(server)} style={styles.smallButton}>
                        <Text style={styles.smallButtonText}>Use</Text>
                      </Pressable>
                    )}
                    <Pressable onPress={() => loadEndpoints(server.id)} style={styles.smallButton}>
                      <Text style={styles.smallButtonText}>Endpoints</Text>
                    </Pressable>
                  </View>
                </View>
              ))}
            </View>
          )}
        </Card>

        {/* About Section */}
        <Card title="About">
          <Text style={styles.description}>
            Version {getAppVersion()}
          </Text>
          <Text style={styles.hint}>
            Mobile Plex client with Netflix-style UI
          </Text>
        </Card>

        {/* Logout Section */}
        <Card title="Account">
          <Text style={styles.description}>
            Sign out of your account and return to the login screen.
          </Text>
          <Button onPress={handleLogout} title="Logout" variant="secondary" />
        </Card>
      </Animated.ScrollView>

      {/* Endpoints Modal */}
      {showServerEndpoints && (
        <View style={styles.modal}>
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Select Endpoint</Text>
              <Pressable onPress={() => setShowServerEndpoints(null)}>
                <Ionicons name="close" size={24} color="#fff" />
              </Pressable>
            </View>
            <ScrollView style={styles.modalScroll}>
              {endpoints.map((endpoint, idx) => (
                <View key={idx} style={styles.endpointItem}>
                  <View style={{ flex: 1 }}>
                    <Text style={styles.endpointUri}>{endpoint.uri}</Text>
                    {endpoint.isPreferred && (
                      <Text style={styles.preferredLabel}>preferred</Text>
                    )}
                    {endpoint.isCurrent && (
                      <Text style={styles.currentLabel}>current</Text>
                    )}
                  </View>
                  <Pressable
                    onPress={() => handleSelectEndpoint(showServerEndpoints, endpoint.uri)}
                    style={styles.smallButton}
                  >
                    <Text style={styles.smallButtonText}>Use</Text>
                  </Pressable>
                </View>
              ))}
            </ScrollView>
          </View>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: 'rgba(15,15,18,0.6)',
    borderRadius: 16,
    padding: 16,
    borderWidth: 1,
    borderColor: 'rgba(31,32,48,0.5)',
    marginBottom: 16,
  },
  cardTitle: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '700',
    marginBottom: 12,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginBottom: 8,
  },
  connectedText: {
    color: '#4ade80',
    fontWeight: '600',
  },
  username: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 8,
  },
  description: {
    color: '#bbb',
    marginBottom: 12,
    lineHeight: 20,
  },
  hint: {
    color: '#888',
    fontSize: 13,
    marginBottom: 12,
  },
  button: {
    paddingVertical: 12,
    borderRadius: 12,
    alignItems: 'center',
    marginTop: 8,
  },
  buttonPrimary: {
    backgroundColor: '#fff',
  },
  buttonSecondary: {
    backgroundColor: 'rgba(31,36,48,0.8)',
  },
  buttonText: {
    fontWeight: '700',
    fontSize: 15,
  },
  buttonTextPrimary: {
    color: '#000',
  },
  buttonTextSecondary: {
    color: '#fff',
  },
  codeLabel: {
    color: '#ddd',
    marginBottom: 6,
  },
  codeValue: {
    color: '#fff',
    fontSize: 20,
    fontWeight: '700',
    marginBottom: 12,
  },
  waiting: {
    color: '#888',
    marginTop: 8,
    textAlign: 'center',
  },
  serverItem: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(255,255,255,0.05)',
    borderRadius: 12,
    padding: 12,
    marginBottom: 8,
  },
  serverName: {
    color: '#fff',
    fontWeight: '600',
    marginBottom: 4,
  },
  serverDetails: {
    color: '#888',
    fontSize: 12,
  },
  activeLabel: {
    color: '#4ade80',
    fontSize: 12,
    marginTop: 4,
  },
  smallButton: {
    backgroundColor: 'rgba(255,255,255,0.1)',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 8,
  },
  smallButtonText: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '600',
  },
  modal: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0,0,0,0.8)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  modalContent: {
    backgroundColor: '#1a1a1a',
    borderRadius: 16,
    width: '90%',
    maxHeight: '70%',
    padding: 16,
  },
  modalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 16,
  },
  modalTitle: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '700',
  },
  modalScroll: {
    maxHeight: 400,
  },
  endpointItem: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(255,255,255,0.05)',
    borderRadius: 12,
    padding: 12,
    marginBottom: 8,
  },
  endpointUri: {
    color: '#fff',
    fontSize: 13,
    marginBottom: 4,
  },
  preferredLabel: {
    color: '#4ade80',
    fontSize: 11,
  },
  currentLabel: {
    color: '#60a5fa',
    fontSize: 11,
  },
  inputGroup: {
    marginBottom: 16,
  },
  inputLabel: {
    color: '#bbb',
    fontSize: 13,
    marginBottom: 6,
  },
  pickerContainer: {
    flexDirection: 'row',
    gap: 8,
  },
  pickerOption: {
    flex: 1,
    paddingVertical: 10,
    borderRadius: 8,
    alignItems: 'center',
    backgroundColor: 'rgba(255,255,255,0.05)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
  },
  pickerOptionActive: {
    backgroundColor: '#fff',
    borderColor: '#fff',
  },
  pickerText: {
    color: '#fff',
    fontWeight: '600',
  },
  pickerTextActive: {
    color: '#000',
  },
  textInput: {
    backgroundColor: 'rgba(255,255,255,0.08)',
    borderRadius: 10,
    paddingHorizontal: 14,
    paddingVertical: 12,
    color: '#fff',
    fontSize: 15,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.15)',
  },
});
