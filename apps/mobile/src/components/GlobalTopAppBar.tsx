import React, { useMemo } from 'react';
import TopAppBar from './TopAppBar';
import { useTopBarStore, TopBarStore } from './TopBarStore';

type Props = {
  screenContext?: 'HomeStack' | 'NewHot' | 'MyList';
};

export default function GlobalTopAppBar({ screenContext }: Props) {
  const visible = useTopBarStore((st) => st.visible === true);
  const baseUsername = useTopBarStore((st) => st.baseUsername);
  const showFilters = useTopBarStore((st) => st.showFilters === true);
  const selected = useTopBarStore((st) => st.selected);
  const onClose = useTopBarStore((st) => st.onClose);
  const onNavigateLibrary = useTopBarStore((st) => st.onNavigateLibrary);
  const onSearch = useTopBarStore((st) => st.onSearch);
  const onBrowse = useTopBarStore((st) => st.onBrowse);
  const onClearGenre = useTopBarStore((st) => st.onClearGenre);
  const compact = useTopBarStore((st) => st.compact === true);
  const customFilters = useTopBarStore((st) => st.customFilters);
  const activeGenre = useTopBarStore((st) => st.activeGenre);

  // Read scrollY and showPills directly from store (don't cause re-renders)
  const scrollY = TopBarStore.getState().scrollY;
  const showPills = TopBarStore.getState().showPills;

  // Derive title INSTANTLY from screenContext - no useFocusEffect delay
  // Return just the username - TopAppBar will add "For " prefix when compact=false
  const displayTitle = useMemo(() => {
    switch (screenContext) {
      case 'NewHot':
        return 'New & Hot'; // Will be displayed as-is because compact=true for NewHot
      case 'MyList':
        return baseUsername || 'You'; // Will become "For {username}"
      case 'HomeStack':
      default:
        return baseUsername || 'You'; // Will become "For {username}"
    }
  }, [screenContext, baseUsername]);

  // NewHot uses compact mode (no "For" prefix)
  const isCompact = screenContext === 'NewHot' ? true : compact;

  return (
    <TopAppBar
      visible={visible}
      username={displayTitle}
      showFilters={showFilters}
      selected={selected}
      onChange={(t)=> TopBarStore.setSelected(t)}
      onOpenCategories={onBrowse || (()=>{})}
      onNavigateLibrary={onNavigateLibrary}
      onClose={onClose}
      onSearch={onSearch}
      scrollY={scrollY}
      showPills={showPills}
      compact={isCompact}
      customFilters={customFilters}
      activeGenre={activeGenre}
      onClearGenre={onClearGenre}
      onHeightChange={(h)=> TopBarStore.setHeight(h)}
    />
  );
}

