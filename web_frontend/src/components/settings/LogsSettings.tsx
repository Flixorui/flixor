import { useMemo, useState, useSyncExternalStore } from 'react';
import SettingsCard from '@/components/SettingsCard';
import { SettingButton } from '@/components/SettingItem';
import SettingsScreen from '@/components/settings/SettingsScreen';
import {
  clearLogEntries,
  formatLogEntries,
  getLogEntries,
  type LogLevel,
  subscribeLogs,
} from '@/services/logger';
import { showToast } from '@/services/toast';
import { useSettings } from '@/state/settings';

const LEVELS: Array<LogLevel | 'all'> = ['all', 'debug', 'info', 'warn', 'error'];

const LEVEL_STYLES: Record<LogLevel, string> = {
  debug: 'text-neutral-400 bg-white/5',
  info: 'text-sky-300 bg-sky-500/10',
  warn: 'text-amber-300 bg-amber-500/10',
  error: 'text-red-300 bg-red-500/10',
};

export default function LogsSettings() {
  const entries = useSyncExternalStore(subscribeLogs, getLogEntries, getLogEntries);
  const { debugLoggingEnabled } = useSettings();
  const [level, setLevel] = useState<LogLevel | 'all'>('all');
  const [query, setQuery] = useState('');

  const visible = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return entries
      .filter((e) => (level === 'all' || e.level === level) && (!needle || e.message.toLowerCase().includes(needle)))
      .reverse();
  }, [entries, level, query]);

  async function copy() {
    try {
      await navigator.clipboard.writeText(formatLogEntries(visible));
      showToast('Logs copied', 'success');
    } catch {
      showToast('Could not copy logs', 'error');
    }
  }

  function download() {
    const url = URL.createObjectURL(new Blob([formatLogEntries(visible)], { type: 'text/plain' }));
    const link = document.createElement('a');
    link.href = url;
    link.download = `flixor-logs-${new Date().toISOString().replace(/[:.]/g, '-')}.txt`;
    link.click();
    URL.revokeObjectURL(url);
  }

  function clear() {
    if (window.confirm('Clear all logs?')) clearLogEntries();
  }

  return (
    <SettingsScreen title="Logs" backTo="/settings/advanced">
      <div className="flex flex-wrap items-center gap-2 mb-3">
        <span className="text-[13px] text-[#9ca3af] mr-auto">
          {visible.length === entries.length ? `${entries.length} entries` : `${visible.length} of ${entries.length} entries`}
        </span>
        <SettingButton onClick={copy} disabled={visible.length === 0}>Copy</SettingButton>
        <SettingButton onClick={download} disabled={visible.length === 0}>Download</SettingButton>
        <SettingButton variant="danger" onClick={clear} disabled={entries.length === 0}>Clear</SettingButton>
      </div>

      <div className="flex flex-wrap gap-2 mb-3">
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Filter messages"
          aria-label="Filter messages"
          className="input flex-1 min-w-[10rem] select-text"
        />
        <select
          value={level}
          onChange={(e) => setLevel(e.target.value as LogLevel | 'all')}
          aria-label="Level"
          className="input capitalize"
        >
          {LEVELS.map((l) => (
            <option key={l} value={l}>
              {l === 'all' ? 'All levels' : l}
            </option>
          ))}
        </select>
      </div>

      <SettingsCard>
        {visible.length === 0 ? (
          <div className="px-[14px] py-10 text-center">
            <p className="text-[#f9fafb] text-[15px] font-semibold">{entries.length === 0 ? 'No logs yet' : 'No matching logs'}</p>
            {entries.length === 0 && !debugLoggingEnabled && (
              <p className="mt-1 text-[12px] text-[#9ca3af]">Turn on Debug Logging to capture detailed logs</p>
            )}
          </div>
        ) : (
          <ul className="max-h-[60vh] overflow-auto divide-y divide-white/[0.06] select-text">
            {visible.map((entry) => (
              <li key={entry.id} className="px-[14px] py-2 font-mono text-[12px] leading-5">
                <div className="flex items-center gap-2">
                  <span className="text-neutral-500">{new Date(entry.timestamp).toLocaleTimeString()}</span>
                  <span className={`px-1.5 rounded text-[10px] font-bold uppercase ${LEVEL_STYLES[entry.level]}`}>{entry.level}</span>
                </div>
                <p className="text-neutral-200 whitespace-pre-wrap break-words">{entry.message}</p>
              </li>
            ))}
          </ul>
        )}
      </SettingsCard>

      <p className="px-1 text-[12px] text-[#9ca3af]">
        Logs stay in memory for this tab and are cleared when it reloads. Tokens, passwords and PINs are removed
        automatically.
      </p>
    </SettingsScreen>
  );
}
