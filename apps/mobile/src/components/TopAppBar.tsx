import React from 'react';
import { Animated, View, Text, StyleSheet, LayoutAnimation, UIManager, Platform } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import ConditionalBlurView from './ConditionalBlurView';
import Pills from './Pills';
import { TopBarStore } from './TopBarStore';
import {
  TOP_BAR_BASE_HEIGHT,
  TOP_BAR_COLLAPSED_CONTENT_HEIGHT,
  TOP_BAR_EXPANDED_CONTENT_HEIGHT,
  TOP_BAR_PILLS_AREA_HEIGHT,
} from './topBarMetrics';

if (Platform.OS === 'android') {
  UIManager.setLayoutAnimationEnabledExperimental?.(true);
}

function TopAppBar({ visible, username, showFilters, selected, onChange, onOpenCategories, onNavigateLibrary, onClose, scrollY, onHeightChange, compact, customFilters, activeGenre, onClearGenre }: {
  visible: boolean;
  username?: string;
  showFilters?: boolean;
  selected?: 'all'|'movies'|'shows';
  onChange?: (t:'all'|'movies'|'shows')=>void;
  onOpenCategories?: ()=>void;
  onNavigateLibrary?: (tab: 'movies'|'shows')=>void;
  onClose?: ()=>void;
  scrollY?: Animated.Value;
  onHeightChange?: (h:number)=>void;
  compact?: boolean; // Smaller header for screens like NewHot
  customFilters?: React.ReactNode; // Custom filter content (e.g., tab pills for NewHot)
  activeGenre?: string;
  onClearGenre?: ()=>void;
}) {
  const insets = useSafeAreaInsets();

  const collapsedHeight = insets.top + TOP_BAR_COLLAPSED_CONTENT_HEIGHT;
  const expandedHeight = insets.top + TOP_BAR_EXPANDED_CONTENT_HEIGHT;
  const headerHeight = (showFilters || customFilters) ? expandedHeight : collapsedHeight;
  const pillsAreaHeight = TOP_BAR_PILLS_AREA_HEIGHT;

  const fallbackOffset = React.useRef(new Animated.Value(0)).current;
  const fallbackOpacity = React.useRef(new Animated.Value(0)).current;

  const canCollapse = !!scrollY && showFilters && !customFilters;
  const scrollMinusDeadzone = scrollY ? Animated.subtract(scrollY, 8) : fallbackOffset;
  const pillsOffset = canCollapse
    ? Animated.diffClamp(scrollMinusDeadzone, 0, pillsAreaHeight)
    : 0;
  const topClamp = canCollapse
    ? scrollY.interpolate({
        inputRange: [-200, 0, 8],
        outputRange: [1, 1, 0],
        extrapolate: 'clamp',
      })
    : 0;
  const clampedOffset = canCollapse
    ? Animated.multiply(pillsOffset, Animated.subtract(1, topClamp))
    : 0;
  const pillsOpacity = canCollapse
    ? clampedOffset.interpolate({
        inputRange: [0, pillsAreaHeight * 0.6],
        outputRange: [1, 0],
        extrapolate: 'clamp',
      })
    : 1;
  const pillsTranslateY = canCollapse ? Animated.multiply(clampedOffset, -1) : 0;

  const blurHeight = canCollapse
    ? Animated.subtract(expandedHeight, clampedOffset)
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
        <View pointerEvents="none" style={[StyleSheet.absoluteFillObject, { backgroundColor: 'rgba(27,10,16,0.12)' }]} />
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
            <Text style={{ color: '#fff', fontSize: compact ? 20 : 25, fontWeight: compact ? '700' : '600'}}>
              {compact ? username : `For ${username || 'You'}`}
            </Text>
            {/* Search button removed - using bottom tab bar search instead */}
          </View>
          {/* Pills row – animated visibility with slide up/down OR custom filters */}
          {customFilters ? (
            <View style={{ paddingVertical: 4 }}>
              {customFilters}
            </View>
          ) : showFilters ? (
            <View style={{ height: pillsAreaHeight, overflow: 'hidden' }} pointerEvents="box-none">
              <Animated.View style={{ opacity: pillsOpacity, transform: [{ translateY: pillsTranslateY }] }}>
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
                  onClose={onClose}
                  activeGenre={activeGenre}
                  onClearGenre={onClearGenre}
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
