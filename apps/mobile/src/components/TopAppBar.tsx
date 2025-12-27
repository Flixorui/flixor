import React, { useEffect, useRef } from 'react';
import { Animated, View, Text, StyleSheet, Easing } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import Feather from '@expo/vector-icons/Feather';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { BlurView } from 'expo-blur';
import { Pressable } from 'react-native';
import Pills from './Pills';
import { LinearGradient } from 'expo-linear-gradient';

function TopAppBar({ visible, username, showFilters, selected, onChange, onOpenCategories, onNavigateLibrary, onClose, onSearch, scrollY, onHeightChange, showPills, compact, customFilters, activeGenre, onClearGenre }: {
  visible: boolean;
  username?: string;
  showFilters?: boolean;
  selected?: 'all'|'movies'|'shows';
  onChange?: (t:'all'|'movies'|'shows')=>void;
  onOpenCategories?: ()=>void;
  onNavigateLibrary?: (tab: 'movies'|'shows')=>void;
  onClose?: ()=>void;
  onSearch?: ()=>void;
  scrollY?: Animated.Value;
  onHeightChange?: (h:number)=>void;
  showPills?: Animated.Value; // 0=hidden, 1=visible
  compact?: boolean; // Smaller header for screens like NewHot
  customTitle?: string;
  customFilters?: React.ReactNode; // Custom filter content (e.g., tab pills for NewHot)
  activeGenre?: string;
  onClearGenre?: ()=>void;
}) {
  const insets = useSafeAreaInsets();
  const AnimatedBlurView: any = Animated.createAnimatedComponent(BlurView);

  // Compute heights - use smaller base height in compact mode
  const baseHeight = 44;
  const pillsHeight = 48;
  // In compact mode (NewHot), always use collapsed height; in normal mode respect showFilters
  const collapsedHeight = insets.top + baseHeight + 4;
  const expandedHeight = (insets.top + baseHeight + pillsHeight + 8);

  // Animated height - interpolate from showPills (uses spring animation from screens)
  const heightAnim = useRef(new Animated.Value(expandedHeight)).current;
  
  // When showPills changes, animate height smoothly (only in non-compact mode)
  useEffect(() => {
    if (showPills && !compact) {
      // Listen to showPills changes and animate height accordingly
      const listener = showPills.addListener(({ value }) => {
        const targetHeight = collapsedHeight + (value * (pillsHeight + 8));
        Animated.timing(heightAnim, {
          toValue: targetHeight,
          duration: 0, // Instant follow, spring handles smoothness
          useNativeDriver: false,
        }).start();
      });
      return () => showPills.removeListener(listener);
    } else if (compact) {
      // In compact mode, set height to collapsed immediately
      Animated.timing(heightAnim, {
        toValue: collapsedHeight,
        duration: 0,
        useNativeDriver: false,
      }).start();
    }
  }, [showPills, compact, collapsedHeight, pillsHeight]);

  // Report height based on mode
  useEffect(() => {
    if (onHeightChange && visible) {
      onHeightChange(compact ? collapsedHeight : expandedHeight);
    }
  }, [expandedHeight, collapsedHeight, visible, onHeightChange, compact]);

  // Derive blur/tint from scrollY
  const blurIntensity = scrollY ? scrollY.interpolate({ inputRange:[0,120], outputRange:[0,90], extrapolate:'clamp' }) : new Animated.Value(0);
  const tintOpacity = scrollY ? scrollY.interpolate({ inputRange:[0,120], outputRange:[0,0.12], extrapolate:'clamp' }) : new Animated.Value(0);
  const separatorOpacity = scrollY ? scrollY.interpolate({ inputRange:[0,120], outputRange:[0,0.08], extrapolate:'clamp' }) : new Animated.Value(0);
  
  // Pills animations - opacity and translateY for smooth hide/reveal
  const pillsOpacity = showPills || new Animated.Value(1);
  const pillsTranslateY = showPills 
    ? showPills.interpolate({ inputRange: [0, 1], outputRange: [-20, 0] })
    : 0;

  return (
    <Animated.View
      pointerEvents={visible ? 'box-none' : 'none'}
      style={{ position: 'absolute', top: 0, left: 0, right: 0, zIndex: 20, height: heightAnim }}
    >
      {/* Full-bleed frosted background – always at max, controlled by container opacity */}
      <Animated.View style={[StyleSheet.absoluteFillObject, { opacity: scrollY ? scrollY.interpolate({ inputRange:[0,120], outputRange:[0,1], extrapolate:'clamp' }) : 0 }]}>
        <BlurView
          intensity={90}
          tint="dark"
          style={StyleSheet.absoluteFillObject}
        />
        {/* Glass tint overlay */}
        <View pointerEvents="none" style={[StyleSheet.absoluteFillObject, { backgroundColor: 'rgba(27,10,16,0.12)' }]} />
      </Animated.View>
      {/* Hairline separator at bottom – fades in with scroll */}
      <Animated.View pointerEvents="none" style={{ position:'absolute', left:0, right:0, bottom:0, height: StyleSheet.hairlineWidth, backgroundColor:'rgba(255,255,255,1)', opacity: separatorOpacity }} />
      <SafeAreaView edges={["top"]} style={{ flex: 1 }} pointerEvents="box-none">
        <View style={{ paddingHorizontal: 16, paddingTop: 0 }} pointerEvents="box-none">
          {/* Header row – always visible */}
          <View style={{ height: baseHeight, flexDirection: 'row', alignItems:'center', justifyContent:'space-between', paddingHorizontal: 4 }}>
            <Text style={{ color: '#fff', fontSize: compact ? 20 : 25, fontWeight: compact ? '700' : '600'}}>
              {compact ? username : `For ${username || 'You'}`}
            </Text>
            <View style={{ flexDirection: 'row' }}>
              {/* {!compact && <Feather name="cast" size={20} color="#fff" style={{ marginHorizontal: 8 }} />}
              {!compact && <Ionicons name="download-outline" size={20} color="#fff" style={{ marginHorizontal: 8 }} />} */}
              <Pressable onPress={onSearch}>
                <Ionicons name="search-outline" size={compact ? 22 : 20} color="#fff" style={{ marginHorizontal: compact ? 0 : 8 }} />
              </Pressable>
            </View>
          </View>
          {/* Pills row – animated visibility with slide up/down OR custom filters */}
          {customFilters ? (
            <View style={{ paddingVertical: 4 }}>
              {customFilters}
            </View>
          ) : showFilters ? (
            <Animated.View style={{ 
              opacity: pillsOpacity, 
              transform: [{ translateY: pillsTranslateY }],
              overflow: 'hidden',
            }}>
              <Pills
                selected={selected || 'all'}
                onChange={(t)=> {
                  console.log('[TopAppBar] Pill onChange:', t, 'current selected:', selected);
                  // Always call onChange first to update state
                  onChange && onChange(t);
                  // Then navigate if it's a content pill (not 'all')
                  if ((t === 'movies' || t === 'shows') && onNavigateLibrary) {
                    console.log('[TopAppBar] Calling onNavigateLibrary with:', t);
                    onNavigateLibrary(t);
                  }
                }}
                onOpenCategories={onOpenCategories}
                onClose={onClose}
                activeGenre={activeGenre}
                onClearGenre={onClearGenre}
              />
            </Animated.View>
          ) : null}
        </View>
      </SafeAreaView>
    </Animated.View>
  );
}

export default React.memo(TopAppBar);
