import { useState, useEffect, useRef } from 'react';
import SettingsCard from '@/components/SettingsCard';
import { AppSettings } from '@/state/settings';
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

// Trakt API constants
const TRAKT_CLIENT_ID = '14c41a682a5e3ddafb1a4b6ed59f6a2e6edab9eb0569830e7b3f9f6a88a1e2f1';

export default function TraktSettings({ settings, updateSetting, onBack }: TraktSettingsProps) {
  const [profile, setProfile] = useState<any | null>(null);
  const [deviceCode, setDeviceCode] = useState<any | null>(null);
  const [copied, setCopied] = useState(false);
  const [polling, setPolling] = useState(false);
  const pollRef = useRef<number | null>(null);

  // Check if we have Trakt tokens
  const isConnected = !!(settings.traktAccessToken || settings.traktTokens);

  useEffect(() => {
    // Try to get profile from tokens
    if (isConnected) {
      // For now just show connected status
      // In a full implementation, we'd fetch the profile from Trakt API
      setProfile({ connected: true });
    }
    return () => {
      if (pollRef.current) clearInterval(pollRef.current);
    };
  }, [isConnected]);

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
    try {
      // Start device code flow
      const response = await fetch('https://api.trakt.tv/oauth/device/code', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          client_id: settings.traktClientId || TRAKT_CLIENT_ID,
        }),
      });

      if (!response.ok) throw new Error('Failed to get device code');
      const dc = await response.json();
      setDeviceCode(dc);
      setPolling(true);
      setCopied(false);

      // Open verification URL
      window.open(dc.verification_url, '_blank');

      // Start polling for token
      if (pollRef.current) clearInterval(pollRef.current);
      pollRef.current = window.setInterval(async () => {
        try {
          const tokenResponse = await fetch('https://api.trakt.tv/oauth/device/token', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              code: dc.device_code,
              client_id: settings.traktClientId || TRAKT_CLIENT_ID,
              client_secret: '', // Not needed for device auth
            }),
          });

          if (tokenResponse.ok) {
            const tokens = await tokenResponse.json();
            // Save tokens
            updateSetting('traktTokens', JSON.stringify(tokens));
            updateSetting('traktAccessToken', tokens.access_token);

            if (pollRef.current) clearInterval(pollRef.current);
            setDeviceCode(null);
            setPolling(false);
            setProfile({ connected: true });
          }
        } catch {
          // Still waiting for authorization
        }
      }, Math.max(5, Number(dc.interval || 5)) * 1000);
    } catch (e) {
      console.error('Failed to start Trakt auth:', e);
    }
  };

  const handleSignOut = () => {
    updateSetting('traktTokens', undefined);
    updateSetting('traktAccessToken', undefined);
    setProfile(null);
  };

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
          {profile ? (
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
                <span className="text-[#e5e7eb] text-sm">Not connected</span>
              </div>
              <button
                onClick={startAuth}
                className="w-full py-2.5 rounded-[10px] font-bold text-sm bg-white text-[#0b0b0d] hover:bg-white/90 transition-colors"
              >
                Connect Trakt
              </button>
            </div>
          )}
        </SettingsCard>

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
