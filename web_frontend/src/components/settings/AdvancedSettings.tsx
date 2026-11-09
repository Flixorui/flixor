import { useNavigate } from 'react-router-dom';
import { useState } from 'react';
import { ChevronForwardIcon } from '@/components/ServiceIcons';
import SettingsCard from '@/components/SettingsCard';
import SettingItem, { SettingButton, SettingToggle } from '@/components/SettingItem';
import SettingsScreen from '@/components/settings/SettingsScreen';
import { apiClient } from '@/services/api';
import { forget } from '@/services/cache';
import { showToast } from '@/services/toast';
import { saveSettings, useSettings } from '@/state/settings';

export default function AdvancedSettings() {
  const navigate = useNavigate();
  const { debugLoggingEnabled } = useSettings();
  const [clearing, setClearing] = useState(false);

  async function clearCache() {
    setClearing(true);
    forget('');
    try {
      await apiClient.flushCache();
      showToast('Cached data cleared', 'success');
    } catch {
      showToast('Cleared this browser, but the server cache could not be cleared', 'error');
    } finally {
      setClearing(false);
    }
  }

  return (
    <SettingsScreen title="Advanced">
      <SettingsCard title="DIAGNOSTICS">
        <SettingItem
          title="Debug Logging"
          description="Capture console output for troubleshooting"
          renderRight={() => (
            <SettingToggle checked={debugLoggingEnabled} onChange={(v) => saveSettings({ debugLoggingEnabled: v })} />
          )}
        />
        <SettingItem
          title="View Logs"
          description="Recent entries from this tab"
          renderRight={() => <ChevronForwardIcon size={18} color="#9ca3af" />}
          onClick={() => navigate('/settings/advanced/logs')}
          isLast
        />
      </SettingsCard>

      <SettingsCard title="STORAGE">
        <SettingItem
          title="Clear Cached Data"
          description="Reloads library and metadata the next time they are needed"
          renderRight={() => (
            <SettingButton onClick={clearCache} loading={clearing}>
              Clear
            </SettingButton>
          )}
          isLast
        />
      </SettingsCard>
    </SettingsScreen>
  );
}
