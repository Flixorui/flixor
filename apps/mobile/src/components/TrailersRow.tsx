import React, { useState, useCallback, useMemo } from 'react';
import { View, Text, ScrollView, Pressable, StyleSheet, Dimensions, Modal } from 'react-native';
import FastImage from '@d11/react-native-fast-image';
import { Ionicons } from '@expo/vector-icons';
import { BlurView } from 'expo-blur';
import * as Haptics from 'expo-haptics';
import Animated, { useSharedValue, withTiming, withDelay, useAnimatedStyle } from 'react-native-reanimated';
import TrailerModal from './TrailerModal';
import { getYouTubeThumbnailUrl } from '../core/DetailsData';

export interface TrailerVideo {
  key: string;
  name: string;
  site: string;
  type: string;
  official?: boolean;
  publishedAt?: string;
}

interface TrailersRowProps {
  trailers: TrailerVideo[];
  title?: string;
  contentTitle?: string;
}

const CARD_WIDTH = 200;
const CARD_SPACING = 12;

// Categorize trailers by type
function categorizeTrailers(trailers: TrailerVideo[]): Record<string, TrailerVideo[]> {
  const categories: Record<string, TrailerVideo[]> = {};

  trailers.forEach(trailer => {
    const category = trailer.type;
    if (!categories[category]) {
      categories[category] = [];
    }
    categories[category].push(trailer);
  });

  // Sort within each category: official first, then by date
  Object.keys(categories).forEach(category => {
    categories[category].sort((a, b) => {
      if (a.official && !b.official) return -1;
      if (!a.official && b.official) return 1;
      if (a.publishedAt && b.publishedAt) {
        return new Date(b.publishedAt).getTime() - new Date(a.publishedAt).getTime();
      }
      return 0;
    });
  });

  return categories;
}

// Format category name for display
function formatCategory(type: string): string {
  switch (type) {
    case 'Trailer': return 'Official Trailers';
    case 'Teaser': return 'Teasers';
    case 'Clip': return 'Clips & Scenes';
    case 'Featurette': return 'Featurettes';
    case 'Behind the Scenes': return 'Behind the Scenes';
    default: return type;
  }
}

// Get icon for category
function getCategoryIcon(type: string): string {
  switch (type) {
    case 'Trailer': return 'film-outline';
    case 'Teaser': return 'videocam-outline';
    case 'Clip': return 'cut-outline';
    case 'Featurette': return 'star-outline';
    case 'Behind the Scenes': return 'camera-outline';
    default: return 'play-circle-outline';
  }
}

function TrailerCard({ trailer, width, onPress }: { trailer: TrailerVideo; width: number; onPress: () => void }) {
  const thumbnailUrl = getYouTubeThumbnailUrl(trailer.key);
  const year = trailer.publishedAt ? new Date(trailer.publishedAt).getFullYear() : null;

  return (
    <View style={[styles.cardContainer, { width }]}>
      <Pressable
        onPress={() => {
          Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
          onPress();
        }}
        style={({ pressed }) => [
          styles.card,
          { width, opacity: pressed ? 0.9 : 1 }
        ]}
      >
        <View style={styles.thumbnailWrapper}>
          <FastImage
            source={{ uri: thumbnailUrl }}
            style={styles.thumbnail}
            resizeMode={FastImage.resizeMode.cover}
          />
          <View style={styles.thumbnailGradient} />
        </View>
      </Pressable>

      {/* Info Below Card */}
      <View style={styles.trailerInfo}>
        <Text style={styles.trailerTitle} numberOfLines={2}>
          {trailer.name}
        </Text>
        {year && (
          <Text style={styles.trailerMeta}>{year}</Text>
        )}
      </View>
    </View>
  );
}

export default function TrailersRow({ trailers, title = 'Trailers & Videos', contentTitle }: TrailersRowProps) {
  const [modalVisible, setModalVisible] = useState(false);
  const [selectedTrailer, setSelectedTrailer] = useState<TrailerVideo | null>(null);
  const [dropdownVisible, setDropdownVisible] = useState(false);

  // Categorize trailers
  const categories = useMemo(() => categorizeTrailers(trailers), [trailers]);
  const categoryNames = Object.keys(categories);

  // Select first category with "Trailer" preferred
  const [selectedCategory, setSelectedCategory] = useState<string>(() => {
    if (categoryNames.includes('Trailer')) return 'Trailer';
    if (categoryNames.includes('Teaser')) return 'Teaser';
    return categoryNames[0] || '';
  });

  // Animation
  const opacity = useSharedValue(0);
  const translateY = useSharedValue(8);

  React.useEffect(() => {
    if (trailers.length > 0) {
      opacity.value = withDelay(300, withTiming(1, { duration: 400 }));
      translateY.value = withDelay(300, withTiming(0, { duration: 400 }));
    }
  }, [trailers.length]);

  const animatedStyle = useAnimatedStyle(() => ({
    opacity: opacity.value,
    transform: [{ translateY: translateY.value }],
  }));

  const handleTrailerPress = useCallback((trailer: TrailerVideo) => {
    setSelectedTrailer(trailer);
    setModalVisible(true);
  }, []);

  const handleCloseModal = useCallback(() => {
    setModalVisible(false);
    setSelectedTrailer(null);
  }, []);

  const handleCategorySelect = useCallback((category: string) => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    setSelectedCategory(category);
    setDropdownVisible(false);
  }, []);

  if (trailers.length === 0 || categoryNames.length === 0) return null;

  const currentTrailers = categories[selectedCategory] || [];

  return (
    <Animated.View style={[styles.container, animatedStyle]}>
      {/* Header with Category Selector */}
      <View style={styles.header}>
        <Text style={styles.headerTitle}>{title}</Text>

        {categoryNames.length > 1 && (
          <Pressable
            onPress={() => {
              Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
              setDropdownVisible(true);
            }}
            style={({ pressed }) => [
              styles.categorySelector,
              { opacity: pressed ? 0.7 : 1 }
            ]}
          >
            <Text style={styles.categorySelectorText} numberOfLines={1}>
              {formatCategory(selectedCategory)}
            </Text>
            <Ionicons
              name={dropdownVisible ? 'chevron-up' : 'chevron-down'}
              size={16}
              color="rgba(255,255,255,0.7)"
            />
          </Pressable>
        )}
      </View>

      {/* Category Dropdown Modal */}
      <Modal
        visible={dropdownVisible}
        transparent
        animationType="fade"
        onRequestClose={() => setDropdownVisible(false)}
      >
        <Pressable
          style={styles.dropdownOverlay}
          onPress={() => setDropdownVisible(false)}
        >
          <View style={styles.dropdownContainer}>
            <BlurView intensity={100} tint="dark" style={styles.dropdownBlur}>
              {categoryNames.map(category => (
                <Pressable
                  key={category}
                  onPress={() => handleCategorySelect(category)}
                  style={({ pressed }) => [
                    styles.dropdownItem,
                    { backgroundColor: pressed ? 'rgba(255,255,255,0.1)' : 'transparent' }
                  ]}
                >
                  <View style={styles.dropdownItemContent}>
                    <View style={styles.categoryIconContainer}>
                      <Ionicons
                        name={getCategoryIcon(category) as any}
                        size={16}
                        color="#e50914"
                      />
                    </View>
                    <Text style={styles.dropdownItemText}>
                      {formatCategory(category)}
                    </Text>
                    <View style={styles.dropdownItemCount}>
                      <Text style={styles.dropdownItemCountText}>
                        {categories[category].length}
                      </Text>
                    </View>
                  </View>
                </Pressable>
              ))}
            </BlurView>
          </View>
        </Pressable>
      </Modal>

      {/* Trailers Horizontal Scroll */}
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.scrollContent}
        decelerationRate="fast"
        snapToInterval={CARD_WIDTH + CARD_SPACING}
        snapToAlignment="start"
      >
        {currentTrailers.map((trailer) => (
          <TrailerCard
            key={trailer.key}
            trailer={trailer}
            width={CARD_WIDTH}
            onPress={() => handleTrailerPress(trailer)}
          />
        ))}

        {/* Scroll Indicator */}
        {currentTrailers.length > 2 && (
          <View style={styles.scrollIndicator}>
            <Ionicons name="chevron-forward" size={20} color="rgba(255,255,255,0.4)" />
          </View>
        )}
      </ScrollView>

      <TrailerModal
        visible={modalVisible}
        trailer={selectedTrailer}
        onClose={handleCloseModal}
        contentTitle={contentTitle}
      />
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  container: {
    marginTop: 24,
    marginBottom: 16,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    marginBottom: 16,
  },
  headerTitle: {
    color: '#fff',
    fontSize: 20,
    fontWeight: '700',
    letterSpacing: 0.3,
  },
  categorySelector: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.5)',
    borderRadius: 16,
    paddingHorizontal: 12,
    paddingVertical: 6,
    backgroundColor: 'rgba(255,255,255,0.03)',
    gap: 6,
    maxWidth: 160,
  },
  categorySelectorText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '600',
    maxWidth: 120,
  },
  dropdownOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.6)',
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 24,
  },
  dropdownContainer: {
    width: '100%',
    maxWidth: 320,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.15)',
    overflow: 'hidden',
  },
  dropdownBlur: {
    overflow: 'hidden',
  },
  dropdownItem: {
    paddingHorizontal: 16,
    paddingVertical: 14,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.05)',
  },
  dropdownItemContent: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  categoryIconContainer: {
    width: 32,
    height: 32,
    borderRadius: 8,
    backgroundColor: 'rgba(229,9,20,0.15)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  dropdownItemText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '500',
    flex: 1,
  },
  dropdownItemCount: {
    backgroundColor: 'rgba(255,255,255,0.1)',
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 12,
    minWidth: 28,
    alignItems: 'center',
  },
  dropdownItemCountText: {
    color: 'rgba(255,255,255,0.7)',
    fontSize: 12,
    fontWeight: '600',
  },
  scrollContent: {
    paddingHorizontal: 16,
    gap: CARD_SPACING,
    paddingRight: 32,
  },
  cardContainer: {
    alignItems: 'flex-start',
  },
  card: {
    borderRadius: 12,
    overflow: 'hidden',
    backgroundColor: 'rgba(255,255,255,0.03)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
  },
  thumbnailWrapper: {
    aspectRatio: 16 / 9,
    width: '100%',
  },
  thumbnail: {
    width: '100%',
    height: '100%',
  },
  thumbnailGradient: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0,0,0,0.15)',
  },
  trailerInfo: {
    width: '100%',
    paddingTop: 10,
    paddingHorizontal: 4,
  },
  trailerTitle: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '600',
    lineHeight: 18,
    marginBottom: 4,
  },
  trailerMeta: {
    color: 'rgba(255,255,255,0.5)',
    fontSize: 11,
    fontWeight: '500',
  },
  scrollIndicator: {
    width: 28,
    height: 28,
    justifyContent: 'center',
    alignItems: 'center',
    alignSelf: 'center',
    backgroundColor: 'rgba(0,0,0,0.3)',
    borderRadius: 14,
    marginLeft: 8,
  },
});
