import React, { useEffect, useState } from 'react';
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  Pressable,
  ActivityIndicator,
  Alert,
  TextInput,
} from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import PlexIcon from '../../components/icons/PlexIcon';
import TraktIcon from '../../components/icons/TraktIcon';
import { useFlixor } from '../../core/FlixorContext';
import {
  getPlexUser,
  getConnectedServerInfo,
  getServerConnections,
  selectServerEndpoint,
  getAppSettings,
  setAppSettings,
  type PlexConnectionInfo,
} from '../../core/SettingsData';
import type { PlexServer } from '@flixor/core';

interface PlexSettingsProps {
  onLogout?: () => Promise<void>;
}

export default function PlexSettings({ onLogout }: PlexSettingsProps) {
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const headerHeight = insets.top + 52;
  const { flixor, isConnected } = useFlixor();

  const [plexUser, setPlexUser] = useState<any | null>(null);
  const [serverInfo, setServerInfo] = useState<{ name: string; url: string } | null>(null);
  const [servers, setServers] = useState<PlexServer[]>([]);
  const [loading, setLoading] = useState(true);
  const [connecting, setConnecting] = useState<string | null>(null);

  // Expanded server endpoints state
  const [expandedServerId, setExpandedServerId] = useState<string | null>(null);
  const [endpoints, setEndpoints] = useState<PlexConnectionInfo[]>([]);
  const [loadingEndpoints, setLoadingEndpoints] = useState(false);
  const [selectingEndpoint, setSelectingEndpoint] = useState<string | null>(null);
  const [testingEndpoint, setTestingEndpoint] = useState<string | null>(null);
  const [testResults, setTestResults] = useState<Record<string, 'success' | 'failed' | 'testing'>>({});

  // Custom endpoint state
  const [customEndpoint, setCustomEndpoint] = useState('');
  const [testingCustom, setTestingCustom] = useState(false);

  // Watchlist provider state
  const [isTraktConnected, setIsTraktConnected] = useState(false);
  const [watchlistProvider, setWatchlistProvider] = useState<'trakt' | 'plex'>('trakt');

  useEffect(() => {
    loadData();
  }, [flixor, isConnected]);

  const loadData = async () => {
    setLoading(true);
    try {
      setPlexUser(await getPlexUser());
      setServerInfo(getConnectedServerInfo());

      if (flixor) {
        const serverList = await flixor.getServers();
        setServers(serverList);

        const traktAuth = flixor.isTraktAuthenticated;
        setIsTraktConnected(traktAuth);

        const settings = getAppSettings();
        setWatchlistProvider(settings.watchlistProvider || 'trakt');
      }
    } catch (e) {
      console.log('[PlexSettings] Error loading data:', e);
    } finally {
      setLoading(false);
    }
  };

  const connectToServer = async (server: PlexServer) => {
    if (!flixor) return;

    try {
      setConnecting(server.id);
      await flixor.connectToServer(server);
      setServerInfo({ name: server.name, url: server.connections[0]?.uri || '' });
      Alert.alert('Connected', `Now connected to ${server.name}`);
    } catch (e: any) {
      Alert.alert(
        'Connection Failed',
        `Could not connect to ${server.name}. Make sure the server is online.`
      );
    } finally {
      setConnecting(null);
    }
  };

  const toggleServerEndpoints = async (serverId: string) => {
    if (expandedServerId === serverId) {
      // Collapse
      setExpandedServerId(null);
      setEndpoints([]);
      setTestResults({});
      setCustomEndpoint('');
      return;
    }

    // Expand and load endpoints
    setExpandedServerId(serverId);
    setLoadingEndpoints(true);
    setTestResults({});
    setCustomEndpoint('');

    try {
      const connections = await getServerConnections(serverId);
      setEndpoints(connections);
    } catch (e) {
      console.log('[PlexSettings] Error loading endpoints:', e);
      setEndpoints([]);
    } finally {
      setLoadingEndpoints(false);
    }
  };

  const testEndpoint = async (uri: string) => {
    if (!flixor || !expandedServerId) return;

    setTestingEndpoint(uri);
    setTestResults(prev => ({ ...prev, [uri]: 'testing' }));

    try {
      const server = servers.find(s => s.id === expandedServerId);
      if (!server) throw new Error('Server not found');

      const connection = server.connections.find(c => c.uri === uri) || { uri, protocol: 'https', local: false, relay: false };
      const isValid = await flixor.testConnection(connection, server.accessToken);

      setTestResults(prev => ({ ...prev, [uri]: isValid ? 'success' : 'failed' }));
    } catch (e) {
      console.log('[PlexSettings] Test endpoint error:', e);
      setTestResults(prev => ({ ...prev, [uri]: 'failed' }));
    } finally {
      setTestingEndpoint(null);
    }
  };

  const testAllEndpoints = async () => {
    for (const endpoint of endpoints) {
      await testEndpoint(endpoint.uri);
    }
  };

  const testCustomEndpoint = async () => {
    if (!customEndpoint.trim() || !flixor || !expandedServerId) return;

    setTestingCustom(true);
    const uri = customEndpoint.trim();

    try {
      const server = servers.find(s => s.id === expandedServerId);
      if (!server) throw new Error('Server not found');

      const connection = { uri, protocol: uri.startsWith('https') ? 'https' : 'http', local: false, relay: false };
      const isValid = await flixor.testConnection(connection, server.accessToken);

      if (isValid) {
        Alert.alert('Success', 'Custom endpoint is reachable!', [
          { text: 'Cancel', style: 'cancel' },
          { text: 'Use This Endpoint', onPress: () => selectCustomEndpoint(uri) },
        ]);
      } else {
        Alert.alert('Failed', 'Could not reach this endpoint. Check the URL and try again.');
      }
    } catch (e) {
      Alert.alert('Error', 'Failed to test endpoint.');
    } finally {
      setTestingCustom(false);
    }
  };

  const selectCustomEndpoint = async (uri: string) => {
    if (!expandedServerId || !flixor) return;

    try {
      setSelectingEndpoint(uri);

      const server = servers.find(s => s.id === expandedServerId);
      if (!server) throw new Error('Server not found');

      await flixor.connectToServerWithUri(server, uri);
      setServerInfo(getConnectedServerInfo());
      Alert.alert('Endpoint Changed', 'Successfully switched to the custom endpoint.');
      loadData();
    } catch (e: any) {
      Alert.alert('Connection Failed', e.message || 'Could not connect to this endpoint.');
    } finally {
      setSelectingEndpoint(null);
    }
  };

  const selectEndpoint = async (uri: string) => {
    if (!expandedServerId) return;

    try {
      setSelectingEndpoint(uri);
      await selectServerEndpoint(expandedServerId, uri);
      setServerInfo(getConnectedServerInfo());
      Alert.alert('Endpoint Changed', 'Successfully switched to the selected endpoint.');
      loadData();
    } catch (e: any) {
      Alert.alert('Connection Failed', e.message || 'Could not connect to this endpoint.');
    } finally {
      setSelectingEndpoint(null);
    }
  };

  const handleWatchlistProviderChange = async (provider: 'trakt' | 'plex') => {
    setWatchlistProvider(provider);
    await setAppSettings({ watchlistProvider: provider });
  };

  const handleLogout = () => {
    Alert.alert(
      'Sign Out',
      'Are you sure you want to sign out of Plex? You will need to sign in again to access your media.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Sign Out',
          style: 'destructive',
          onPress: async () => {
            if (onLogout) {
              await onLogout();
            }
          },
        },
      ]
    );
  };

  const currentServerId = serverInfo ? servers.find(s => s.name === serverInfo.name)?.id : null;

  const getEndpointType = (conn: PlexConnectionInfo): 'local' | 'remote' | 'relay' => {
    if (conn.local && !conn.relay) return 'local';
    if (conn.relay) return 'relay';
    return 'remote';
  };

  const getEndpointLabel = (conn: PlexConnectionInfo): string => {
    const labels: string[] = [];
    if (conn.isPreferred) labels.push('preferred');
    if (conn.isCurrent) labels.push('current');
    return labels.length > 0 ? labels.join(' · ') : '';
  };

  const getEndpointColor = (conn: PlexConnectionInfo): string => {
    const type = getEndpointType(conn);
    switch (type) {
      case 'local': return '#22c55e';
      case 'remote': return '#3b82f6';
      case 'relay': return '#f59e0b';
      default: return '#9ca3af';
    }
  };

  const getTestResultIcon = (uri: string) => {
    const result = testResults[uri];
    if (!result) return null;
    if (result === 'testing') return <ActivityIndicator size="small" color="#e5a00d" />;
    if (result === 'success') return <Ionicons name="checkmark-circle" size={16} color="#22c55e" />;
    if (result === 'failed') return <Ionicons name="close-circle" size={16} color="#ef4444" />;
    return null;
  };

  const renderServerEndpoints = (serverId: string) => {
    if (expandedServerId !== serverId) return null;

    return (
      <View style={styles.endpointsContainer}>
        {loadingEndpoints ? (
          <View style={styles.endpointsLoading}>
            <ActivityIndicator color="#e5a00d" size="small" />
            <Text style={styles.endpointsLoadingText}>Loading endpoints...</Text>
          </View>
        ) : (
          <>
            {/* Test All Button */}
            {endpoints.length > 0 && (
              <Pressable style={styles.testAllButton} onPress={testAllEndpoints}>
                <Ionicons name="speedometer-outline" size={14} color="#3b82f6" />
                <Text style={styles.testAllButtonText}>Test All</Text>
              </Pressable>
            )}

            {/* Endpoints List */}
            {endpoints.length === 0 ? (
              <Text style={styles.noEndpointsText}>No endpoints available</Text>
            ) : (
              endpoints.map((endpoint) => (
                <View key={endpoint.uri} style={styles.endpointRow}>
                  <View style={styles.endpointInfo}>
                    <View style={styles.endpointTypeRow}>
                      <View style={[styles.typeBadge, { backgroundColor: getEndpointColor(endpoint) + '20' }]}>
                        <Text style={[styles.typeBadgeText, { color: getEndpointColor(endpoint) }]}>
                          {getEndpointType(endpoint)}
                        </Text>
                      </View>
                      {getTestResultIcon(endpoint.uri)}
                      {endpoint.isCurrent && (
                        <View style={styles.currentBadge}>
                          <Ionicons name="checkmark" size={10} color="#e5a00d" />
                        </View>
                      )}
                    </View>
                    <Text style={styles.endpointUri} numberOfLines={1}>{endpoint.uri}</Text>
                    {getEndpointLabel(endpoint) ? (
                      <Text style={styles.endpointMeta}>{getEndpointLabel(endpoint)}</Text>
                    ) : null}
                  </View>
                  <View style={styles.endpointActions}>
                    <Pressable
                      style={styles.smallButton}
                      onPress={() => testEndpoint(endpoint.uri)}
                      disabled={testingEndpoint !== null}
                    >
                      {testingEndpoint === endpoint.uri ? (
                        <ActivityIndicator size="small" color="#3b82f6" />
                      ) : (
                        <Text style={styles.smallButtonText}>Test</Text>
                      )}
                    </Pressable>
                    {!endpoint.isCurrent && (
                      <Pressable
                        style={[styles.smallButton, styles.smallButtonPrimary]}
                        onPress={() => selectEndpoint(endpoint.uri)}
                        disabled={selectingEndpoint !== null}
                      >
                        {selectingEndpoint === endpoint.uri ? (
                          <ActivityIndicator size="small" color="#000" />
                        ) : (
                          <Text style={[styles.smallButtonText, styles.smallButtonTextPrimary]}>Use</Text>
                        )}
                      </Pressable>
                    )}
                  </View>
                </View>
              ))
            )}

            {/* Custom Endpoint */}
            <View style={styles.customEndpointSection}>
              <Text style={styles.customLabel}>Custom Endpoint</Text>
              <View style={styles.customInputRow}>
                <TextInput
                  style={styles.customInput}
                  placeholder="https://plex.example.com:32400"
                  placeholderTextColor="#6b7280"
                  value={customEndpoint}
                  onChangeText={setCustomEndpoint}
                  autoCapitalize="none"
                  autoCorrect={false}
                  keyboardType="url"
                />
              </View>
              <View style={styles.customActions}>
                <Pressable
                  style={[styles.smallButton, !customEndpoint.trim() && styles.smallButtonDisabled]}
                  onPress={testCustomEndpoint}
                  disabled={testingCustom || !customEndpoint.trim()}
                >
                  {testingCustom ? (
                    <ActivityIndicator size="small" color="#3b82f6" />
                  ) : (
                    <Text style={styles.smallButtonText}>Test</Text>
                  )}
                </Pressable>
                <Pressable
                  style={[styles.smallButton, styles.smallButtonPrimary, !customEndpoint.trim() && styles.smallButtonDisabled]}
                  onPress={() => selectCustomEndpoint(customEndpoint.trim())}
                  disabled={selectingEndpoint !== null || !customEndpoint.trim()}
                >
                  <Text style={[styles.smallButtonText, styles.smallButtonTextPrimary]}>Use</Text>
                </Pressable>
              </View>
            </View>
          </>
        )}
      </View>
    );
  };

  return (
    <View style={styles.container}>
      <SettingsHeader title="Plex" onBack={() => nav.goBack()} />
      <ScrollView
        contentContainerStyle={[styles.content, { paddingTop: headerHeight }]}
        keyboardShouldPersistTaps="handled"
      >
        {/* Header with Plex logo */}
        <View style={styles.logoHeader}>
          <View style={styles.logoContainer}>
            <PlexIcon size={32} color="#e5a00d" />
          </View>
          <Text style={styles.logoTitle}>Plex Media Server</Text>
          {plexUser && (
            <Text style={styles.logoSubtitle}>
              Signed in as {plexUser?.username || plexUser?.title || 'User'}
            </Text>
          )}
        </View>

        {/* Current Server Card */}
        <SettingsCard title="CURRENT SERVER">
          {serverInfo ? (
            <SettingItem
              title={serverInfo.name}
              description={serverInfo.url}
              icon="checkmark-circle"
              isLast={true}
            />
          ) : (
            <SettingItem
              title="No server connected"
              description="Select a server below"
              icon="alert-circle-outline"
              isLast={true}
            />
          )}
        </SettingsCard>

        {/* Watchlist Provider Preference */}
        {isTraktConnected && (
          <SettingsCard title="PREFERENCES">
            <View style={styles.preferenceItem}>
              <View style={styles.preferenceHeader}>
                <Text style={styles.preferenceTitle}>Save to Watchlist</Text>
                <Text style={styles.preferenceDescription}>Where new items are added</Text>
              </View>
              <View style={styles.providerToggle}>
                <Pressable
                  style={[
                    styles.providerOption,
                    watchlistProvider === 'trakt' && styles.providerOptionActive,
                  ]}
                  onPress={() => handleWatchlistProviderChange('trakt')}
                >
                  <TraktIcon size={16} color={watchlistProvider === 'trakt' ? '#fff' : '#9ca3af'} />
                  <Text
                    style={[
                      styles.providerOptionText,
                      watchlistProvider === 'trakt' && styles.providerOptionTextActive,
                    ]}
                  >
                    Trakt
                  </Text>
                </Pressable>
                <Pressable
                  style={[
                    styles.providerOption,
                    watchlistProvider === 'plex' && styles.providerOptionActive,
                  ]}
                  onPress={() => handleWatchlistProviderChange('plex')}
                >
                  <PlexIcon size={16} color={watchlistProvider === 'plex' ? '#fff' : '#9ca3af'} />
                  <Text
                    style={[
                      styles.providerOptionText,
                      watchlistProvider === 'plex' && styles.providerOptionTextActive,
                    ]}
                  >
                    Plex
                  </Text>
                </Pressable>
              </View>
            </View>
          </SettingsCard>
        )}

        {/* Available Servers */}
        <SettingsCard title="AVAILABLE SERVERS">
          {loading ? (
            <View style={styles.loadingWrap}>
              <ActivityIndicator color="#e5a00d" />
              <Text style={styles.loadingText}>Loading servers...</Text>
            </View>
          ) : servers.length === 0 ? (
            <View style={styles.emptyWrap}>
              <Ionicons name="server-outline" size={32} color="#6b7280" />
              <Text style={styles.emptyText}>No servers found</Text>
            </View>
          ) : (
            servers.map((server, index) => {
              const isCurrentServer = server.id === currentServerId;
              const isConnectingToThis = connecting === server.id;
              const isExpanded = expandedServerId === server.id;

              return (
                <View key={server.id}>
                  <View
                    style={[
                      styles.serverItem,
                      index < servers.length - 1 && !isExpanded && styles.serverItemBorder,
                      isCurrentServer && styles.serverItemActive,
                    ]}
                  >
                    <View style={styles.serverIcon}>
                      <Ionicons
                        name={server.owned ? "server" : "cloud-outline"}
                        size={18}
                        color={isCurrentServer ? "#e5a00d" : "#e5e7eb"}
                      />
                    </View>
                    <View style={styles.serverInfo}>
                      <Text style={[styles.serverName, isCurrentServer && styles.serverNameActive]}>
                        {server.name}
                      </Text>
                      <Text style={styles.serverMeta}>
                        {server.owned ? 'Owned' : 'Shared'} · {server.presence ? 'Online' : 'Offline'}
                      </Text>
                    </View>
                    <View style={styles.serverActions}>
                      <Pressable
                        style={[styles.actionButton, isExpanded && styles.actionButtonExpanded]}
                        onPress={() => toggleServerEndpoints(server.id)}
                      >
                        <Ionicons
                          name={isExpanded ? "chevron-up" : "chevron-down"}
                          size={14}
                          color={isExpanded ? "#e5a00d" : "#9ca3af"}
                        />
                        <Text style={[styles.actionButtonText, isExpanded && styles.actionButtonTextExpanded]}>
                          Endpoints
                        </Text>
                      </Pressable>
                      {!isCurrentServer && (
                        <Pressable
                          style={[styles.actionButton, styles.actionButtonPrimary]}
                          onPress={() => connectToServer(server)}
                          disabled={isConnectingToThis || (connecting !== null && !isConnectingToThis)}
                        >
                          {isConnectingToThis ? (
                            <ActivityIndicator size="small" color="#000" />
                          ) : (
                            <Text style={[styles.actionButtonText, styles.actionButtonTextPrimary]}>
                              Switch
                            </Text>
                          )}
                        </Pressable>
                      )}
                      {isCurrentServer && !isExpanded && (
                        <Ionicons name="checkmark-circle" size={20} color="#e5a00d" />
                      )}
                    </View>
                  </View>
                  {renderServerEndpoints(server.id)}
                  {isExpanded && index < servers.length - 1 && (
                    <View style={styles.serverItemBorder} />
                  )}
                </View>
              );
            })
          )}
        </SettingsCard>

        {/* Refresh button */}
        <Pressable style={styles.refreshButton} onPress={loadData} disabled={loading}>
          <Ionicons name="refresh-outline" size={18} color="#3b82f6" />
          <Text style={styles.refreshButtonText}>Refresh Servers</Text>
        </Pressable>

        {/* Account Section - Logout */}
        <SettingsCard title="ACCOUNT">
          <Pressable style={styles.logoutButton} onPress={handleLogout}>
            <Ionicons name="log-out-outline" size={20} color="#ef4444" />
            <Text style={styles.logoutButtonText}>Sign Out of Plex</Text>
          </Pressable>
          <Text style={styles.logoutHint}>Sign out and return to login screen</Text>
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
    backgroundColor: 'rgba(229, 160, 13, 0.1)',
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
  loadingWrap: {
    padding: 24,
    alignItems: 'center',
    gap: 12,
  },
  loadingText: {
    color: '#9ca3af',
    fontSize: 14,
  },
  emptyWrap: {
    padding: 24,
    alignItems: 'center',
    gap: 12,
  },
  emptyText: {
    color: '#6b7280',
    fontSize: 14,
  },
  serverItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 14,
    paddingVertical: 14,
  },
  serverItemBorder: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: 'rgba(255,255,255,0.08)',
  },
  serverItemActive: {
    backgroundColor: 'rgba(229, 160, 13, 0.05)',
  },
  serverIcon: {
    width: 34,
    height: 34,
    borderRadius: 10,
    backgroundColor: 'rgba(229,231,235,0.08)',
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 12,
  },
  serverInfo: {
    flex: 1,
  },
  serverName: {
    color: '#f9fafb',
    fontSize: 15,
    fontWeight: '600',
  },
  serverNameActive: {
    color: '#e5a00d',
  },
  serverMeta: {
    color: '#9ca3af',
    fontSize: 12,
    marginTop: 2,
  },
  serverActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  actionButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 8,
    backgroundColor: 'rgba(255,255,255,0.08)',
  },
  actionButtonExpanded: {
    backgroundColor: 'rgba(229, 160, 13, 0.15)',
  },
  actionButtonPrimary: {
    backgroundColor: '#e5a00d',
  },
  actionButtonText: {
    color: '#9ca3af',
    fontSize: 12,
    fontWeight: '600',
  },
  actionButtonTextExpanded: {
    color: '#e5a00d',
  },
  actionButtonTextPrimary: {
    color: '#000',
  },
  refreshButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    marginTop: 16,
    marginBottom: 16,
    paddingVertical: 12,
    paddingHorizontal: 16,
    backgroundColor: 'rgba(59, 130, 246, 0.1)',
    borderRadius: 10,
    alignSelf: 'center',
  },
  refreshButtonText: {
    color: '#3b82f6',
    fontWeight: '600',
    fontSize: 14,
  },
  // Preference styles
  preferenceItem: {
    padding: 14,
  },
  preferenceHeader: {
    marginBottom: 12,
  },
  preferenceTitle: {
    color: '#f9fafb',
    fontSize: 15,
    fontWeight: '600',
  },
  preferenceDescription: {
    color: '#9ca3af',
    fontSize: 12,
    marginTop: 2,
  },
  providerToggle: {
    flexDirection: 'row',
    gap: 8,
  },
  providerOption: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 10,
    backgroundColor: 'rgba(255,255,255,0.06)',
    flex: 1,
    justifyContent: 'center',
  },
  providerOptionActive: {
    backgroundColor: 'rgba(229, 160, 13, 0.2)',
    borderWidth: 1,
    borderColor: '#e5a00d',
  },
  providerOptionText: {
    color: '#9ca3af',
    fontSize: 14,
    fontWeight: '600',
  },
  providerOptionTextActive: {
    color: '#fff',
  },
  // Logout styles
  logoutButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    paddingVertical: 14,
    marginHorizontal: 14,
    marginTop: 8,
    backgroundColor: 'rgba(239, 68, 68, 0.1)',
    borderRadius: 10,
  },
  logoutButtonText: {
    color: '#ef4444',
    fontSize: 15,
    fontWeight: '600',
  },
  logoutHint: {
    color: '#6b7280',
    fontSize: 12,
    textAlign: 'center',
    marginTop: 8,
    marginBottom: 14,
  },
  // Inline endpoints styles
  endpointsContainer: {
    backgroundColor: 'rgba(0,0,0,0.3)',
    marginHorizontal: 14,
    marginBottom: 10,
    borderRadius: 10,
    padding: 12,
  },
  endpointsLoading: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    padding: 16,
  },
  endpointsLoadingText: {
    color: '#9ca3af',
    fontSize: 13,
  },
  testAllButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    paddingVertical: 8,
    marginBottom: 10,
    backgroundColor: 'rgba(59, 130, 246, 0.1)',
    borderRadius: 6,
  },
  testAllButtonText: {
    color: '#3b82f6',
    fontSize: 12,
    fontWeight: '600',
  },
  noEndpointsText: {
    color: '#6b7280',
    fontSize: 13,
    textAlign: 'center',
    padding: 16,
  },
  endpointRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 10,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: 'rgba(255,255,255,0.06)',
  },
  endpointInfo: {
    flex: 1,
    marginRight: 8,
  },
  endpointTypeRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    marginBottom: 4,
  },
  typeBadge: {
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
  },
  typeBadgeText: {
    fontSize: 9,
    fontWeight: '700',
    textTransform: 'uppercase',
  },
  currentBadge: {
    width: 16,
    height: 16,
    borderRadius: 8,
    backgroundColor: 'rgba(229, 160, 13, 0.2)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  endpointUri: {
    color: '#e5e7eb',
    fontSize: 12,
  },
  endpointMeta: {
    color: '#6b7280',
    fontSize: 10,
    marginTop: 2,
  },
  endpointActions: {
    flexDirection: 'row',
    gap: 6,
  },
  smallButton: {
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: 6,
    backgroundColor: 'rgba(59, 130, 246, 0.15)',
    minWidth: 40,
    alignItems: 'center',
  },
  smallButtonPrimary: {
    backgroundColor: '#e5a00d',
  },
  smallButtonDisabled: {
    opacity: 0.4,
  },
  smallButtonText: {
    color: '#3b82f6',
    fontSize: 11,
    fontWeight: '600',
  },
  smallButtonTextPrimary: {
    color: '#000',
  },
  // Custom endpoint styles
  customEndpointSection: {
    marginTop: 12,
    paddingTop: 12,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: 'rgba(255,255,255,0.08)',
  },
  customLabel: {
    color: '#9ca3af',
    fontSize: 11,
    fontWeight: '600',
    marginBottom: 8,
    textTransform: 'uppercase',
  },
  customInputRow: {
    marginBottom: 8,
  },
  customInput: {
    backgroundColor: 'rgba(255,255,255,0.06)',
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
    color: '#fff',
    fontSize: 13,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
  },
  customActions: {
    flexDirection: 'row',
    gap: 8,
  },
});
