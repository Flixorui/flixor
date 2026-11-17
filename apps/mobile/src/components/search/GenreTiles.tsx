/**
 * "Browse by Genre": 16:9 artwork tiles in two columns; a tap opens Discover with
 * that genre picked. Same genres and images as macOS.
 * macOS reference: Views/Search/SearchView.swift (SearchGenreTiles)
 */

import React from 'react';
import { Pressable, StyleSheet, Text, useWindowDimensions, View, type ImageSourcePropType } from 'react-native';
import { Image } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';

export type GenreTile = { id: number; name: string; image: ImageSourcePropType };

/** TMDB movie genres. */
export const SEARCH_GENRES: GenreTile[] = [
  { id: 28, name: 'Action', image: require('../../../assets/genres/genre-action.jpg') },
  { id: 35, name: 'Comedy', image: require('../../../assets/genres/genre-comedy.jpg') },
  { id: 18, name: 'Drama', image: require('../../../assets/genres/genre-drama.jpg') },
  { id: 878, name: 'Science Fiction', image: require('../../../assets/genres/genre-science-fiction.jpg') },
  { id: 53, name: 'Thriller', image: require('../../../assets/genres/genre-thriller.jpg') },
  { id: 27, name: 'Horror', image: require('../../../assets/genres/genre-horror.jpg') },
  { id: 16, name: 'Animation', image: require('../../../assets/genres/genre-animation.jpg') },
  { id: 10749, name: 'Romance', image: require('../../../assets/genres/genre-romance.jpg') },
  { id: 80, name: 'Crime', image: require('../../../assets/genres/genre-crime.jpg') },
  { id: 14, name: 'Fantasy', image: require('../../../assets/genres/genre-fantasy.jpg') },
  { id: 10751, name: 'Family', image: require('../../../assets/genres/genre-family.jpg') },
  { id: 99, name: 'Documentary', image: require('../../../assets/genres/genre-documentary.jpg') },
];

const GUTTER = 16;
const GAP = 10;

export default function GenreTiles({ onSelect }: { onSelect: (genre: GenreTile) => void }) {
  const { width } = useWindowDimensions();
  // Two columns on a phone, more on wider screens.
  const columns = width >= 900 ? 4 : width >= 600 ? 3 : 2;
  const tileWidth = Math.floor((width - GUTTER * 2 - GAP * (columns - 1)) / columns);
  const tileHeight = Math.round((tileWidth * 9) / 16);

  return (
    <View style={styles.container}>
      <Text style={styles.heading}>Browse by Genre</Text>
      <View style={styles.grid}>
        {SEARCH_GENRES.map((genre) => (
          <Pressable
            key={genre.id}
            onPress={() => onSelect(genre)}
            accessibilityRole="button"
            accessibilityLabel={`Discover ${genre.name}`}
            style={({ pressed }) => [
              styles.tile,
              { width: tileWidth, height: tileHeight, transform: [{ scale: pressed ? 0.97 : 1 }] },
            ]}
          >
            {/* Explicit size: a local image with only absolute insets draws at its own size. */}
            <Image
              source={genre.image}
              style={{ position: 'absolute', top: 0, left: 0, width: tileWidth, height: tileHeight }}
              resizeMode="cover"
            />
            <LinearGradient
              colors={['rgba(0,0,0,0)', 'rgba(0,0,0,0.7)']}
              start={{ x: 0.5, y: 0.4 }}
              end={{ x: 0.5, y: 1 }}
              style={StyleSheet.absoluteFill}
            />
            <Text style={styles.label} numberOfLines={1}>
              {genre.name}
            </Text>
          </Pressable>
        ))}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { marginTop: 28 },
  heading: { color: '#fff', fontSize: 20, fontWeight: '800', marginHorizontal: GUTTER, marginBottom: 14 },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: GAP, paddingHorizontal: GUTTER },
  tile: {
    borderRadius: 10,
    overflow: 'hidden',
    backgroundColor: '#1a1a1a',
    justifyContent: 'flex-end',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.12)',
  },
  label: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '700',
    padding: 10,
    textShadowColor: 'rgba(0,0,0,0.5)',
    textShadowRadius: 3,
    textShadowOffset: { width: 0, height: 1 },
  },
});
