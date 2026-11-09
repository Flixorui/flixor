import { useState } from 'react';
import FloatingNavTrack from '@/components/nav/FloatingNavTrack';
import { NAV_ITEMS, type NavItem } from '@/components/nav/navItems';
import SettingsCard from '@/components/SettingsCard';
import SettingItem, { SettingSegmentedControl, SettingToggle } from '@/components/SettingItem';
import SettingsScreen from '@/components/settings/SettingsScreen';
import { type NavigationBarStyle, type NavigationStyle, saveSettings, useSettings } from '@/state/settings';

const PREVIEW_ITEMS = NAV_ITEMS.filter((item) => ['home', 'search', 'library'].includes(item.id));

/** Live example of the bar. Click a tab to try it. */
function FloatingNavPreview() {
  const { navigationBarStyle, navigationBarGlow } = useSettings();
  const [selected, setSelected] = useState<NavItem['id']>('home');
  const [hovered, setHovered] = useState(false);
  const showsLabels = navigationBarStyle === 'expanded' || (navigationBarStyle === 'adaptive' && hovered);

  return (
    <div
      className="flex justify-center py-5 rounded-xl"
      style={{ background: 'linear-gradient(to bottom, rgb(var(--accent-rgb) / 0.35), #0a0a0a)' }}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
    >
      <FloatingNavTrack
        items={PREVIEW_ITEMS}
        selectedId={selected}
        showsLabels={showsLabels}
        isFrosted={hovered}
        glowEnabled={navigationBarGlow}
        onSelect={(item) => setSelected(item.id)}
      />
    </div>
  );
}

export default function NavigationSettings() {
  const { navigationStyle, navigationSidebarPinned, navigationBarStyle, navigationBarGlow, showNewPopularTab, discoveryDisabled } =
    useSettings();
  const usesSidebar = navigationStyle === 'sidebar';

  return (
    <SettingsScreen title="Navigation">
      <SettingsCard title="NAVIGATION STYLE">
        <SettingItem
          title="Navigation Style"
          description="Show tabs in the top bar or in a sidebar"
          renderRight={() => (
            <SettingSegmentedControl<NavigationStyle>
              value={navigationStyle}
              options={[
                { value: 'topBar', label: 'Top Bar' },
                { value: 'sidebar', label: 'Sidebar' },
              ]}
              onChange={(value) => saveSettings({ navigationStyle: value })}
            />
          )}
        />
        {usesSidebar ? (
          <SettingItem
            title="Keep Sidebar Expanded"
            description="Always show labels instead of expanding on hover"
            renderRight={() => (
              <SettingToggle
                checked={navigationSidebarPinned}
                onChange={(v) => saveSettings({ navigationSidebarPinned: v })}
              />
            )}
            isLast
          />
        ) : (
          <>
            <SettingItem
              title="Bar Style"
              description="How the bar shows its labels"
              renderRight={() => (
                <SettingSegmentedControl<NavigationBarStyle>
                  value={navigationBarStyle}
                  options={[
                    { value: 'adaptive', label: 'Adaptive' },
                    { value: 'expanded', label: 'Expanded' },
                    { value: 'compact', label: 'Compact' },
                  ]}
                  onChange={(value) => saveSettings({ navigationBarStyle: value })}
                />
              )}
            />
            <SettingItem
              title="Glass Glow"
              description="Adds soft light around the selected tab"
              renderRight={() => (
                <SettingToggle checked={navigationBarGlow} onChange={(v) => saveSettings({ navigationBarGlow: v })} />
              )}
            />
            <div className="p-3">
              <FloatingNavPreview />
            </div>
          </>
        )}
      </SettingsCard>

      <SettingsCard title="TABS">
        <SettingItem
          title="New & Popular Tab"
          description={discoveryDisabled ? 'Disabled by Library Only Mode' : 'Show New & Popular tab in navigation'}
          disabled={discoveryDisabled === true}
          renderRight={() => (
            <SettingToggle
              checked={discoveryDisabled !== true && showNewPopularTab !== false}
              disabled={discoveryDisabled === true}
              onChange={(v) => saveSettings({ showNewPopularTab: v })}
            />
          )}
          isLast
        />
      </SettingsCard>
      <p className="px-1 text-[12px] text-[#9ca3af]">
        On narrow screens the tabs move to a bar at the bottom, whichever style is chosen.
      </p>
    </SettingsScreen>
  );
}
