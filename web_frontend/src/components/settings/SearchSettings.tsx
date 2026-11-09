import { useNavigate } from 'react-router-dom';
import SettingsCard from '@/components/SettingsCard';
import SettingItem, { SettingToggle } from '@/components/SettingItem';
import { ChevronBackIcon } from '@/components/ServiceIcons';
import { saveSettings, useSettings, type SearchIdleTab } from '@/state/settings';

export default function SearchSettings() {
  const navigate = useNavigate();
  const settings = useSettings();
  const libraryOnly = settings.discoveryDisabled === true;
  const includeTmdb = settings.includeTmdbInSearch !== false;

  return (
    <div className="min-h-screen pb-20">
      <div className="px-4 pt-6 pb-4 max-w-2xl mx-auto flex items-center gap-3">
        <button onClick={() => navigate('/settings')} aria-label="Back" className="-ml-2 flex items-center justify-center w-10 h-10 rounded-full hover:bg-white/10 transition-colors">
          <ChevronBackIcon size={24} color="#fff" />
        </button>
        <h1 className="text-white text-xl font-bold">Search</h1>
      </div>

      <div className="px-4 max-w-2xl mx-auto">
        <SettingsCard title="SOURCES">
          <SettingItem
            title="Search TMDB"
            description={libraryOnly ? 'Disabled by Library Only Mode' : 'Include titles and people that are not in your library'}
            disabled={libraryOnly}
            renderRight={() => (
              <SettingToggle checked={includeTmdb && !libraryOnly} disabled={libraryOnly} onChange={(includeTmdbInSearch) => saveSettings({ includeTmdbInSearch })} />
            )}
          />
          <SettingItem
            title="Search Addon Catalogs"
            description={libraryOnly ? 'Disabled by Library Only Mode' : 'Include results from installed Stremio addons'}
            disabled={libraryOnly}
            renderRight={() => (
              <SettingToggle
                checked={settings.stremioCatalogSearchEnabled && !libraryOnly}
                disabled={libraryOnly}
                onChange={(stremioCatalogSearchEnabled) => saveSettings({ stremioCatalogSearchEnabled })}
              />
            )}
            isLast
          />
        </SettingsCard>

        {includeTmdb && !libraryOnly && (
          <SettingsCard title="WHEN THE SEARCH FIELD IS EMPTY">
            <div className="flex gap-2 p-[14px]">
              {(['explore', 'discover'] as SearchIdleTab[]).map((tab) => (
                <button
                  key={tab}
                  onClick={() => saveSettings({ searchIdleTab: tab })}
                  className={`flex-1 py-3 rounded-[10px] border text-[14px] font-semibold transition-all ${
                    settings.searchIdleTab === tab ? 'bg-white border-white text-[#111827]' : 'bg-white/[0.04] border-white/[0.12] text-[#9ca3af] hover:text-white'
                  }`}
                >
                  {tab === 'explore' ? 'Explore' : 'Discover'}
                </button>
              ))}
            </div>
          </SettingsCard>
        )}

        <SettingsCard title="HISTORY">
          <SettingItem
            title="Clear Recent Searches"
            description={settings.recentSearches.length ? `${settings.recentSearches.length} saved` : 'Nothing saved'}
            disabled={settings.recentSearches.length === 0}
            onClick={() => saveSettings({ recentSearches: [] })}
            isLast
          />
        </SettingsCard>
      </div>
    </div>
  );
}
