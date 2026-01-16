import { useState, useMemo } from 'react';
import SettingsCard from '@/components/SettingsCard';
import SettingItem, { SettingToggle, SettingInput, SettingButton } from '@/components/SettingItem';
import { AppSettings } from '@/state/settings';
import {
  MDBListIcon,
  ChevronBackIcon,
  CheckmarkCircleIcon,
  AlertCircleIcon,
  AnalyticsIcon,
  OpenOutlineIcon,
} from '@/components/ServiceIcons';

// Rating providers available through MDBList
const RATING_PROVIDERS = [
  { key: 'imdb', name: 'IMDb' },
  { key: 'tmdb', name: 'TMDB' },
  { key: 'trakt', name: 'Trakt' },
  { key: 'letterboxd', name: 'Letterboxd' },
  { key: 'tomatoes', name: 'RT Critics' },
  { key: 'audience', name: 'RT Audience' },
  { key: 'metacritic', name: 'Metacritic' },
];

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

interface MDBListSettingsProps {
  settings: AppSettings;
  updateSetting: <K extends keyof AppSettings>(key: K, value: AppSettings[K]) => void;
  onBack: () => void;
}

export default function MDBListSettings({ settings, updateSetting, onBack }: MDBListSettingsProps) {
  const [apiKey, setApiKey] = useState(settings.mdblistApiKey || '');
  const hasKey = useMemo(() => apiKey.trim().length > 0, [apiKey]);
  const isReady = settings.mdblistEnabled && hasKey;

  const saveKey = () => {
    const trimmed = apiKey.trim();
    updateSetting('mdblistApiKey', trimmed.length ? trimmed : undefined);
  };

  const toggleEnabled = (value: boolean) => {
    updateSetting('mdblistEnabled', value);
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
        <h1 className="text-white text-xl font-bold">MDBList</h1>
      </div>

      <div className="px-4 max-w-2xl mx-auto">
        {/* Logo Header */}
        <div className="flex flex-col items-center mb-5 py-4">
          <div
            className="w-16 h-16 rounded-2xl flex items-center justify-center mb-3"
            style={{ backgroundColor: 'rgba(245, 197, 24, 0.1)' }}
          >
            <MDBListIcon size={32} color="#f5c518" />
          </div>
          <span className="text-white text-lg font-bold">MDBList</span>
          <span className="text-[#9ca3af] text-[13px] mt-1">Multi-source ratings aggregator</span>
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
              {!settings.mdblistEnabled
                ? 'MDBList Disabled'
                : !hasKey
                  ? 'API Key Required'
                  : 'MDBList Active'}
            </span>
            <span className="block text-[#9ca3af] text-[13px] mt-0.5">
              {!settings.mdblistEnabled
                ? 'Enable MDBList to fetch ratings from multiple sources.'
                : !hasKey
                  ? 'Enter your MDBList API key to start fetching ratings.'
                  : 'Fetching ratings from IMDb, TMDB, Trakt, RT, and more.'}
            </span>
          </div>
        </div>

        {/* Enable MDBList */}
        <SettingsCard title="ENABLE MDBLIST">
          <SettingItem
            title="Enable MDBList Integration"
            description="Fetch ratings from multiple sources"
            renderIcon={() => <IconWrap><AnalyticsIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={settings.mdblistEnabled || false}
                onChange={toggleEnabled}
              />
            )}
            isLast
          />
        </SettingsCard>

        {/* API Key */}
        <SettingsCard title="API KEY (REQUIRED)">
          <div className={`p-3.5 space-y-2.5 ${!settings.mdblistEnabled ? 'opacity-50' : ''}`}>
            <input
              type="password"
              value={apiKey}
              onChange={(e) => setApiKey(e.target.value)}
              placeholder="Enter your MDBList API key"
              disabled={!settings.mdblistEnabled}
              className={`
                w-full bg-white/[0.06] border border-white/[0.08] rounded-[10px]
                px-3 py-2.5 text-white text-sm placeholder:text-[#6b7280]
                focus:outline-none focus:ring-2 focus:ring-white/20
                disabled:bg-white/[0.02] disabled:text-[#6b7280]
              `}
            />
            <button
              onClick={saveKey}
              disabled={!settings.mdblistEnabled || !apiKey.trim()}
              className={`
                w-full py-2.5 rounded-[10px] font-bold text-sm
                transition-colors
                ${settings.mdblistEnabled && apiKey.trim()
                  ? 'bg-white text-[#0b0b0d] hover:bg-white/90'
                  : 'bg-white/10 text-[#6b7280] cursor-not-allowed'}
              `}
            >
              Save Key
            </button>
          </div>
          <p className="px-3.5 pb-3 text-[#9ca3af] text-xs">
            MDBList requires your own API key. Get one free at mdblist.com.
          </p>
        </SettingsCard>

        {/* Available Ratings */}
        <SettingsCard title="AVAILABLE RATINGS">
          <div className="flex flex-wrap gap-2 p-3.5">
            {RATING_PROVIDERS.map((provider) => (
              <div
                key={provider.key}
                className="flex items-center gap-2 px-3 py-2 bg-white/[0.04] border border-white/[0.08] rounded-lg"
              >
                <span className="text-[#e5e7eb] text-xs font-medium">{provider.name}</span>
              </div>
            ))}
          </div>
        </SettingsCard>

        {/* Get Your API Key */}
        <SettingsCard title="GET YOUR API KEY">
          <div className="p-3.5 space-y-2.5">
            <div className="flex gap-2">
              <span className="text-[#6b7280] text-sm w-5">1.</span>
              <span className="text-[#e5e7eb] text-sm flex-1">
                Create an account at <span className="text-white font-semibold">mdblist.com</span>
              </span>
            </div>
            <div className="flex gap-2">
              <span className="text-[#6b7280] text-sm w-5">2.</span>
              <span className="text-[#e5e7eb] text-sm flex-1">
                Go to <span className="text-white font-semibold">Settings</span> {'>'} <span className="text-white font-semibold">API</span>
              </span>
            </div>
            <div className="flex gap-2">
              <span className="text-[#6b7280] text-sm w-5">3.</span>
              <span className="text-[#e5e7eb] text-sm flex-1">Copy your API key and paste above</span>
            </div>
            <button
              onClick={() => window.open('https://mdblist.com/preferences/', '_blank')}
              className="flex items-center gap-1.5 mt-2 px-3.5 py-2.5 bg-[#3b82f6]/10 rounded-[10px] text-[#3b82f6] font-semibold text-sm"
            >
              Go to MDBList
              <OpenOutlineIcon size={16} color="#3b82f6" />
            </button>
          </div>
        </SettingsCard>
      </div>
    </div>
  );
}
