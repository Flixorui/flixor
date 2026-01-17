import React, { useState, useRef, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  Dimensions,
  TouchableOpacity,
  StatusBar,
  Platform,
  Switch,
  ScrollView,
} from 'react-native';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  FadeIn,
  FadeInUp,
  useAnimatedScrollHandler,
  interpolate,
  Extrapolation,
  runOnJS,
  SharedValue,
} from 'react-native-reanimated';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { ShapeAnimation } from '../components/onboarding/ShapeAnimation';
import {
  loadAppSettings,
  setAppSettings,
  setDiscoveryDisabled,
  AppSettings,
} from '../core/SettingsData';

const { width, height } = Dimensions.get('window');

const STORAGE_KEY = 'flixor:hasCompletedOnboarding';

interface OnboardingSlide {
  id: string;
  title: string;
  subtitle: string;
  description: string;
  isConfig?: boolean;
}

const onboardingData: OnboardingSlide[] = [
  {
    id: '1',
    title: 'Welcome to\nFlixor',
    subtitle: 'Your Personal Media Hub',
    description: 'Stream your entire Plex library with a beautiful, Netflix-inspired experience on any device.',
  },
  {
    id: '2',
    title: 'Powerful\nIntegrations',
    subtitle: 'Connect Your Services',
    description: 'Sync with Trakt to track your watch history, get personalized recommendations, and discover new content.',
  },
  {
    id: '3',
    title: 'Smart\nDiscovery',
    subtitle: 'Find What You Love',
    description: 'Browse trending content, search across your library and TMDB, and get recommendations tailored to you.',
  },
  {
    id: '4',
    title: 'Your\nLibrary',
    subtitle: 'Beautifully Organized',
    description: 'Continue watching across devices, manage your watchlist, and enjoy stunning artwork from TMDB.',
  },
  {
    id: '5',
    title: 'Customize\nYour Experience',
    subtitle: 'Discovery Settings',
    description: 'Choose how you want to discover content.',
    isConfig: true,
  },
];

// Animated Slide Component with parallax
const AnimatedSlide = ({
  item,
  index,
  scrollX
}: {
  item: OnboardingSlide;
  index: number;
  scrollX: SharedValue<number>;
}) => {
  const inputRange = [(index - 1) * width, index * width, (index + 1) * width];

  const titleStyle = useAnimatedStyle(() => {
    const translateX = interpolate(
      scrollX.value,
      inputRange,
      [width * 0.3, 0, -width * 0.3],
      Extrapolation.CLAMP
    );
    const opacity = interpolate(
      scrollX.value,
      inputRange,
      [0, 1, 0],
      Extrapolation.CLAMP
    );
    const scale = interpolate(
      scrollX.value,
      inputRange,
      [0.8, 1, 0.8],
      Extrapolation.CLAMP
    );
    return {
      transform: [{ translateX }, { scale }],
      opacity,
    };
  });

  const subtitleStyle = useAnimatedStyle(() => {
    const translateX = interpolate(
      scrollX.value,
      inputRange,
      [width * 0.5, 0, -width * 0.5],
      Extrapolation.CLAMP
    );
    const opacity = interpolate(
      scrollX.value,
      inputRange,
      [0, 1, 0],
      Extrapolation.CLAMP
    );
    return {
      transform: [{ translateX }],
      opacity,
    };
  });

  const descriptionStyle = useAnimatedStyle(() => {
    const translateX = interpolate(
      scrollX.value,
      inputRange,
      [width * 0.7, 0, -width * 0.7],
      Extrapolation.CLAMP
    );
    const opacity = interpolate(
      scrollX.value,
      inputRange,
      [0, 1, 0],
      Extrapolation.CLAMP
    );
    return {
      transform: [{ translateX }],
      opacity,
    };
  });

  return (
    <View style={styles.slide}>
      <View style={styles.textContainer}>
        <Animated.Text style={[styles.title, titleStyle]}>
          {item.title}
        </Animated.Text>

        <Animated.Text style={[styles.subtitle, subtitleStyle]}>
          {item.subtitle}
        </Animated.Text>

        <Animated.Text style={[styles.description, descriptionStyle]}>
          {item.description}
        </Animated.Text>
      </View>
    </View>
  );
};

// Individual Setting Row Component for Config Slide
const SettingRow = ({
  icon,
  title,
  description,
  value,
  onValueChange,
  isLast = false,
  disabled = false,
}: {
  icon: string;
  title: string;
  description: string;
  value: boolean;
  onValueChange: (value: boolean) => void;
  isLast?: boolean;
  disabled?: boolean;
}) => (
  <View style={[configStyles.settingRow, !isLast && configStyles.settingRowBorder]}>
    <View style={configStyles.settingIconContainer}>
      <Ionicons name={icon as any} size={20} color={disabled ? 'rgba(255,255,255,0.3)' : 'rgba(255,255,255,0.6)'} />
    </View>
    <View style={configStyles.settingTextContainer}>
      <Text style={[configStyles.settingTitle, disabled && configStyles.settingTitleDisabled]}>{title}</Text>
      <Text style={configStyles.settingDescription}>{description}</Text>
    </View>
    <Switch
      value={value}
      onValueChange={onValueChange}
      trackColor={{ false: 'rgba(255,255,255,0.2)', true: '#4CAF50' }}
      thumbColor="#FFFFFF"
      disabled={disabled}
    />
  </View>
);

// Config Slide Component
const ConfigSlide = ({
  index,
  scrollX,
  discoveryOff,
  setDiscoveryOff,
  showIndividual,
  setShowIndividual,
  trendingOff,
  setTrendingOff,
  traktOff,
  setTraktOff,
  plexPopularOff,
  setPlexPopularOff,
  newHotOff,
  setNewHotOff,
  tmdbSearchOff,
  setTmdbSearchOff,
}: {
  index: number;
  scrollX: SharedValue<number>;
  discoveryOff: boolean;
  setDiscoveryOff: (value: boolean) => void;
  showIndividual: boolean;
  setShowIndividual: (value: boolean) => void;
  trendingOff: boolean;
  setTrendingOff: (value: boolean) => void;
  traktOff: boolean;
  setTraktOff: (value: boolean) => void;
  plexPopularOff: boolean;
  setPlexPopularOff: (value: boolean) => void;
  newHotOff: boolean;
  setNewHotOff: (value: boolean) => void;
  tmdbSearchOff: boolean;
  setTmdbSearchOff: (value: boolean) => void;
}) => {
  const inputRange = [(index - 1) * width, index * width, (index + 1) * width];

  const containerStyle = useAnimatedStyle(() => {
    const opacity = interpolate(
      scrollX.value,
      inputRange,
      [0, 1, 0],
      Extrapolation.CLAMP
    );
    const translateX = interpolate(
      scrollX.value,
      inputRange,
      [width * 0.3, 0, -width * 0.3],
      Extrapolation.CLAMP
    );
    return {
      opacity,
      transform: [{ translateX }],
    };
  });

  return (
    <View style={styles.slide}>
      <Animated.View style={[configStyles.configContainer, containerStyle]}>
        <Text style={configStyles.configTitle}>Customize Your Experience</Text>
        <Text style={configStyles.configSubtitle}>Choose how you want to discover content</Text>

        <ScrollView
          style={configStyles.configScrollView}
          showsVerticalScrollIndicator={false}
          nestedScrollEnabled={true}
        >
          {/* Master Toggle */}
          <View style={configStyles.card}>
            <LinearGradient
              colors={['rgba(255,255,255,0.08)', 'rgba(255,255,255,0.04)']}
              style={configStyles.cardGradient}
            >
              <View style={configStyles.cardHeader}>
                <View style={configStyles.cardIconContainer}>
                  <Ionicons name="eye-off" size={24} color="#FF6B6B" />
                </View>
                <View style={configStyles.cardTextContainer}>
                  <Text style={configStyles.cardTitle}>Library Only Mode</Text>
                  <Text style={configStyles.cardDescription}>
                    Turn off all discovery features. Only show content from your Plex library.
                  </Text>
                </View>
                <Switch
                  value={discoveryOff}
                  onValueChange={setDiscoveryOff}
                  trackColor={{ false: 'rgba(255,255,255,0.2)', true: '#FF6B6B' }}
                  thumbColor="#FFFFFF"
                />
              </View>
            </LinearGradient>
          </View>

          {/* Individual Settings Toggle */}
          <TouchableOpacity
            style={configStyles.expandButton}
            onPress={() => setShowIndividual(!showIndividual)}
            disabled={discoveryOff}
          >
            <Text style={[configStyles.expandText, discoveryOff && configStyles.expandTextDisabled]}>
              Or customize individual settings
            </Text>
            <Ionicons
              name={showIndividual ? 'chevron-up' : 'chevron-down'}
              size={20}
              color={discoveryOff ? 'rgba(255,255,255,0.2)' : 'rgba(255,255,255,0.5)'}
            />
          </TouchableOpacity>

          {/* Individual Settings */}
          {showIndividual && !discoveryOff && (
            <View style={configStyles.individualContainer}>
              <SettingRow
                icon="trending-up"
                title="Trending Rows"
                description="Show trending content from TMDB"
                value={!trendingOff}
                onValueChange={(v) => setTrendingOff(!v)}
              />
              <SettingRow
                icon="logo-react"
                title="Trakt Rows"
                description="Show recommendations from Trakt"
                value={!traktOff}
                onValueChange={(v) => setTraktOff(!v)}
              />
              <SettingRow
                icon="star"
                title="Popular on Plex"
                description="Show popular content on Plex"
                value={!plexPopularOff}
                onValueChange={(v) => setPlexPopularOff(!v)}
              />
              <SettingRow
                icon="flame"
                title="New & Hot Tab"
                description="Show New & Hot tab in navigation"
                value={!newHotOff}
                onValueChange={(v) => setNewHotOff(!v)}
              />
              <SettingRow
                icon="search"
                title="TMDB in Search"
                description="Include TMDB results when searching"
                value={!tmdbSearchOff}
                onValueChange={(v) => setTmdbSearchOff(!v)}
                isLast
              />
            </View>
          )}

          {/* Info Text */}
          <View style={configStyles.infoContainer}>
            <Ionicons name="information-circle-outline" size={18} color="rgba(255,255,255,0.4)" />
            <Text style={configStyles.infoText}>
              You can change these settings anytime in Settings → Home Screen
            </Text>
          </View>
        </ScrollView>
      </Animated.View>
    </View>
  );
};

interface OnboardingScreenProps {
  onComplete: () => void;
}

const OnboardingScreen = ({ onComplete }: OnboardingScreenProps) => {
  const [currentIndex, setCurrentIndex] = useState(0);
  const flatListRef = useRef<Animated.FlatList<OnboardingSlide>>(null);
  const scrollX = useSharedValue(0);

  // Config state
  const [settings, setSettings] = useState<AppSettings | null>(null);
  const [discoveryOff, setDiscoveryOff] = useState(false);
  const [showIndividual, setShowIndividual] = useState(false);
  const [trendingOff, setTrendingOff] = useState(false);
  const [traktOff, setTraktOff] = useState(false);
  const [plexPopularOff, setPlexPopularOff] = useState(false);
  const [newHotOff, setNewHotOff] = useState(false);
  const [tmdbSearchOff, setTmdbSearchOff] = useState(false);

  // Load settings on mount
  useEffect(() => {
    (async () => {
      const loaded = await loadAppSettings();
      setSettings(loaded);
      setDiscoveryOff(loaded.discoveryDisabled);
      setTrendingOff(!loaded.showTrendingRows);
      setTraktOff(!loaded.showTraktRows);
      setPlexPopularOff(!loaded.showPlexPopularRow);
      setNewHotOff(!loaded.showNewHotTab);
      setTmdbSearchOff(!loaded.includeTmdbInSearch);
    })();
  }, []);

  // When master toggle is enabled, disable all individual settings
  useEffect(() => {
    if (discoveryOff) {
      setTrendingOff(true);
      setTraktOff(true);
      setPlexPopularOff(true);
      setNewHotOff(true);
      setTmdbSearchOff(true);
    }
  }, [discoveryOff]);

  const updateIndex = (index: number) => {
    setCurrentIndex(index);
  };

  const onScroll = useAnimatedScrollHandler({
    onScroll: (event) => {
      scrollX.value = event.contentOffset.x;
    },
    onMomentumEnd: (event) => {
      const slideIndex = Math.round(event.contentOffset.x / width);
      runOnJS(updateIndex)(slideIndex);
    },
  });

  const progressStyle = useAnimatedStyle(() => {
    const progress = interpolate(
      scrollX.value,
      [0, (onboardingData.length - 1) * width],
      [0, 100],
      Extrapolation.CLAMP
    );
    return {
      width: `${progress}%`,
    };
  });

  const handleSkip = async () => {
    try {
      await AsyncStorage.setItem(STORAGE_KEY, 'true');
    } catch { }
    onComplete();
  };

  const handleGetStarted = async () => {
    try {
      // Save discovery settings
      if (discoveryOff) {
        await setDiscoveryDisabled(true);
      } else {
        await setAppSettings({
          discoveryDisabled: false,
          showTrendingRows: !trendingOff,
          showTraktRows: !traktOff,
          showPlexPopularRow: !plexPopularOff,
          showNewHotTab: !newHotOff,
          includeTmdbInSearch: !tmdbSearchOff,
        });
      }
      await AsyncStorage.setItem(STORAGE_KEY, 'true');
    } catch { }
    onComplete();
  };

  const renderSlide = ({ item, index }: { item: OnboardingSlide; index: number }) => {
    if (item.isConfig) {
      return (
        <ConfigSlide
          index={index}
          scrollX={scrollX}
          discoveryOff={discoveryOff}
          setDiscoveryOff={setDiscoveryOff}
          showIndividual={showIndividual}
          setShowIndividual={setShowIndividual}
          trendingOff={trendingOff}
          setTrendingOff={setTrendingOff}
          traktOff={traktOff}
          setTraktOff={setTraktOff}
          plexPopularOff={plexPopularOff}
          setPlexPopularOff={setPlexPopularOff}
          newHotOff={newHotOff}
          setNewHotOff={setNewHotOff}
          tmdbSearchOff={tmdbSearchOff}
          setTmdbSearchOff={setTmdbSearchOff}
        />
      );
    }
    return <AnimatedSlide item={item} index={index} scrollX={scrollX} />;
  };

  // Animated pagination dots
  const PaginationDot = ({ index }: { index: number }) => {
    const dotStyle = useAnimatedStyle(() => {
      const inputRange = [(index - 1) * width, index * width, (index + 1) * width];
      const dotWidth = interpolate(
        scrollX.value,
        inputRange,
        [8, 32, 8],
        Extrapolation.CLAMP
      );
      const opacity = interpolate(
        scrollX.value,
        inputRange,
        [0.3, 1, 0.3],
        Extrapolation.CLAMP
      );
      return {
        width: dotWidth,
        opacity,
      };
    });

    return <Animated.View style={[styles.paginationDot, dotStyle]} />;
  };

  // Animated button
  const buttonScale = useSharedValue(1);

  const buttonStyle = useAnimatedStyle(() => ({
    transform: [{ scale: buttonScale.value }],
  }));

  // Animated opacity for button and swipe indicator based on scroll
  const lastSlideStart = (onboardingData.length - 1) * width;

  const buttonOpacityStyle = useAnimatedStyle(() => {
    const opacity = interpolate(
      scrollX.value,
      [lastSlideStart - width * 0.3, lastSlideStart],
      [0, 1],
      Extrapolation.CLAMP
    );
    return { opacity };
  });

  const swipeOpacityStyle = useAnimatedStyle(() => {
    const opacity = interpolate(
      scrollX.value,
      [lastSlideStart - width * 0.3, lastSlideStart],
      [1, 0],
      Extrapolation.CLAMP
    );
    return { opacity };
  });

  const handlePressIn = () => {
    buttonScale.value = withSpring(0.95, { damping: 15, stiffness: 400 });
  };

  const handlePressOut = () => {
    buttonScale.value = withSpring(1, { damping: 15, stiffness: 400 });
  };

  return (
    <View style={styles.container}>
      <StatusBar barStyle="light-content" backgroundColor="#0A0A0A" translucent />

      <View style={styles.fullScreenContainer}>
        {/* Shape Animation Background - iOS only for performance */}
        {Platform.OS === 'ios' && <ShapeAnimation scrollX={scrollX} />}

        {/* Header */}
        <Animated.View
          entering={FadeIn.delay(300).duration(600)}
          style={styles.header}
        >
          <TouchableOpacity onPress={handleSkip} style={styles.skipButton}>
            <Text style={styles.skipText}>Skip</Text>
          </TouchableOpacity>

          {/* Smooth Progress Bar */}
          <View style={styles.progressContainer}>
            <Animated.View style={[styles.progressBar, progressStyle]} />
          </View>
        </Animated.View>

        {/* Slides */}
        <Animated.FlatList
          ref={flatListRef}
          data={onboardingData}
          renderItem={renderSlide}
          horizontal
          pagingEnabled
          showsHorizontalScrollIndicator={false}
          keyExtractor={(item) => item.id}
          onScroll={onScroll}
          scrollEventThrottle={16}
          decelerationRate="fast"
          snapToInterval={width}
          snapToAlignment="start"
          bounces={false}
          style={{ flex: 1 }}
        />

        {/* Footer */}
        <Animated.View
          entering={FadeInUp.delay(500).duration(600)}
          style={styles.footer}
        >
          {/* Smooth Pagination */}
          <View style={styles.pagination}>
            {onboardingData.map((_, index) => (
              <PaginationDot key={index} index={index} />
            ))}
          </View>

          {/* Button and Swipe indicator with crossfade based on scroll */}
          <View style={styles.footerButtonContainer}>
            {/* Swipe Indicator - fades out on last slide */}
            <Animated.View style={[styles.swipeIndicator, styles.absoluteFill, swipeOpacityStyle]}>
              <Text style={styles.swipeText}>Swipe to continue</Text>
              <Text style={styles.swipeArrow}>→</Text>
            </Animated.View>

            {/* Get Started Button - fades in on last slide */}
            <Animated.View style={[styles.absoluteFill, buttonOpacityStyle]}>
              <TouchableOpacity
                onPress={handleGetStarted}
                onPressIn={handlePressIn}
                onPressOut={handlePressOut}
                activeOpacity={1}
              >
                <Animated.View style={[styles.button, buttonStyle]}>
                  <Text style={styles.buttonText}>Get Started</Text>
                </Animated.View>
              </TouchableOpacity>
            </Animated.View>
          </View>
        </Animated.View>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0A0A0A',
  },
  fullScreenContainer: {
    flex: 1,
    paddingTop: Platform.OS === 'ios' ? 60 : (StatusBar.currentHeight || 24) + 16,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 24,
    paddingBottom: 20,
  },
  skipButton: {
    paddingVertical: 8,
    paddingHorizontal: 4,
  },
  skipText: {
    fontSize: 15,
    fontWeight: '500',
    color: 'rgba(255, 255, 255, 0.4)',
  },
  progressContainer: {
    flex: 1,
    height: 3,
    borderRadius: 1.5,
    marginLeft: 24,
    backgroundColor: 'rgba(255, 255, 255, 0.08)',
    overflow: 'hidden',
  },
  progressBar: {
    height: '100%',
    borderRadius: 1.5,
    backgroundColor: '#FFFFFF',
  },
  slide: {
    width,
    flex: 1,
    justifyContent: Platform.OS === 'ios' ? 'flex-start' : 'center',
    paddingHorizontal: 32,
    paddingTop: Platform.OS === 'ios' ? '20%' : 0,
  },
  textContainer: {
    alignItems: 'flex-start',
  },
  title: {
    fontSize: 52,
    fontWeight: '800',
    letterSpacing: -2,
    lineHeight: 56,
    marginBottom: 16,
    color: '#FFFFFF',
  },
  subtitle: {
    fontSize: 17,
    fontWeight: '600',
    color: 'rgba(255, 255, 255, 0.6)',
    marginBottom: 20,
    letterSpacing: 0.3,
  },
  description: {
    fontSize: 15,
    lineHeight: 24,
    color: 'rgba(255, 255, 255, 0.4)',
    maxWidth: 300,
    textAlign: 'left',
  },
  footer: {
    paddingHorizontal: 24,
    paddingBottom: Platform.OS === 'ios' ? 50 : 32,
  },
  pagination: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 32,
    gap: 6,
  },
  paginationDot: {
    height: 8,
    borderRadius: 4,
    backgroundColor: '#FFFFFF',
  },
  button: {
    backgroundColor: '#FFFFFF',
    borderRadius: 16,
    paddingVertical: 18,
    alignItems: 'center',
    justifyContent: 'center',
  },
  buttonText: {
    fontSize: 16,
    fontWeight: '700',
    color: '#0A0A0A',
    letterSpacing: 0.3,
  },
  swipeIndicator: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 18,
    gap: 8,
  },
  swipeText: {
    fontSize: 14,
    fontWeight: '500',
    color: 'rgba(255, 255, 255, 0.4)',
    letterSpacing: 0.3,
  },
  swipeArrow: {
    fontSize: 18,
    color: 'rgba(255, 255, 255, 0.4)',
  },
  footerButtonContainer: {
    height: 56,
    position: 'relative',
  },
  absoluteFill: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
  },
});

// Config Slide Styles
const configStyles = StyleSheet.create({
  configContainer: {
    flex: 1,
    paddingHorizontal: 8,
  },
  configTitle: {
    fontSize: 28,
    fontWeight: '800',
    color: '#FFFFFF',
    marginBottom: 8,
  },
  configSubtitle: {
    fontSize: 15,
    color: 'rgba(255,255,255,0.5)',
    marginBottom: 20,
  },
  configScrollView: {
    flex: 1,
  },
  card: {
    borderRadius: 16,
    overflow: 'hidden',
    marginBottom: 16,
  },
  cardGradient: {
    padding: 20,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
  },
  cardHeader: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  cardIconContainer: {
    width: 48,
    height: 48,
    borderRadius: 12,
    backgroundColor: 'rgba(255,107,107,0.15)',
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 16,
  },
  cardTextContainer: {
    flex: 1,
    marginRight: 12,
  },
  cardTitle: {
    fontSize: 17,
    fontWeight: '700',
    color: '#FFFFFF',
    marginBottom: 4,
  },
  cardDescription: {
    fontSize: 13,
    color: 'rgba(255,255,255,0.5)',
    lineHeight: 18,
  },
  expandButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 16,
    gap: 8,
  },
  expandText: {
    fontSize: 14,
    fontWeight: '500',
    color: 'rgba(255,255,255,0.5)',
  },
  expandTextDisabled: {
    color: 'rgba(255,255,255,0.2)',
  },
  individualContainer: {
    backgroundColor: 'rgba(255,255,255,0.05)',
    borderRadius: 16,
    marginTop: 8,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
  },
  settingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 16,
  },
  settingRowBorder: {
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.08)',
  },
  settingIconContainer: {
    width: 36,
    height: 36,
    borderRadius: 10,
    backgroundColor: 'rgba(255,255,255,0.08)',
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 12,
  },
  settingTextContainer: {
    flex: 1,
    marginRight: 12,
  },
  settingTitle: {
    fontSize: 15,
    fontWeight: '600',
    color: '#FFFFFF',
    marginBottom: 2,
  },
  settingTitleDisabled: {
    color: 'rgba(255,255,255,0.4)',
  },
  settingDescription: {
    fontSize: 12,
    color: 'rgba(255,255,255,0.4)',
  },
  infoContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingTop: 24,
    paddingBottom: 80,
    gap: 8,
  },
  infoText: {
    flex: 1,
    fontSize: 13,
    color: 'rgba(255,255,255,0.4)',
    lineHeight: 18,
  },
});

export default OnboardingScreen;
