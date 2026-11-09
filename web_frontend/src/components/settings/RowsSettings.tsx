import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import SettingsCard from '@/components/SettingsCard';
import SettingItem, { SettingToggle } from '@/components/SettingItem';
import { ChevronBackIcon } from '@/components/ServiceIcons';
import { filterEnabledLibraries, getAllCollections, getPlexLibraries, type PlexCollection } from '@/services/plexCollections';
import {
  CONTINUE_WATCHING_ROW_ID,
  HOME_ROW_KIND_LABEL,
  WATCHLIST_ROW_ID,
  homeRowTitle,
  moveHomeRow,
  orderedHomeRowCatalog,
  renameHomeRow,
  resetHomeRowOrder,
  setHomeRowHidden,
  setHomeRowOrder,
  showAllHomeRows,
  useHomeRowCatalog,
  type HomeRowDescriptor,
} from '@/state/homeRows';
import { getSettings, saveSettings, useSettings, type AppSettings } from '@/state/settings';

export default function RowsSettings() {
  const navigate = useNavigate();
  const settings = useSettings();
  const libraryOnly = settings.discoveryDisabled === true;

  const toggle = (title: string, key: keyof AppSettings, checked: boolean, options: { discovery?: boolean; isLast?: boolean; description?: string } = {}) => (
    <SettingItem
      title={title}
      description={options.discovery && libraryOnly ? 'Disabled by Library Only Mode' : options.description}
      disabled={options.discovery && libraryOnly}
      isLast={options.isLast}
      renderRight={() => (
        <SettingToggle checked={checked} disabled={options.discovery && libraryOnly} onChange={(value) => saveSettings({ [key]: value } as Partial<AppSettings>)} />
      )}
    />
  );

  return (
    <div className="min-h-screen bg-[#0b0b0d] pb-20">
      <div className="px-4 pt-6 pb-4 flex items-center gap-3">
        <button onClick={() => navigate('/settings')} aria-label="Back" className="flex items-center justify-center w-10 h-10 rounded-full hover:bg-white/10 transition-colors">
          <ChevronBackIcon size={24} color="#fff" />
        </button>
        <h1 className="text-white text-xl font-bold">Rows</h1>
      </div>

      <div className="px-4 max-w-2xl mx-auto">
        <SettingsCard title="ROW VISIBILITY">
          {toggle('Continue Watching', 'showContinueWatchingRow', settings.showContinueWatchingRow !== false)}
          {toggle('Watchlist', 'showWatchlistRow', settings.showWatchlistRow)}
          {toggle('Trending', 'showTrendingRows', settings.showTrendingRows !== false, { discovery: true })}
          {toggle('Trakt Rows', 'showTraktRows', settings.showTraktRows !== false, { discovery: true })}
          {toggle('Popular on Plex', 'showPlexPopularRow', settings.showPlexPopularRow !== false, { discovery: true })}
          {toggle('Addon Catalogs', 'showStremioCatalogRows', settings.showStremioCatalogRows, { discovery: true })}
          {toggle('Collections', 'showCollectionRows', settings.showCollectionRows, { description: 'Show Plex collection rows on Home' })}
          {toggle('Group New Episodes', 'groupRecentlyAddedEpisodes', settings.groupRecentlyAddedEpisodes, {
            description: 'Show one card per series in Recently Added',
            isLast: true,
          })}
        </SettingsCard>

        <HeroSourceCard />
        <HomeRowsEditor />
        {settings.showCollectionRows && <CollectionRowsCard />}
      </div>
    </div>
  );
}

function HeroSourceCard() {
  const settings = useSettings();
  const rows = orderedHomeRowCatalog(useHomeRowCatalog(), settings.homeRowOrder).filter(
    (row) => row.id !== CONTINUE_WATCHING_ROW_ID && row.id !== WATCHLIST_ROW_ID,
  );
  const value = settings.homeHeroSource;
  const missing = value.startsWith('row:') && value !== `row:${CONTINUE_WATCHING_ROW_ID}` && value !== `row:${WATCHLIST_ROW_ID}` && !rows.some((row) => `row:${row.id}` === value);

  return (
    <SettingsCard title="HERO">
      <SettingItem
        title="Hero Source"
        description="Falls back to the default when the source is empty"
        isLast
        renderRight={() => (
          <select className="input w-[190px]" aria-label="Hero source" value={value} onChange={(e) => saveSettings({ homeHeroSource: e.target.value })}>
            <option value="default">Default</option>
            <option value="continueWatching">Continue Watching</option>
            <option value="myList">My List</option>
            {rows.map((row) => (
              <option key={row.id} value={`row:${row.id}`}>{homeRowTitle(settings.homeRowTitles, row.id, row.defaultTitle)}</option>
            ))}
            {missing && <option value={value}>Unavailable row</option>}
          </select>
        )}
      />
    </SettingsCard>
  );
}

function HomeRowsEditor() {
  const settings = useSettings();
  const catalog = useHomeRowCatalog();
  const rows = orderedHomeRowCatalog(catalog, settings.homeRowOrder);
  const [dragging, setDragging] = useState<string | null>(null);
  const hiddenCount = rows.filter((row) => settings.homeRowHidden.includes(row.id)).length;

  const dropOn = (targetId: string) => {
    if (!dragging || dragging === targetId) return;
    const ids = rows.map((row) => row.id).filter((id) => id !== dragging);
    ids.splice(ids.indexOf(targetId), 0, dragging);
    setHomeRowOrder(ids);
  };

  return (
    <>
      <div className="flex items-center justify-between mb-2 ml-1">
        <span className="text-[#9ca3af] text-[12px] font-bold tracking-[1px] uppercase">Home Rows</span>
        <div className="flex gap-3">
          {hiddenCount > 0 && <button onClick={showAllHomeRows} className="text-xs text-[#9ca3af] hover:text-white">Show All</button>}
          <button onClick={resetHomeRowOrder} disabled={settings.homeRowOrder.length === 0} className="text-xs text-[#9ca3af] hover:text-white disabled:opacity-40">
            Reset to Default Order
          </button>
        </div>
      </div>
      <SettingsCard>
        {rows.length === 0 ? (
          <p className="px-[14px] py-6 text-[#9ca3af] text-[13px]">Your rows appear here once the Home screen has loaded.</p>
        ) : (
          rows.map((row, index) => (
            <HomeRowEditorRow
              key={row.id}
              row={row}
              isFirst={index === 0}
              isLast={index === rows.length - 1}
              onDragStart={() => setDragging(row.id)}
              onDragEnd={() => setDragging(null)}
              onDrop={() => dropOn(row.id)}
            />
          ))
        )}
      </SettingsCard>
      <p className="text-[#9ca3af] text-xs -mt-3 mb-[18px] px-1">
        Drag to reorder. Rows you turn off stay here so you can bring them back. New rows appear next to where they would normally be.
      </p>
    </>
  );
}

function HomeRowEditorRow({
  row,
  isFirst,
  isLast,
  onDragStart,
  onDragEnd,
  onDrop,
}: {
  row: HomeRowDescriptor;
  isFirst: boolean;
  isLast: boolean;
  onDragStart: () => void;
  onDragEnd: () => void;
  onDrop: () => void;
}) {
  const settings = useSettings();
  const [renaming, setRenaming] = useState(false);
  const [draft, setDraft] = useState('');
  const title = homeRowTitle(settings.homeRowTitles, row.id, row.defaultTitle);
  const custom = settings.homeRowTitles[row.id];
  const isContinue = row.id === CONTINUE_WATCHING_ROW_ID;
  const visible = isContinue ? settings.showContinueWatchingRow !== false : !settings.homeRowHidden.includes(row.id);
  const subtitle = [row.detail || HOME_ROW_KIND_LABEL[row.kind], custom ? `Originally "${row.defaultTitle}"` : undefined].filter(Boolean).join(' · ');

  const commit = () => {
    renameHomeRow(row.id, draft, row.defaultTitle);
    setRenaming(false);
  };

  return (
    <div
      draggable={!renaming}
      onDragStart={onDragStart}
      onDragEnd={onDragEnd}
      onDragOver={(event) => event.preventDefault()}
      onDrop={(event) => {
        event.preventDefault();
        onDrop();
      }}
      className={`flex items-center gap-2 px-[14px] py-2 ${isLast ? '' : 'border-b border-white/[0.06]'}`}
    >
      <span className="text-[#6b7280] cursor-grab select-none" aria-hidden>≡</span>
      <div className="flex-1 min-w-0">
        {renaming ? (
          <input
            autoFocus
            className="input w-full"
            aria-label={`Rename ${title}`}
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') commit();
              if (e.key === 'Escape') setRenaming(false);
            }}
            onBlur={commit}
          />
        ) : (
          <>
            <span className={`block text-[14px] font-semibold truncate ${visible ? 'text-[#f9fafb]' : 'text-[#6b7280]'}`}>{title}</span>
            <span className="block text-[12px] text-[#9ca3af] truncate">{subtitle}</span>
          </>
        )}
      </div>
      {!renaming && (
        <button
          className="px-2 py-1 text-xs text-[#9ca3af] hover:text-white"
          onClick={() => {
            setDraft(title);
            setRenaming(true);
          }}
          aria-label={`Rename ${title}`}
        >
          Rename
        </button>
      )}
      <button className="px-1.5 py-1 text-[#9ca3af] hover:text-white disabled:opacity-30" disabled={isFirst} onClick={() => moveHomeRow(row.id, -1)} aria-label={`Move ${title} up`}>↑</button>
      <button className="px-1.5 py-1 text-[#9ca3af] hover:text-white disabled:opacity-30" disabled={isLast} onClick={() => moveHomeRow(row.id, 1)} aria-label={`Move ${title} down`}>↓</button>
      <SettingToggle
        checked={visible}
        onChange={(value) => {
          if (isContinue) saveSettings({ showContinueWatchingRow: value });
          else setHomeRowHidden(row.id, !value);
        }}
      />
    </div>
  );
}

function CollectionRowsCard() {
  const settings = useSettings();
  const [collections, setCollections] = useState<PlexCollection[] | null>(null);
  const [error, setError] = useState('');

  useEffect(() => {
    let alive = true;
    getPlexLibraries()
      .then((libraries) => getAllCollections(filterEnabledLibraries(libraries, getSettings().enabledLibraryKeys)))
      .then((list) => alive && setCollections(list.sort((a, b) => b.count - a.count)))
      .catch((e: any) => alive && setError(e?.message || 'Could not load collections'));
    return () => {
      alive = false;
    };
  }, []);

  const setVisible = (key: string, visible: boolean) => {
    const next = new Set(getSettings().hiddenCollectionKeys);
    if (visible) next.delete(key);
    else next.add(key);
    saveSettings({ hiddenCollectionKeys: Array.from(next) });
  };

  return (
    <SettingsCard title="COLLECTION ROWS">
      {error ? (
        <p className="px-[14px] py-6 text-[#9ca3af] text-[13px]">{error}</p>
      ) : !collections ? (
        <p className="px-[14px] py-6 text-[#9ca3af] text-[13px]">Loading collections…</p>
      ) : collections.length === 0 ? (
        <p className="px-[14px] py-6 text-[#9ca3af] text-[13px]">No Plex collections found.</p>
      ) : (
        collections.map((collection, index) => (
          <SettingItem
            key={collection.ratingKey}
            title={collection.title}
            description={`${collection.count} ${collection.count === 1 ? 'title' : 'titles'} · ${collection.libraryTitle}`}
            isLast={index === collections.length - 1}
            renderRight={() => (
              <SettingToggle checked={!settings.hiddenCollectionKeys.includes(collection.ratingKey)} onChange={(value) => setVisible(collection.ratingKey, value)} />
            )}
          />
        ))
      )}
    </SettingsCard>
  );
}
