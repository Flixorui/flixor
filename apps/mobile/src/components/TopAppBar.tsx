import React from 'react';
import { Animated, View, Text, StyleSheet, LayoutAnimation, UIManager, Platform, Pressable, Image } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useNavigation } from '@react-navigation/native';
import Pills from './Pills';
import HeaderGlass, { HEADER_GLASS_MIN_OPACITY } from './HeaderGlass';
import type { CategoryPick } from './CategoriesMenu';
import { TopBarStore } from './TopBarStore';
import {
  TOP_BAR_BASE_HEIGHT,
  TOP_BAR_COLLAPSED_CONTENT_HEIGHT,
  TOP_BAR_EXPANDED_CONTENT_HEIGHT,
  TOP_BAR_PILLS_AREA_HEIGHT,
} from './topBarMetrics';
import { useTheme } from '../hooks/useTheme';
import { HIDDEN_PILL_OPACITY, useHeaderCollapse } from './useHeaderCollapse';

if (Platform.OS === 'android') {
  UIManager.setLayoutAnimationEnabledExperimental?.(true);
}


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

  const collapsedHeight = insets.top + TOP_BAR_COLLAPSED_CONTENT_HEIGHT;
  const expandedHeight = insets.top + TOP_BAR_EXPANDED_CONTENT_HEIGHT;
  const headerHeight = (showFilters || customFilters) ? expandedHeight : collapsedHeight;
  const pillsAreaHeight = TOP_BAR_PILLS_AREA_HEIGHT;

  const fallbackOpacity = React.useRef(new Animated.Value(HEADER_GLASS_MIN_OPACITY)).current;

  // Expanded keeps the pills on screen. Adaptive hides them on scroll down and returns
  // them on a deliberate scroll up. Compact hides them on scroll and returns them only at the top.
  // Netflix behaviour: pills hide on a scroll down and return on a deliberate scroll up
  const canCollapse = !!scrollY && !!showFilters && !customFilters;

  // Netflix's measured pill hide / show (shared with the Shows / Movies page)
  const { pillsP, titleP, bandP, pillsHidden } = useHeaderCollapse({
    scrollY,
    enabled: canCollapse,
    showOnUpwardScroll: true,
  });

  const pillsOpacity = pillsP.interpolate({ inputRange: [0, 1], outputRange: [1, HIDDEN_PILL_OPACITY] });
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
    return scrollY.interpolate({ inputRange: [0, 8, 120], outputRange: [HEADER_GLASS_MIN_OPACITY, HEADER_GLASS_MIN_OPACITY, 1], extrapolate: 'clamp' });
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
        <HeaderGlass fallbackIntensity={90} />
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
                fontSize: compact ? 20 : 25,
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
