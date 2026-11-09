import { useEffect, useState, useMemo } from 'react';
import SettingsCard from '@/components/SettingsCard';
import SettingItem, { SettingToggle } from '@/components/SettingItem';
import { AppSettings } from '@/state/settings';
import { API_BASE_URL } from '@/services/api';
import {
  clearOverseerrCache,
  getOverseerrPlexSession,
  signInToOverseerrWithPlex,
  signOutOfOverseerrPlex,
} from '@/services/overseerr';
import {
  OverseerrIcon,
  ChevronBackIcon,
  CheckmarkCircleIcon,
  AlertCircleIcon,
  ServerIcon,
  KeyIcon,
  OpenOutlineIcon,
} from '@/components/ServiceIcons';

const OVERSEERR_PROXY = `${API_BASE_URL.replace(/\/$/, '')}/overseerr/proxy`;

// Icon wrapper - matches mobile's 34x34 icon container
function IconWrap({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="flex items-center justify-center w-[34px] h-[34px] rounded-[10px]"
      style={{ backgroundColor: 'rgba(229,231,235,0.08)' }}
    >
      {children}
    </div>
  );
}

interface OverseerrSettingsProps {
  settings: AppSettings;
  updateSetting: <K extends keyof AppSettings>(key: K, value: AppSettings[K]) => void;
  onBack: () => void;
}

export default function OverseerrSettings({ settings, updateSetting, onBack }: OverseerrSettingsProps) {
  const [url, setUrl] = useState(settings.overseerrUrl || '');
  const [apiKey, setApiKey] = useState(settings.overseerrApiKey || '');
  const [testing, setTesting] = useState(false);
  const [testResult, setTestResult] = useState<'success' | 'error' | null>(null);

  const authMethod = settings.overseerrAuthMethod ?? 'api_key';
  const [plexUsername, setPlexUsername] = useState(settings.overseerrPlexUsername || '');
  const [signingIn, setSigningIn] = useState(false);
  const [signInError, setSignInError] = useState<string | null>(null);

  const hasConfig = useMemo(
    () => url.trim().length > 0 && (authMethod === 'plex' ? plexUsername.length > 0 : apiKey.trim().length > 0),
    [url, apiKey, authMethod, plexUsername],
  );
  const isReady = settings.overseerrEnabled && hasConfig;

  // The session lives on the server and can expire, so confirm it on open.
  useEffect(() => {
    if (authMethod !== 'plex' || !settings.overseerrUrl) return;
    let alive = true;
    getOverseerrPlexSession(settings.overseerrUrl).then((session) => {
      if (!alive) return;
      const name = session.signedIn ? session.username || plexUsername : '';
      setPlexUsername(name);
      if (name !== (settings.overseerrPlexUsername || '')) updateSetting('overseerrPlexUsername', name);
    });
    return () => { alive = false; };
    // Run once per URL and method.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [authMethod, settings.overseerrUrl]);

  const signIn = async () => {
    setSigningIn(true);
    setSignInError(null);
    const result = await signInToOverseerrWithPlex(url.trim());
    setSigningIn(false);
    if (result.valid) {
      const name = result.username || 'Plex User';
      setPlexUsername(name);
      updateSetting('overseerrUrl', url.trim());
      updateSetting('overseerrPlexUsername', name);
      clearOverseerrCache();
    } else {
      setSignInError(result.error || 'Sign-in failed');
    }
  };

  const signOut = async () => {
    await signOutOfOverseerrPlex();
    setPlexUsername('');
    updateSetting('overseerrPlexUsername', '');
  };

  const saveSettings = () => {
    updateSetting('overseerrUrl', url.trim() || undefined);
    updateSetting('overseerrApiKey', apiKey.trim() || undefined);
  };

  const testConnection = async () => {
    if (!url.trim() || !apiKey.trim()) return;
    setTesting(true);
    setTestResult(null);

    try {
      const baseUrl = url.trim().replace(/\/$/, '').replace(/\/api\/v1$/, '');

      // Use backend proxy to avoid CORS issues
      const response = await fetch(OVERSEERR_PROXY, {
        method: 'POST',
        credentials: 'include',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          targetUrl: baseUrl,
          apiKey: apiKey.trim(),
          endpoint: '/auth/me',
          method: 'GET',
        }),
      });

      if (response.ok) {
        setTestResult('success');
        saveSettings();
      } else {
        setTestResult('error');
      }
    } catch {
      setTestResult('error');
    } finally {
      setTesting(false);
    }
  };

  const toggleEnabled = (value: boolean) => {
    updateSetting('overseerrEnabled', value);
  };

  return (
    <div className="min-h-screen pb-20">
      {/* Header with back button */}
      <div className="px-4 pt-6 pb-4 max-w-2xl mx-auto flex items-center gap-3">
        <button
          onClick={onBack}
          className="-ml-2 flex items-center justify-center w-10 h-10 rounded-full hover:bg-white/10 transition-colors"
        >
          <ChevronBackIcon size={24} color="#fff" />
        </button>
        <h1 className="text-white text-xl font-bold">Overseerr</h1>
      </div>

      <div className="px-4 max-w-2xl mx-auto">
        {/* Logo Header */}
        <div className="flex flex-col items-center mb-5 py-4">
          <div
            className="w-16 h-16 rounded-2xl flex items-center justify-center mb-3"
            style={{ backgroundColor: 'rgba(101, 79, 240, 0.1)' }}
          >
            <OverseerrIcon size={32} color="#654ff0" />
          </div>
          <span className="text-white text-lg font-bold">Overseerr</span>
          <span className="text-[#9ca3af] text-[13px] mt-1">Request management for Plex</span>
        </div>

        {/* Status Card */}
        <div
          className={`
            flex items-center gap-3 p-3.5 rounded-xl mb-4 border
            ${isReady ? 'bg-[#22c55e]/10 border-[#22c55e]/20' : 'bg-[#f59e0b]/10 border-[#f59e0b]/20'}
          `}
        >
          {isReady ? (
            <CheckmarkCircleIcon size={24} color="#22c55e" />
          ) : (
            <AlertCircleIcon size={24} color="#f59e0b" />
          )}
          <div className="flex-1">
            <span className="block text-white text-base font-semibold">
              {!settings.overseerrEnabled
                ? 'Overseerr Disabled'
                : !hasConfig
                  ? 'Configuration Required'
                  : 'Overseerr Active'}
            </span>
            <span className="block text-[#9ca3af] text-[13px] mt-0.5">
              {!settings.overseerrEnabled
                ? 'Enable Overseerr to request media not in your library.'
                : !hasConfig
                  ? (authMethod === 'plex' ? 'Enter your Overseerr URL and sign in with Plex.' : 'Enter your Overseerr URL and API key.')
                  : 'Request movies and TV shows directly from Flixor.'}
            </span>
          </div>
        </div>

        {/* Enable Overseerr */}
        <SettingsCard title="ENABLE OVERSEERR">
          <SettingItem
            title="Enable Overseerr Integration"
            description="Request media not in your library"
            renderIcon={() => <IconWrap><OverseerrIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={settings.overseerrEnabled || false}
                onChange={toggleEnabled}
              />
            )}
            isLast
          />
        </SettingsCard>

        {/* Server Configuration */}
        <SettingsCard title="SERVER CONFIGURATION">
          <div className={`p-3.5 space-y-3 ${!settings.overseerrEnabled ? 'opacity-50' : ''}`}>
            <div className="flex rounded-[14px] p-0.5 gap-0.5 h-[44px] bg-white/[0.04] border border-white/[0.12]">
              {([
                { value: 'api_key', label: 'API Key' },
                { value: 'plex', label: 'Sign in with Plex' },
              ] as const).map((option) => (
                <button
                  key={option.value}
                  disabled={!settings.overseerrEnabled}
                  onClick={() => {
                    updateSetting('overseerrAuthMethod', option.value);
                    clearOverseerrCache();
                  }}
                  className={`flex-1 rounded-[10px] text-[14px] font-semibold transition-colors ${
                    authMethod === option.value ? 'bg-white text-[#111827]' : 'text-[#e5e7eb] hover:text-white'
                  }`}
                >
                  {option.label}
                </button>
              ))}
            </div>
            <div>
              <label className="flex items-center gap-2 text-[#f9fafb] text-sm font-semibold mb-2">
                <ServerIcon size={16} color="#9ca3af" />
                Server URL
              </label>
              <input
                type="url"
                value={url}
                onChange={(e) => setUrl(e.target.value)}
                placeholder="https://overseerr.example.com"
                disabled={!settings.overseerrEnabled}
                className={`
                  w-full bg-white/[0.06] border border-white/[0.08] rounded-[10px]
                  px-3 py-2.5 text-white text-sm placeholder:text-[#6b7280]
                  focus:outline-none focus:ring-2 focus:ring-white/20
                  disabled:bg-white/[0.02] disabled:text-[#6b7280]
                `}
              />
            </div>
            {authMethod === 'plex' ? (
              <div className="space-y-3">
                {plexUsername ? (
                  <div className="flex items-center gap-2 p-2.5 rounded-lg text-sm bg-[#22c55e]/10 text-[#22c55e]">
                    <CheckmarkCircleIcon size={18} color="#22c55e" />
                    <span className="flex-1">Signed in as {plexUsername}</span>
                    <button onClick={signOut} className="text-[#e5e7eb] font-semibold hover:text-white">Sign out</button>
                  </div>
                ) : (
                  <button
                    onClick={signIn}
                    disabled={!settings.overseerrEnabled || !url.trim() || signingIn}
                    className={`w-full py-2.5 rounded-[10px] font-bold text-sm transition-colors ${
                      settings.overseerrEnabled && url.trim() && !signingIn
                        ? 'bg-white text-[#0b0b0d] hover:bg-white/90'
                        : 'bg-white/10 text-[#6b7280] cursor-not-allowed'
                    }`}
                  >
                    {signingIn ? 'Signing in...' : 'Sign in with Plex'}
                  </button>
                )}
                {signInError && (
                  <div className="flex items-center gap-2 p-2.5 rounded-lg text-sm bg-[#ef4444]/10 text-[#ef4444]">
                    <AlertCircleIcon size={18} color="#ef4444" />
                    {signInError}
                  </div>
                )}
                <p className="text-[#9ca3af] text-[12px]">
                  Uses your Plex account. Your Plex user must have access to this Overseerr server.
                </p>
              </div>
            ) : (
            <>
            <div>
              <label className="flex items-center gap-2 text-[#f9fafb] text-sm font-semibold mb-2">
                <KeyIcon size={16} color="#9ca3af" />
                API Key
              </label>
              <input
                type="password"
                value={apiKey}
                onChange={(e) => setApiKey(e.target.value)}
                placeholder="Your Overseerr API key"
                disabled={!settings.overseerrEnabled}
                className={`
                  w-full bg-white/[0.06] border border-white/[0.08] rounded-[10px]
                  px-3 py-2.5 text-white text-sm placeholder:text-[#6b7280]
                  focus:outline-none focus:ring-2 focus:ring-white/20
                  disabled:bg-white/[0.02] disabled:text-[#6b7280]
                `}
              />
            </div>

            {/* Test Result */}
            {testResult && (
              <div
                className={`
                  flex items-center gap-2 p-2.5 rounded-lg text-sm
                  ${testResult === 'success' ? 'bg-[#22c55e]/10 text-[#22c55e]' : 'bg-[#ef4444]/10 text-[#ef4444]'}
                `}
              >
                {testResult === 'success' ? (
                  <>
                    <CheckmarkCircleIcon size={18} color="#22c55e" />
                    Connection successful! Settings saved.
                  </>
                ) : (
                  <>
                    <AlertCircleIcon size={18} color="#ef4444" />
                    Connection failed. Check your URL and API key.
                  </>
                )}
              </div>
            )}

            <button
              onClick={testConnection}
              disabled={!settings.overseerrEnabled || !url.trim() || !apiKey.trim() || testing}
              className={`
                w-full py-2.5 rounded-[10px] font-bold text-sm
                transition-colors
                ${settings.overseerrEnabled && url.trim() && apiKey.trim() && !testing
                  ? 'bg-white text-[#0b0b0d] hover:bg-white/90'
                  : 'bg-white/10 text-[#6b7280] cursor-not-allowed'}
              `}
            >
              {testing ? 'Testing...' : 'Test Connection & Save'}
            </button>
            </>
            )}
          </div>
        </SettingsCard>

        {/* Get Your API Key */}
        <SettingsCard title="FIND YOUR API KEY">
          <div className="p-3.5 space-y-2.5">
            <div className="flex gap-2">
              <span className="text-[#6b7280] text-sm w-5">1.</span>
              <span className="text-[#e5e7eb] text-sm flex-1">
                Open your <span className="text-white font-semibold">Overseerr</span> instance
              </span>
            </div>
            <div className="flex gap-2">
              <span className="text-[#6b7280] text-sm w-5">2.</span>
              <span className="text-[#e5e7eb] text-sm flex-1">
                Go to <span className="text-white font-semibold">Settings</span> {'>'} <span className="text-white font-semibold">General</span>
              </span>
            </div>
            <div className="flex gap-2">
              <span className="text-[#6b7280] text-sm w-5">3.</span>
              <span className="text-[#e5e7eb] text-sm flex-1">Copy the API key and paste above</span>
            </div>
            {settings.overseerrUrl && (
              <button
                onClick={() => window.open(settings.overseerrUrl, '_blank')}
                className="flex items-center gap-1.5 mt-2 px-3.5 py-2.5 bg-[#654ff0]/10 rounded-[10px] text-[#654ff0] font-semibold text-sm"
              >
                Open Overseerr
                <OpenOutlineIcon size={16} color="#654ff0" />
              </button>
            )}
          </div>
        </SettingsCard>
      </div>
    </div>
  );
}
