import React, { useMemo, useRef } from 'react';
import { useIsFocused } from '@react-navigation/native';
import TopAppBar from './TopAppBar';
import { useTopBarStore, TopBarStore } from './TopBarStore';

type Props = {
  screenContext?: 'HomeStack' | 'NewHot' | 'MyList';
  /**
   * Rendered inside a screen rather than above the whole stack, so the header slides with
   * its screen during push and pop (and swipe-back) instead of vanishing and popping back.
   * While its screen is covered it keeps showing that screen's own state.
   */
  embedded?: boolean;
};

export default function GlobalTopAppBar({ screenContext, embedded }: Props) {
  const isFocused = useIsFocused();
  const storeVisible = useTopBarStore((st) => st.visible === true);
  const baseUsername = useTopBarStore((st) => st.baseUsername);
  const showFilters = useTopBarStore((st) => st.showFilters === true);
  const selected = useTopBarStore((st) => st.selected);
  const onClose = useTopBarStore((st) => st.onClose);
  const onNavigateLibrary = useTopBarStore((st) => st.onNavigateLibrary);
  const onBrowse = useTopBarStore((st) => st.onBrowse);
  const onClearGenre = useTopBarStore((st) => st.onClearGenre);
  const onSelectCategory = useTopBarStore((st) => st.onSelectCategory);
  const compact = useTopBarStore((st) => st.compact === true);
  const customFilters = useTopBarStore((st) => st.customFilters);
  const activeGenre = useTopBarStore((st) => st.activeGenre);
  const customPillLabel = useTopBarStore((st) => st.customPillLabel);

  // Re-render only when the scrollY reference changes (screen switch)
  const liveScrollY = useTopBarStore((st) => st.scrollY);

  const live = {
    visible: embedded ? true : storeVisible,
    showFilters, selected, onClose, onNavigateLibrary, onBrowse, onClearGenre, onSelectCategory,
    compact, customFilters, activeGenre, customPillLabel, scrollY: liveScrollY,
  };
  const frozen = useRef(live);
  if (!embedded || isFocused) frozen.current = live;
  const view = frozen.current;

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
  const isCompact = screenContext === 'NewHot' ? true : view.compact;

  return (
    <TopAppBar
      visible={view.visible}
      username={displayTitle}
      showFilters={view.showFilters}
      selected={view.selected}
      onChange={(t)=> TopBarStore.setSelected(t)}
      onOpenCategories={view.onBrowse || (()=>{})}
      onSelectCategory={view.onSelectCategory}
      onNavigateLibrary={view.onNavigateLibrary}
      onClose={view.onClose}
      scrollY={view.scrollY}
      compact={isCompact}
      customFilters={view.customFilters}
      activeGenre={view.activeGenre}
      onClearGenre={view.onClearGenre}
      customPillLabel={view.customPillLabel}
      onHeightChange={(h)=> { if (!embedded || isFocused) TopBarStore.setHeight(h); }}
    />
  );
}
