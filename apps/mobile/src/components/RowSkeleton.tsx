import React, { useEffect, useRef } from 'react';
import { View, Animated, StyleSheet, Dimensions } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { useAppSettings } from '../hooks/useAppSettings';

const { width: SCREEN_WIDTH } = Dimensions.get('window');

const POSTER_SIZES = {
  small: { width: 96, height: 144 },
  medium: { width: 110, height: 165 },
  large: { width: 128, height: 192 },
} as const;

interface RowSkeletonProps {
  title?: string;
  itemCount?: number;
}

function RowSkeleton({ title, itemCount = 5 }: RowSkeletonProps) {
  const { settings } = useAppSettings();
  const size = POSTER_SIZES[settings.posterSize] || POSTER_SIZES.medium;
  const borderRadius = settings.posterBorderRadius || 8;

  const shimmerAnim = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    const animation = Animated.loop(
      Animated.timing(shimmerAnim, {
        toValue: 1,
        duration: 1500,
        useNativeDriver: true,
      })
    );
    animation.start();
    return () => animation.stop();
  }, [shimmerAnim]);

  const translateX = shimmerAnim.interpolate({
    inputRange: [0, 1],
    outputRange: [-SCREEN_WIDTH, SCREEN_WIDTH],
  });

  const renderSkeletonCard = (index: number) => (
    <View
      key={index}
      style={[
        styles.posterContainer,
        {
          width: size.width,
          height: size.height,
          borderRadius,
          marginRight: 12,
        },
      ]}
    >
      <Animated.View
        style={[
          styles.shimmer,
          {
            transform: [{ translateX }],
          },
        ]}
      >
        <LinearGradient
          colors={['rgba(34,34,34,0)', 'rgba(60,60,60,0.8)', 'rgba(34,34,34,0)']}
          start={{ x: 0, y: 0.5 }}
          end={{ x: 1, y: 0.5 }}
          style={StyleSheet.absoluteFill}
        />
      </Animated.View>
    </View>
  );

  return (
    <View style={styles.container}>
      {/* Title skeleton or actual title */}
      <View style={styles.header}>
        {title ? (
          <View style={styles.titleText}>
            <Animated.View style={[styles.titleSkeleton, { width: title.length * 8 }]}>
              <Animated.View
                style={[
                  styles.shimmer,
                  { transform: [{ translateX }] },
                ]}
              >
                <LinearGradient
                  colors={['rgba(51,51,51,0)', 'rgba(80,80,80,0.8)', 'rgba(51,51,51,0)']}
                  start={{ x: 0, y: 0.5 }}
                  end={{ x: 1, y: 0.5 }}
                  style={StyleSheet.absoluteFill}
                />
              </Animated.View>
            </Animated.View>
          </View>
        ) : (
          <View style={[styles.titleSkeleton, { width: 120 }]}>
            <Animated.View
              style={[
                styles.shimmer,
                { transform: [{ translateX }] },
              ]}
            >
              <LinearGradient
                colors={['rgba(51,51,51,0)', 'rgba(80,80,80,0.8)', 'rgba(51,51,51,0)']}
                start={{ x: 0, y: 0.5 }}
                end={{ x: 1, y: 0.5 }}
                style={StyleSheet.absoluteFill}
              />
            </Animated.View>
          </View>
        )}
      </View>

      {/* Poster skeletons */}
      <View style={styles.postersContainer}>
        {Array.from({ length: itemCount }).map((_, index) => renderSkeletonCard(index))}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    marginBottom: 16,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 15,
    marginTop: 15,
    paddingHorizontal: 16,
  },
  titleText: {
    height: 20,
  },
  titleSkeleton: {
    height: 16,
    backgroundColor: '#333',
    borderRadius: 4,
    overflow: 'hidden',
  },
  postersContainer: {
    flexDirection: 'row',
    paddingHorizontal: 16,
  },
  posterContainer: {
    backgroundColor: '#222',
    overflow: 'hidden',
  },
  shimmer: {
    ...StyleSheet.absoluteFillObject,
    width: SCREEN_WIDTH * 2,
  },
});

export default React.memo(RowSkeleton);
