import { useState, useEffect, useRef } from 'react';
import SettingsCard from '@/components/SettingsCard';
import SettingItem, { SettingToggle } from '@/components/SettingItem';
import { AppSettings } from '@/state/settings';
import {
  traktGetUserProfile,
  traktPollForToken,
  traktRequestDeviceCode,
  traktRevokeToken,
  type TraktDeviceCode,
} from '@/services/trakt';
import { clearTraktReconnect } from '@/services/traktConnection';
import {
  TraktIcon,
  ChevronBackIcon,
  CheckmarkCircleIcon,
  CloseCircleIcon,
  CopyIcon,
  CheckmarkIcon,
} from '@/components/ServiceIcons';

interface TraktSettingsProps {
  settings: AppSettings;
  updateSetting: <K extends keyof AppSettings>(key: K, value: AppSettings[K]) => void;
  onBack: () => void;
}

export default function TraktSettings({ settings, updateSetting, onBack }: TraktSettingsProps) {
  const [connected, setConnected] = useState(false);
  const [needsReconnect, setNeedsReconnect] = useState(false);
  const [authError, setAuthError] = useState<string | null>(null);
  const [deviceCode, setDeviceCode] = useState<TraktDeviceCode | null>(null);
  const [copied, setCopied] = useState(false);
  const pollRef = useRef<number | null>(null);

  const stopPolling = () => {
    if (pollRef.current) clearInterval(pollRef.current);
    pollRef.current = null;
  };

  // The backend's tokens are what every Trakt feature uses, so ask it directly.
  const hasLocalTokens = !!(settings.traktAccessToken || settings.traktTokens);
  useEffect(() => {
    let alive = true;
    traktGetUserProfile('')
      .then(() => {
        if (!alive) return;
        setConnected(true);
        setNeedsReconnect(false);
      })
      .catch(() => {
        if (!alive) return;
        setConnected(false);
        setNeedsReconnect(hasLocalTokens);
      });
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => stopPolling, []);

  const copyCode = async () => {
    if (!deviceCode?.user_code) return;
    try {
      await navigator.clipboard.writeText(deviceCode.user_code);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch (e) {
      console.error('Failed to copy:', e);
    }
  };

  const startAuth = async () => {
    setAuthError(null);
    try {
      // Device flow through the backend, which keeps the tokens server-side.
      const dc = await traktRequestDeviceCode();
      setDeviceCode(dc);
      setCopied(false);

      window.open(dc.verification_url, '_blank');

      if (pollRef.current) clearInterval(pollRef.current);
      pollRef.current = window.setInterval(async () => {
        try {
          const tokens = await traktPollForToken(dc.device_code);
          if (!tokens) return;
          stopPolling();
          updateSetting('traktTokens', JSON.stringify(tokens));
          updateSetting('traktAccessToken', tokens.access_token);
          setDeviceCode(null);
          setConnected(true);
        } catch {
          // The code expired or was denied.
          stopPolling();
          setDeviceCode(null);
          setAuthError('Authorization did not complete. Try again.');
        }
      }, Math.max(5, Number(dc.interval || 5)) * 1000);
    } catch {
      setAuthError('Could not reach Trakt. Try again.');
    }
  };

  const handleSignOut = async () => {
    // Local sign-out still applies if the server call fails.
    await traktRevokeToken('').catch(() => undefined);
    updateSetting('traktTokens', undefined);
    updateSetting('traktAccessToken', undefined);
    clearTraktReconnect();
    setConnected(false);
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
        <h1 className="text-white text-xl font-bold">Trakt</h1>
      </div>

      <div className="px-4 max-w-2xl mx-auto">
        {/* Logo Header */}
        <div className="flex flex-col items-center mb-5 py-4">
          <div
            className="w-16 h-16 rounded-2xl flex items-center justify-center mb-3"
            style={{ backgroundColor: 'rgba(237, 28, 36, 0.1)' }}
          >
            <TraktIcon size={32} color="#ed1c24" />
          </div>
          <span className="text-white text-lg font-bold">Trakt</span>
          <span className="text-[#9ca3af] text-[13px] mt-1">Track your watch history</span>
        </div>

        {/* Account Status */}
        <SettingsCard title="ACCOUNT">
          {connected ? (
            <div className="p-3.5 space-y-2.5">
              <div className="flex items-center gap-2">
                <CheckmarkCircleIcon size={18} color="#22c55e" />
                <span className="text-[#e5e7eb] text-sm">Connected to Trakt</span>
              </div>
              <button
                onClick={handleSignOut}
                className="w-full py-2.5 rounded-[10px] font-semibold text-sm bg-white/[0.08] text-white hover:bg-white/[0.12] transition-colors"
              >
                Sign out
              </button>
            </div>
          ) : (
            <div className="p-3.5 space-y-2.5">
              <div className="flex items-center gap-2">
                <CloseCircleIcon size={18} color="#ef4444" />
                <span className="text-[#e5e7eb] text-sm">{needsReconnect ? 'Reconnect needed' : 'Not connected'}</span>
              </div>
              {needsReconnect && (
                <p className="text-[#9ca3af] text-[12px]">
                  Flixor now keeps your Trakt sign-in on the server, and your earlier sign-in was only saved in this browser.
                  Connect once more to turn syncing, scrobbling, ratings and Trakt rows back on. Your Trakt history isn't affected.
                </p>
              )}
              {authError && <p className="text-[#ef4444] text-[13px]">{authError}</p>}
              <button
                onClick={startAuth}
                className="w-full py-2.5 rounded-[10px] font-bold text-sm bg-white text-[#0b0b0d] hover:bg-white/90 transition-colors"
              >
                {needsReconnect ? 'Reconnect Trakt' : 'Connect Trakt'}
              </button>
            </div>
          )}
        </SettingsCard>

        {connected && (
          <SettingsCard title="SYNC">
            <SettingItem
              title="Auto-sync watched"
              description="Send watched status and saved progress to Trakt"
              renderRight={() => (
                <SettingToggle
                  checked={settings.traktAutoSyncWatched !== false}
                  onChange={(value) => updateSetting('traktAutoSyncWatched', value)}
                />
              )}
            />
            <SettingItem
              title="Enable scrobbling"
              description="Report your watching activity to Trakt in real time"
              renderRight={() => (
                <SettingToggle
                  checked={settings.traktScrobbleEnabled !== false}
                  onChange={(value) => updateSetting('traktScrobbleEnabled', value)}
                />
              )}
              isLast
            />
          </SettingsCard>
        )}

        {/* Device Code - shown during auth */}
        {deviceCode && (
          <SettingsCard title="DEVICE CODE">
            <div className="p-3.5 space-y-4">
              {/* Polling indicator */}
              <div className="flex items-center gap-2.5 bg-[#ed1c24]/10 p-3 rounded-[10px]">
                <div className="w-4 h-4 border-2 border-[#ed1c24] border-t-transparent rounded-full animate-spin" />
                <span className="text-[#ed1c24] text-[13px] font-medium">Waiting for authorization...</span>
              </div>

              {/* Code display */}
              <div className="flex flex-col items-center bg-white/[0.06] border border-white/[0.1] rounded-xl p-5">
                <span className="text-[#9ca3af] text-xs mb-2">Enter this code on Trakt</span>
                <span className="text-white text-3xl font-extrabold tracking-[4px] mb-4">{deviceCode.user_code}</span>
                <button
                  onClick={copyCode}
                  className={`
                    flex items-center gap-1.5 px-4 py-2.5 rounded-lg text-[13px] font-semibold transition-all
                    ${copied
                      ? 'bg-[#22c55e]/15 text-[#22c55e]'
                      : 'bg-white/[0.1] text-white hover:bg-white/[0.15]'}
                  `}
                >
                  {copied ? (
                    <>
                      <CheckmarkIcon size={16} color="#22c55e" />
                      Copied!
                    </>
                  ) : (
                    <>
                      <CopyIcon size={16} color="#fff" />
                      Copy Code
                    </>
                  )}
                </button>
              </div>

              {/* URL */}
              <div className="flex items-center gap-2">
                <span className="text-[#9ca3af] text-[13px]">Visit:</span>
                <button
                  onClick={() => window.open(deviceCode.verification_url, '_blank')}
                  className="text-[#3b82f6] text-[13px] font-medium underline"
                >
                  {deviceCode.verification_url}
                </button>
              </div>
            </div>
          </SettingsCard>
        )}
      </div>
    </div>
  );
}
