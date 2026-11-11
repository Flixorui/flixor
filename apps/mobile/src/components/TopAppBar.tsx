import React from 'react';
import { Animated, Easing, View, Text, StyleSheet, LayoutAnimation, UIManager, Platform, Pressable, Image } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useNavigation } from '@react-navigation/native';
import ConditionalBlurView from './ConditionalBlurView';
import Pills from './Pills';
import type { CategoryPick } from './CategoriesMenu';
import { TopBarStore } from './TopBarStore';
import {
  TOP_BAR_BASE_HEIGHT,
  TOP_BAR_COLLAPSED_CONTENT_HEIGHT,
  TOP_BAR_EXPANDED_CONTENT_HEIGHT,
  TOP_BAR_PILLS_AREA_HEIGHT,
} from './topBarMetrics';
import { useTheme } from '../hooks/useTheme';
import { useAppSetting } from '../hooks/useAppSettings';

if (Platform.OS === 'android') {
  UIManager.setLayoutAnimationEnabledExperimental?.(true);
}

/*
 * Pill-row motion, measured frame by frame from the Netflix iOS app (Nov 2026):
 * - Hide after a small downward scroll: pills scale to 0.9, rise 6 pt and fade in ~180 ms,
 *   while the frosted band shrinks to the title row.
 * - A small nudge up is ignored; a deliberate upward scroll (or reaching the top) brings
 *   them back in ~250 ms, anywhere on the page.
 * - The title row shrinks ~6.5% while the pills are hidden (title toward the left edge,
 *   icons toward the right edge, lifted ~1.3 pt): 340 ms out, 400 ms back with a soft settle.
 * Time-based, not tied to the scroll position, so it plays the same at any scroll speed.
 */
const HIDE_AFTER = 8; // pt of downward scroll
const SHOW_AFTER = 60; // pt of upward scroll
const TOP_ZONE = 8; // pt from the top where the pills always show
const PILLS_HIDE = { duration: 180, easing: Easing.bezier(0.4, 0, 0.2, 1) };
const PILLS_SHOW = { duration: 250, easing: Easing.bezier(0.2, 0.8, 0.2, 1) };
const TITLE_HIDE = { duration: 340, easing: Easing.bezier(0.33, 0, 0.2, 1) };
const TITLE_SHOW = { duration: 400, easing: Easing.bezier(0.16, 1, 0.3, 1) };

function TopAppBar({ visible, username, showFilters, selected, onChange, onOpenCategories, onSelectCategory, onNavigateLibrary, onClose, scrollY, onHeightChange, compact, customFilters, activeGenre, onClearGenre, customPillLabel }: {
  visible: boolean;
  username?: string;
  showFilters?: boolean;
  selected?: 'all'|'movies'|'shows';
  onChange?: (t:'all'|'movies'|'shows')=>void;
  onOpenCategories?: ()=>void;
  onSelectCategory?: (pick: CategoryPick)=>void;
  onNavigateLibrary?: (tab: 'movies'|'shows')=>void;
  onClose?: ()=>void;
  scrollY?: Animated.Value;
  onHeightChange?: (h:number)=>void;
  compact?: boolean; // Smaller header for screens like NewHot
  customFilters?: React.ReactNode; // Custom filter content (e.g., tab pills for NewHot)
  activeGenre?: string;
  onClearGenre?: ()=>void;
  customPillLabel?: string; // Custom label for pill when browsing specific library
}) {
  const insets = useSafeAreaInsets();
  const navigation = useNavigation<any>();
  const theme = useTheme();
  const barStyle = useAppSetting('topBarStyle');

  const collapsedHeight = insets.top + TOP_BAR_COLLAPSED_CONTENT_HEIGHT;
  const expandedHeight = insets.top + TOP_BAR_EXPANDED_CONTENT_HEIGHT;
  const headerHeight = (showFilters || customFilters) ? expandedHeight : collapsedHeight;
  const pillsAreaHeight = TOP_BAR_PILLS_AREA_HEIGHT;

  const fallbackOpacity = React.useRef(new Animated.Value(0)).current;

  // Expanded keeps the pills on screen. Adaptive hides them on scroll down and returns
  // them on a deliberate scroll up. Compact hides them on scroll and returns them only at the top.
  const canCollapse = !!scrollY && !!showFilters && !customFilters && barStyle !== 'expanded';

  // 0 = pills shown, 1 = hidden. Two native-driven values (pills and the slower title row)
  // and one JS-driven value for the frosted band's height.
  const pillsP = React.useRef(new Animated.Value(0)).current;
  const titleP = React.useRef(new Animated.Value(0)).current;
  const bandP = React.useRef(new Animated.Value(0)).current;
  const [pillsHidden, setPillsHidden] = React.useState(false);
  const hiddenRef = React.useRef(false);

  const setHidden = React.useCallback((hide: boolean) => {
    if (hiddenRef.current === hide) return;
    hiddenRef.current = hide;
    setPillsHidden(hide);
    const to = hide ? 1 : 0;
    const pills = hide ? PILLS_HIDE : PILLS_SHOW;
    const title = hide ? TITLE_HIDE : TITLE_SHOW;
    Animated.parallel([
      Animated.timing(pillsP, { toValue: to, ...pills, useNativeDriver: true }),
      Animated.timing(titleP, { toValue: to, ...title, useNativeDriver: true }),
      Animated.timing(bandP, { toValue: to, ...pills, useNativeDriver: false }),
    ]).start();
  }, [pillsP, titleP, bandP]);

  React.useEffect(() => {
    if (!canCollapse || !scrollY) {
      setHidden(false);
      return;
    }
    let lastY = 0;
    let down = 0;
    let up = 0;
    const id = scrollY.addListener(({ value: y }) => {
      const delta = y - lastY;
      lastY = y;
      if (y <= TOP_ZONE) {
        down = 0;
        up = 0;
        setHidden(false);
        return;
      }
      if (delta > 0) {
        down += delta;
        up = 0;
        if (down >= HIDE_AFTER) setHidden(true);
      } else if (delta < 0) {
        up -= delta;
        down = 0;
        if (barStyle === 'adaptive' && up >= SHOW_AFTER) setHidden(false);
      }
    });
    return () => scrollY.removeListener(id);
  }, [canCollapse, scrollY, barStyle, setHidden]);

  const pillsOpacity = pillsP.interpolate({ inputRange: [0, 1], outputRange: [1, 0] });
  const pillsScale = pillsP.interpolate({ inputRange: [0, 1], outputRange: [1, 0.9] });
  const pillsTranslateY = pillsP.interpolate({ inputRange: [0, 1], outputRange: [0, -6] });
  const titleScale = titleP.interpolate({ inputRange: [0, 1], outputRange: [1, 0.935] });
  const iconsScale = titleP.interpolate({ inputRange: [0, 1], outputRange: [1, 0.93] });
  const titleShift = titleP.interpolate({ inputRange: [0, 1], outputRange: [0, -1.3] });

  const blurHeight = canCollapse
    ? bandP.interpolate({ inputRange: [0, 1], outputRange: [expandedHeight, collapsedHeight] })
    : headerHeight;

  const backgroundOpacity = React.useMemo(() => {
    if (!scrollY) return fallbackOpacity;
    return scrollY.interpolate({ inputRange: [0, 8, 120], outputRange: [0, 0, 1], extrapolate: 'clamp' });
  }, [scrollY, fallbackOpacity]);

  const separatorOpacity = React.useMemo(() => {
    if (!scrollY) return fallbackOpacity;
    return scrollY.interpolate({ inputRange: [0, 8, 120], outputRange: [0, 0, 0.08], extrapolate: 'clamp' });
  }, [scrollY, fallbackOpacity]);

  React.useEffect(() => {
    onHeightChange?.(headerHeight);
  }, [headerHeight, onHeightChange]);

  const handleOpenDownloads = React.useCallback(() => {
    // Walk up the navigator tree to find the tabs navigator
    let current: any = navigation;
    while (current) {
      const state = current.getState?.();
      if (state?.routeNames?.includes('DownloadsTab')) {
        current.navigate('DownloadsTab');
        return;
      }
      current = current.getParent?.();
    }

    // If the downloads tab is hidden, fall back to the root Downloads screen
    current = navigation;
    while (current) {
      const state = current.getState?.();
      if (state?.routeNames?.includes('Downloads')) {
        current.navigate('Downloads');
        return;
      }
      current = current.getParent?.();
    }

    navigation.navigate('Downloads');
  }, [navigation]);

  return (
    <Animated.View
      pointerEvents={visible ? 'box-none' : 'none'}
      style={{ position: 'absolute', top: 0, left: 0, right: 0, zIndex: 20, height: headerHeight, overflow: 'hidden' }}
    >
      {/* Unified frosted background to avoid hard edges between sections */}
      <Animated.View
        pointerEvents="none"
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          top: 0,
          height: blurHeight,
          opacity: backgroundOpacity,
          overflow: 'hidden',
        }}
      >
        <ConditionalBlurView intensity={90} tint="dark" style={StyleSheet.absoluteFillObject} />
        <View pointerEvents="none" style={[StyleSheet.absoluteFillObject, { backgroundColor: theme.glassTint }]} />
        <Animated.View
          pointerEvents="none"
          style={{
            position: 'absolute',
            left: 0,
            right: 0,
            bottom: 0,
            height: StyleSheet.hairlineWidth,
            backgroundColor: 'rgba(255,255,255,1)',
            opacity: separatorOpacity,
          }}
        />
      </Animated.View>
      <SafeAreaView edges={["top"]} style={{ flex: 1 }} pointerEvents="box-none">
        <View style={{ paddingHorizontal: 16, paddingTop: 0 }} pointerEvents="box-none">
          {/* Header row – always visible */}
          <View style={{ height: TOP_BAR_BASE_HEIGHT, flexDirection: 'row', alignItems:'center', justifyContent:'space-between', paddingHorizontal: 4 }}>
            <Animated.Text
              style={{
                color: '#fff',
                fontSize: compact || barStyle === 'compact' ? 20 : 25,
                fontWeight: compact ? '700' : '600',
                transformOrigin: 'left center',
                transform: [{ translateX: titleShift }, { translateY: titleShift }, { scale: titleScale }],
              }}
            >
              {compact ? username : `For ${username || 'You'}`}
            </Animated.Text>
            <Animated.View style={{ transformOrigin: 'right center', transform: [{ translateY: titleShift }, { scale: iconsScale }] }}>
            <Pressable
              onPress={handleOpenDownloads}
              hitSlop={10}
              style={({ pressed }) => [{ opacity: pressed ? 0.6 : 1 }]}
              accessibilityRole="button"
              accessibilityLabel="Downloads"
            >
              <Image
                source={require('../../assets/icons/downloads.png')}
                style={{ width: 32, height: 32, resizeMode: 'contain' }}
              />
            </Pressable>
            </Animated.View>
          </View>
          {/* Pills row – animated visibility with slide up/down OR custom filters */}
          {customFilters ? (
            <View style={{ paddingVertical: 4 }}>
              {customFilters}
            </View>
          ) : showFilters ? (
            <View style={{ height: pillsAreaHeight }} pointerEvents={pillsHidden ? 'none' : 'box-none'}>
              <Animated.View
                style={{
                  opacity: pillsOpacity,
                  transformOrigin: 'center top',
                  transform: [{ translateY: pillsTranslateY }, { scale: pillsScale }],
                }}
              >
                <Pills
                  selected={selected || 'all'}
                  onChange={(t)=> {
                    LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
                    // Always call onChange first to update state
                    onChange && onChange(t);
                    // Then navigate if it's a content pill (not 'all')
                    // Use prop directly for local TopAppBar, fallback to store for global
                    if (t === 'movies' || t === 'shows') {
                      if (onNavigateLibrary) {
                        onNavigateLibrary(t);
                      } else {
                        TopBarStore.navigateLibrary(t);
                      }
                    }
                  }}
                  onOpenCategories={onOpenCategories}
                  onSelectCategory={onSelectCategory}
                  onClose={onClose}
                  activeGenre={activeGenre}
                  onClearGenre={onClearGenre}
                  customPillLabel={customPillLabel}
                />
              </Animated.View>
            </View>
          ) : null}
        </View>
      </SafeAreaView>
    </Animated.View>
  );
}

export default React.memo(TopAppBar);
