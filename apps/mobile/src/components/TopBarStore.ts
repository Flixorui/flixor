import { Animated } from 'react-native';
import React from 'react';

type Pill = 'all'|'movies'|'shows';

type State = {
  visible: boolean;
  tabBarVisible: boolean;
  username?: string;
  baseUsername?: string; // Set once when user data loads, used for stable title display
  showFilters: boolean;
  selected: Pill;
  scrollY?: Animated.Value;
  onNavigateLibrary?: (tab: 'movies'|'shows')=>void;
  onClose?: ()=>void;
  onBrowse?: ()=>void;
  onClearGenre?: ()=>void;
  compact?: boolean;
  customFilters?: React.ReactNode;
  activeGenre?: string;
  height: number;
};

type Listener = () => void;

const state: State = {
  visible: true,
  tabBarVisible: true,
  username: undefined,
  baseUsername: undefined,
  showFilters: true, // default to true so pills are visible
  selected: 'all',
  scrollY: undefined,
  onNavigateLibrary: undefined,
  onClose: undefined,
  onBrowse: undefined,
  onClearGenre: undefined,
  compact: false,
  customFilters: undefined,
  activeGenre: undefined,
  height: 90,
};

const listeners = new Set<Listener>();

function emit() { listeners.forEach(l => l()); }

export const TopBarStore = {
  subscribe(fn: Listener) { listeners.add(fn); return () => listeners.delete(fn); },
  getState(): State { return state; },
  setState(next: Partial<State>) {
    let changed = false;
    (Object.keys(next) as Array<keyof State>).forEach((key) => {
      const value = next[key];
      if (state[key] !== value) {
        (state as any)[key] = value;
        changed = true;
      }
    });
    if (changed) emit();
  },
  setVisible(v: boolean) { if (state.visible !== v) { state.visible = v; emit(); } },
  setTabBarVisible(v: boolean) { if (state.tabBarVisible !== v) { state.tabBarVisible = v; emit(); } },
  setUsername(u?: string) { if (state.username !== u) { state.username = u; emit(); } },
  setBaseUsername(u?: string) { if (state.baseUsername !== u) { state.baseUsername = u; emit(); } },
  setShowFilters(v: boolean) { if (state.showFilters !== v) { state.showFilters = v; emit(); } },
  setSelected(p: Pill) { if (state.selected !== p) { state.selected = p; emit(); } },
  setCompact(v: boolean) { if (state.compact !== v) { state.compact = v; emit(); } },
  setCustomFilters(v?: React.ReactNode) { if (state.customFilters !== v) { state.customFilters = v; emit(); } },
  setActiveGenre(v?: string) { if (state.activeGenre !== v) { state.activeGenre = v; emit(); } },
  setScrollY(y?: Animated.Value) {
    if (state.scrollY !== y) {
      state.scrollY = y;
      emit();
    }
  },
  setHandlers(h: { onNavigateLibrary?: (tab:'movies'|'shows')=>void; onClose?: ()=>void; onBrowse?: ()=>void; onClearGenre?: ()=>void }) {
    let changed = false;
    if (state.onNavigateLibrary !== h.onNavigateLibrary) { state.onNavigateLibrary = h.onNavigateLibrary; changed = true; }
    if (state.onClose !== h.onClose) { state.onClose = h.onClose; changed = true; }
    if (state.onBrowse !== h.onBrowse) { state.onBrowse = h.onBrowse; changed = true; }
    if (state.onClearGenre !== h.onClearGenre) { state.onClearGenre = h.onClearGenre; changed = true; }
    if (changed) emit();
  },
  setHeight(h: number) { if (state.height !== h) { state.height = h; emit(); } },
  navigateLibrary(tab: 'movies'|'shows') {
    state.onNavigateLibrary && state.onNavigateLibrary(tab);
  },
};

export function useTopBarStore<T>(selector: (s: State) => T): T {
  return React.useSyncExternalStore(TopBarStore.subscribe, () => selector(TopBarStore.getState()), () => selector(TopBarStore.getState()));
}
