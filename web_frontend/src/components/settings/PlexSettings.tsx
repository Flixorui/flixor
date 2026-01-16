import { useState, useEffect, useCallback } from 'react';
import SettingsCard from '@/components/SettingsCard';
import { AppSettings, loadSettings, saveSettings } from '@/state/settings';
import { apiClient } from '@/services/api';
import {
  PlexIcon,
  TraktIcon,
  ChevronBackIcon,
  CheckmarkCircleIcon,
  ServerIcon,
  CloudIcon,
  RefreshIcon,
  ChevronForwardIcon,
  ChevronDownIcon,
} from '@/components/ServiceIcons';

interface PlexSettingsProps {
  settings: AppSettings;
  updateSetting: <K extends keyof AppSettings>(key: K, value: AppSettings[K]) => void;
  onBack: () => void;
}

type PlexServer = {
  id: string;
  name: string;
  owned: boolean;
  presence: boolean;
  accessToken: string;
  connections: Array<{
    uri: string;
    protocol: string;
    local: boolean;
    relay: boolean;
  }>;
};

type PlexConnection = {
  uri: string;
  protocol: string;
  local: boolean;
  relay: boolean;
  isPreferred?: boolean;
  isCurrent?: boolean;
};

export default function PlexSettings({ settings, updateSetting, onBack }: PlexSettingsProps) {
  const [loading, setLoading] = useState(true);
  const [servers, setServers] = useState<PlexServer[]>([]);
  const [currentServer, setCurrentServer] = useState<{ name: string; url: string } | null>(null);
  const [connecting, setConnecting] = useState<string | null>(null);

  // Endpoint expansion state
  const [expandedServerId, setExpandedServerId] = useState<string | null>(null);
  const [endpoints, setEndpoints] = useState<PlexConnection[]>([]);
  const [loadingEndpoints, setLoadingEndpoints] = useState(false);
  const [testingEndpoint, setTestingEndpoint] = useState<string | null>(null);
  const [testResults, setTestResults] = useState<Record<string, 'success' | 'failed' | 'testing'>>({});
  const [selectingEndpoint, setSelectingEndpoint] = useState<string | null>(null);

  // Custom endpoint
  const [customEndpoint, setCustomEndpoint] = useState('');
  const [testingCustom, setTestingCustom] = useState(false);

  // Watchlist provider
  const isTraktConnected = !!(settings.traktAccessToken || settings.traktTokens);
  const [watchlistProvider, setWatchlistProvider] = useState<'trakt' | 'plex'>(settings.watchlistProvider || 'trakt');

  const loadData = useCallback(async () => {
    setLoading(true);
    try {
      const response = await apiClient.plexServers();
      console.log('[PlexSettings] API response:', response);

      // Handle different response structures
      const serverList = response.servers || response.data?.servers || response || [];
      if (Array.isArray(serverList) && serverList.length > 0) {
        setServers(serverList);
      } else if (settings.plexServers && settings.plexServers.length > 0) {
        // Fallback to localStorage plexServers
        const mappedServers = settings.plexServers.map((s: any) => ({
          id: s.clientIdentifier || s.id || s.name,
          name: s.name,
          owned: true,
          presence: true,
          accessToken: s.token,
          connections: [{ uri: s.bestUri || s.baseUrl, protocol: 'https', local: false, relay: false }],
        }));
        setServers(mappedServers);
      }

      // Set current server
      const current = response.currentServer || response.data?.currentServer;
      if (current) {
        setCurrentServer({
          name: current.name,
          url: current.uri || current.bestUri || '',
        });
      } else if (settings.plexServer) {
        setCurrentServer({
          name: settings.plexServer.name,
          url: settings.plexServer.baseUrl,
        });
      }
    } catch (e) {
      console.error('[PlexSettings] Error loading servers:', e);
      // Fallback to localStorage settings
      if (settings.plexServers && settings.plexServers.length > 0) {
        const mappedServers = settings.plexServers.map((s: any) => ({
          id: s.clientIdentifier || s.id || s.name,
          name: s.name,
          owned: true,
          presence: true,
          accessToken: s.token,
          connections: [{ uri: s.bestUri || s.baseUrl, protocol: 'https', local: false, relay: false }],
        }));
        setServers(mappedServers);
      }
      if (settings.plexServer) {
        setCurrentServer({
          name: settings.plexServer.name,
          url: settings.plexServer.baseUrl,
        });
      }
    } finally {
      setLoading(false);
    }
  }, [settings.plexServer, settings.plexServers]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const connectToServer = async (server: PlexServer) => {
    try {
      setConnecting(server.id);
      await apiClient.plexSetCurrentServer(server.id);
      await loadData();
    } catch (e: any) {
      console.error('[PlexSettings] Connect error:', e);
      alert(`Could not connect to ${server.name}. Make sure the server is online.`);
    } finally {
      setConnecting(null);
    }
  };

  const toggleServerEndpoints = async (serverId: string) => {
    if (expandedServerId === serverId) {
      setExpandedServerId(null);
      setEndpoints([]);
      setTestResults({});
      setCustomEndpoint('');
      return;
    }

    setExpandedServerId(serverId);
    setLoadingEndpoints(true);
    setTestResults({});
    setCustomEndpoint('');

    try {
      const response = await apiClient.plexServerConnections(serverId);
      setEndpoints(response.connections || []);
    } catch (e) {
      console.error('[PlexSettings] Error loading endpoints:', e);
      setEndpoints([]);
    } finally {
      setLoadingEndpoints(false);
    }
  };

  const testEndpoint = async (uri: string) => {
    if (!expandedServerId) return;

    setTestingEndpoint(uri);
    setTestResults(prev => ({ ...prev, [uri]: 'testing' }));

    try {
      const response = await apiClient.plexSetServerEndpoint(expandedServerId, uri, true);
      setTestResults(prev => ({ ...prev, [uri]: response.success ? 'success' : 'failed' }));
    } catch (e) {
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

  const selectEndpoint = async (uri: string) => {
    if (!expandedServerId) return;

    try {
      setSelectingEndpoint(uri);
      await apiClient.plexSetServerEndpoint(expandedServerId, uri, false);
      await loadData();
      alert('Successfully switched to the selected endpoint.');
    } catch (e: any) {
      alert(e.message || 'Could not connect to this endpoint.');
    } finally {
      setSelectingEndpoint(null);
    }
  };

  const testCustomEndpoint = async () => {
    if (!customEndpoint.trim() || !expandedServerId) return;

    setTestingCustom(true);
    const uri = customEndpoint.trim();

    try {
      const response = await apiClient.plexSetServerEndpoint(expandedServerId, uri, true);
      if (response.success) {
        if (confirm('Custom endpoint is reachable! Use this endpoint?')) {
          await selectEndpoint(uri);
        }
      } else {
        alert('Could not reach this endpoint. Check the URL and try again.');
      }
    } catch (e) {
      alert('Failed to test endpoint.');
    } finally {
      setTestingCustom(false);
    }
  };

  const handleWatchlistProviderChange = (provider: 'trakt' | 'plex') => {
    setWatchlistProvider(provider);
    updateSetting('watchlistProvider', provider);
  };

  const handleLogout = async () => {
    if (!confirm('Are you sure you want to sign out of Plex? You will need to sign in again to access your media.')) {
      return;
    }
    try {
      await apiClient.logout();
      // Clear local settings
      saveSettings({
        plexBaseUrl: undefined,
        plexToken: undefined,
        plexTvToken: undefined,
        plexAccountToken: undefined,
        plexServer: undefined,
        plexServers: undefined,
        plexUserProfile: undefined,
      });
      window.location.href = '/login';
    } catch (e) {
      console.error('[PlexSettings] Logout error:', e);
    }
  };

  const getEndpointType = (conn: PlexConnection): 'local' | 'remote' | 'relay' => {
    if (conn.local && !conn.relay) return 'local';
    if (conn.relay) return 'relay';
    return 'remote';
  };

  const getEndpointColor = (conn: PlexConnection): string => {
    const type = getEndpointType(conn);
    switch (type) {
      case 'local': return '#22c55e';
      case 'remote': return '#3b82f6';
      case 'relay': return '#f59e0b';
      default: return '#9ca3af';
    }
  };

  const currentServerId = currentServer ? servers.find(s => s.name === currentServer.name)?.id : null;

  return (
    <div className="min-h-screen bg-[#0b0b0d] pb-20">
      {/* Header with back button */}
      <div className="px-4 pt-6 pb-4 flex items-center gap-3">
        <button
          onClick={onBack}
          className="flex items-center justify-center w-10 h-10 rounded-full hover:bg-white/10 transition-colors"
        >
          <ChevronBackIcon size={24} color="#fff" />
        </button>
        <h1 className="text-white text-xl font-bold">Plex</h1>
      </div>

      <div className="px-4 max-w-2xl mx-auto">
        {/* Logo Header */}
        <div className="flex flex-col items-center mb-5 py-4">
          <div
            className="w-16 h-16 rounded-2xl flex items-center justify-center mb-3"
            style={{ backgroundColor: 'rgba(229, 160, 13, 0.1)' }}
          >
            <PlexIcon size={32} color="#e5a00d" />
          </div>
          <span className="text-white text-lg font-bold">Plex Media Server</span>
          {settings.plexUserProfile && (
            <span className="text-[#9ca3af] text-[13px] mt-1">
              Signed in as {settings.plexUserProfile.username || settings.plexUserProfile.title || 'User'}
            </span>
          )}
        </div>

        {/* Current Server */}
        <SettingsCard title="CURRENT SERVER">
          {currentServer ? (
            <div className="p-3.5 flex items-center gap-3">
              <CheckmarkCircleIcon size={20} color="#e5a00d" />
              <div className="flex-1 min-w-0">
                <p className="text-[#f9fafb] text-[15px] font-semibold">{currentServer.name}</p>
                <p className="text-[#9ca3af] text-xs truncate">{currentServer.url}</p>
              </div>
            </div>
          ) : (
            <div className="p-3.5 flex items-center gap-3">
              <div className="w-5 h-5 rounded-full bg-white/10 flex items-center justify-center">
                <span className="text-[#9ca3af] text-xs">?</span>
              </div>
              <div className="flex-1">
                <p className="text-[#f9fafb] text-[15px] font-semibold">No server connected</p>
                <p className="text-[#9ca3af] text-xs">Select a server below</p>
              </div>
            </div>
          )}
        </SettingsCard>

        {/* Watchlist Provider - only if Trakt connected */}
        {isTraktConnected && (
          <SettingsCard title="PREFERENCES">
            <div className="p-3.5">
              <div className="mb-3">
                <p className="text-[#f9fafb] text-[15px] font-semibold">Save to Watchlist</p>
                <p className="text-[#9ca3af] text-xs mt-0.5">Where new items are added</p>
              </div>
              <div className="flex gap-2">
                <button
                  onClick={() => handleWatchlistProviderChange('trakt')}
                  className={`flex-1 flex items-center justify-center gap-2 px-4 py-2.5 rounded-[10px] transition-all ${
                    watchlistProvider === 'trakt'
                      ? 'bg-[#e5a00d]/20 border border-[#e5a00d]'
                      : 'bg-white/[0.06]'
                  }`}
                >
                  <TraktIcon size={16} color={watchlistProvider === 'trakt' ? '#fff' : '#9ca3af'} />
                  <span className={`text-sm font-semibold ${watchlistProvider === 'trakt' ? 'text-white' : 'text-[#9ca3af]'}`}>
                    Trakt
                  </span>
                </button>
                <button
                  onClick={() => handleWatchlistProviderChange('plex')}
                  className={`flex-1 flex items-center justify-center gap-2 px-4 py-2.5 rounded-[10px] transition-all ${
                    watchlistProvider === 'plex'
                      ? 'bg-[#e5a00d]/20 border border-[#e5a00d]'
                      : 'bg-white/[0.06]'
                  }`}
                >
                  <PlexIcon size={16} color={watchlistProvider === 'plex' ? '#fff' : '#9ca3af'} />
                  <span className={`text-sm font-semibold ${watchlistProvider === 'plex' ? 'text-white' : 'text-[#9ca3af]'}`}>
                    Plex
                  </span>
                </button>
              </div>
            </div>
          </SettingsCard>
        )}

        {/* Available Servers */}
        <SettingsCard title="AVAILABLE SERVERS">
          {loading ? (
            <div className="p-6 flex flex-col items-center gap-3">
              <div className="w-5 h-5 border-2 border-[#e5a00d] border-t-transparent rounded-full animate-spin" />
              <span className="text-[#9ca3af] text-sm">Loading servers...</span>
            </div>
          ) : servers.length === 0 ? (
            <div className="p-6 flex flex-col items-center gap-3">
              <ServerIcon size={32} color="#6b7280" />
              <span className="text-[#6b7280] text-sm">No servers found</span>
            </div>
          ) : (
            <div>
              {servers.map((server, index) => {
                const isCurrentServer = server.id === currentServerId;
                const isConnectingToThis = connecting === server.id;
                const isExpanded = expandedServerId === server.id;

                return (
                  <div key={server.id}>
                    <div
                      className={`px-3.5 py-3.5 flex items-center gap-3 ${
                        index < servers.length - 1 && !isExpanded ? 'border-b border-white/[0.08]' : ''
                      } ${isCurrentServer ? 'bg-[#e5a00d]/5' : ''}`}
                    >
                      {/* Server icon */}
                      <div className="w-[34px] h-[34px] rounded-[10px] bg-white/[0.08] flex items-center justify-center">
                        {server.owned ? (
                          <ServerIcon size={18} color={isCurrentServer ? '#e5a00d' : '#e5e7eb'} />
                        ) : (
                          <CloudIcon size={18} color={isCurrentServer ? '#e5a00d' : '#e5e7eb'} />
                        )}
                      </div>

                      {/* Server info */}
                      <div className="flex-1 min-w-0">
                        <p className={`text-[15px] font-semibold ${isCurrentServer ? 'text-[#e5a00d]' : 'text-[#f9fafb]'}`}>
                          {server.name}
                        </p>
                        <p className="text-[#9ca3af] text-xs mt-0.5">
                          {server.owned ? 'Owned' : 'Shared'} · {server.presence ? 'Online' : 'Offline'}
                        </p>
                      </div>

                      {/* Actions */}
                      <div className="flex items-center gap-2">
                        {/* Endpoints toggle */}
                        <button
                          onClick={() => toggleServerEndpoints(server.id)}
                          className={`flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-xs font-semibold transition-colors ${
                            isExpanded
                              ? 'bg-[#e5a00d]/15 text-[#e5a00d]'
                              : 'bg-white/[0.08] text-[#9ca3af] hover:bg-white/[0.12]'
                          }`}
                        >
                          {isExpanded ? (
                            <ChevronDownIcon size={12} color="#e5a00d" />
                          ) : (
                            <ChevronForwardIcon size={12} color="#9ca3af" />
                          )}
                          Endpoints
                        </button>

                        {/* Switch button */}
                        {!isCurrentServer && (
                          <button
                            onClick={() => connectToServer(server)}
                            disabled={isConnectingToThis || (connecting !== null && !isConnectingToThis)}
                            className="px-3 py-1.5 rounded-lg bg-[#e5a00d] text-black text-xs font-semibold disabled:opacity-50"
                          >
                            {isConnectingToThis ? (
                              <div className="w-4 h-4 border-2 border-black border-t-transparent rounded-full animate-spin" />
                            ) : (
                              'Switch'
                            )}
                          </button>
                        )}

                        {/* Current indicator */}
                        {isCurrentServer && !isExpanded && (
                          <CheckmarkCircleIcon size={20} color="#e5a00d" />
                        )}
                      </div>
                    </div>

                    {/* Endpoints panel */}
                    {isExpanded && (
                      <div className="mx-3.5 mb-3 bg-black/30 rounded-[10px] p-3">
                        {loadingEndpoints ? (
                          <div className="flex items-center justify-center gap-2 py-4">
                            <div className="w-4 h-4 border-2 border-[#e5a00d] border-t-transparent rounded-full animate-spin" />
                            <span className="text-[#9ca3af] text-[13px]">Loading endpoints...</span>
                          </div>
                        ) : (
                          <>
                            {/* Test All button */}
                            {endpoints.length > 0 && (
                              <button
                                onClick={testAllEndpoints}
                                className="w-full flex items-center justify-center gap-1.5 py-2 mb-3 bg-[#3b82f6]/10 rounded-md"
                              >
                                <RefreshIcon size={14} color="#3b82f6" />
                                <span className="text-[#3b82f6] text-xs font-semibold">Test All</span>
                              </button>
                            )}

                            {/* Endpoints list */}
                            {endpoints.length === 0 ? (
                              <p className="text-[#6b7280] text-[13px] text-center py-4">No endpoints available</p>
                            ) : (
                              endpoints.map((endpoint) => (
                                <div
                                  key={endpoint.uri}
                                  className="flex items-center py-2.5 border-b border-white/[0.06] last:border-0"
                                >
                                  <div className="flex-1 min-w-0 mr-2">
                                    {/* Type badge and test result */}
                                    <div className="flex items-center gap-1.5 mb-1">
                                      <span
                                        className="px-1.5 py-0.5 rounded text-[9px] font-bold uppercase"
                                        style={{
                                          backgroundColor: `${getEndpointColor(endpoint)}20`,
                                          color: getEndpointColor(endpoint),
                                        }}
                                      >
                                        {getEndpointType(endpoint)}
                                      </span>
                                      {testResults[endpoint.uri] === 'testing' && (
                                        <div className="w-3 h-3 border-2 border-[#e5a00d] border-t-transparent rounded-full animate-spin" />
                                      )}
                                      {testResults[endpoint.uri] === 'success' && (
                                        <CheckmarkCircleIcon size={14} color="#22c55e" />
                                      )}
                                      {testResults[endpoint.uri] === 'failed' && (
                                        <div className="w-3.5 h-3.5 rounded-full bg-red-500/20 flex items-center justify-center">
                                          <span className="text-red-500 text-[8px]">✕</span>
                                        </div>
                                      )}
                                      {endpoint.isCurrent && (
                                        <span className="w-4 h-4 rounded-full bg-[#e5a00d]/20 flex items-center justify-center">
                                          <CheckmarkCircleIcon size={10} color="#e5a00d" />
                                        </span>
                                      )}
                                    </div>
                                    <p className="text-[#e5e7eb] text-xs truncate">{endpoint.uri}</p>
                                    {(endpoint.isPreferred || endpoint.isCurrent) && (
                                      <p className="text-[#6b7280] text-[10px] mt-0.5">
                                        {[endpoint.isPreferred && 'preferred', endpoint.isCurrent && 'current'].filter(Boolean).join(' · ')}
                                      </p>
                                    )}
                                  </div>

                                  {/* Actions */}
                                  <div className="flex gap-1.5">
                                    <button
                                      onClick={() => testEndpoint(endpoint.uri)}
                                      disabled={testingEndpoint !== null}
                                      className="px-2.5 py-1 rounded-md bg-[#3b82f6]/15 text-[#3b82f6] text-[11px] font-semibold disabled:opacity-50"
                                    >
                                      {testingEndpoint === endpoint.uri ? '...' : 'Test'}
                                    </button>
                                    {!endpoint.isCurrent && (
                                      <button
                                        onClick={() => selectEndpoint(endpoint.uri)}
                                        disabled={selectingEndpoint !== null}
                                        className="px-2.5 py-1 rounded-md bg-[#e5a00d] text-black text-[11px] font-semibold disabled:opacity-50"
                                      >
                                        {selectingEndpoint === endpoint.uri ? '...' : 'Use'}
                                      </button>
                                    )}
                                  </div>
                                </div>
                              ))
                            )}

                            {/* Custom endpoint */}
                            <div className="mt-3 pt-3 border-t border-white/[0.08]">
                              <p className="text-[#9ca3af] text-[11px] font-semibold uppercase mb-2">Custom Endpoint</p>
                              <input
                                type="text"
                                value={customEndpoint}
                                onChange={(e) => setCustomEndpoint(e.target.value)}
                                placeholder="https://plex.example.com:32400"
                                className="w-full px-3 py-2.5 bg-white/[0.06] border border-white/[0.1] rounded-lg text-white text-[13px] placeholder-[#6b7280] mb-2"
                              />
                              <div className="flex gap-2">
                                <button
                                  onClick={testCustomEndpoint}
                                  disabled={testingCustom || !customEndpoint.trim()}
                                  className="px-3 py-1.5 rounded-md bg-[#3b82f6]/15 text-[#3b82f6] text-[11px] font-semibold disabled:opacity-40"
                                >
                                  {testingCustom ? '...' : 'Test'}
                                </button>
                                <button
                                  onClick={() => selectEndpoint(customEndpoint.trim())}
                                  disabled={selectingEndpoint !== null || !customEndpoint.trim()}
                                  className="px-3 py-1.5 rounded-md bg-[#e5a00d] text-black text-[11px] font-semibold disabled:opacity-40"
                                >
                                  Use
                                </button>
                              </div>
                            </div>
                          </>
                        )}
                      </div>
                    )}

                    {isExpanded && index < servers.length - 1 && (
                      <div className="border-b border-white/[0.08]" />
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </SettingsCard>

        {/* Refresh button */}
        <button
          onClick={loadData}
          disabled={loading}
          className="w-full flex items-center justify-center gap-2 py-3 mt-4 bg-[#3b82f6]/10 rounded-[10px] disabled:opacity-50"
        >
          <RefreshIcon size={18} color="#3b82f6" />
          <span className="text-[#3b82f6] text-sm font-semibold">Refresh Servers</span>
        </button>

        {/* Sign Out */}
        <SettingsCard title="ACCOUNT">
          <div className="p-3.5">
            <button
              onClick={handleLogout}
              className="w-full flex items-center justify-center gap-2 py-3 bg-red-500/10 rounded-[10px] hover:bg-red-500/20 transition-colors"
            >
              <svg className="w-5 h-5 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
              </svg>
              <span className="text-red-500 text-[15px] font-semibold">Sign Out of Plex</span>
            </button>
            <p className="text-[#6b7280] text-xs text-center mt-2">Sign out and return to login screen</p>
          </div>
        </SettingsCard>
      </div>
    </div>
  );
}
