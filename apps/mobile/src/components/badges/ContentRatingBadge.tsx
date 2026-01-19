import React from 'react';
import { View, Text, Image, StyleSheet, ImageSourcePropType } from 'react-native';

interface ContentRatingBadgeProps {
  rating: string;
  size?: number;
}

// Content rating image assets
const ratingImages: Record<string, ImageSourcePropType> = {
  'g': require('../../../assets/badges/g.png'),
  'pg': require('../../../assets/badges/pg.png'),
  'pg13': require('../../../assets/badges/pg13.png'),
  'r': require('../../../assets/badges/r.png'),
  'tvg': require('../../../assets/badges/tvg.png'),
  'tvpg': require('../../../assets/badges/tvpg.png'),
  'tv14': require('../../../assets/badges/tv14.png'),
  'tvma': require('../../../assets/badges/tvma.png'),
  'unrated': require('../../../assets/badges/unrated.png'),
};

// Map rating string to image key
const getRatingImageKey = (rating: string): string | null => {
  const normalized = rating.toLowerCase().replace(/-/g, '').replace(/ /g, '').trim();

  switch (normalized) {
    case 'g':
      return 'g';
    case 'pg':
      return 'pg';
    case 'pg13':
      return 'pg13';
    case 'r':
    case 'ratedr':
      return 'r';
    case 'tvg':
      return 'tvg';
    case 'tvpg':
      return 'tvpg';
    case 'tv14':
      return 'tv14';
    case 'tvma':
      return 'tvma';
    case 'nr':
    case 'unrated':
    case 'notrated':
      return 'unrated';
    default:
      return null;
  }
};

// Fallback styling for ratings without images
const getRatingStyle = (rating: string): { bg: string; text: string; border?: string } => {
  const normalized = rating.toUpperCase().replace(/-/g, '');

  switch (normalized) {
    case 'G':
      return { bg: '#2ecc71', text: '#fff' };
    case 'PG':
      return { bg: '#f39c12', text: '#fff' };
    case 'PG13':
      return { bg: '#e67e22', text: '#fff' };
    case 'R':
      return { bg: '#e74c3c', text: '#fff' };
    case 'NC17':
      return { bg: '#c0392b', text: '#fff' };
    case 'TVY':
    case 'TVY7':
      return { bg: '#2ecc71', text: '#fff' };
    case 'TVG':
      return { bg: '#27ae60', text: '#fff' };
    case 'TVPG':
      return { bg: '#f39c12', text: '#fff' };
    case 'TV14':
      return { bg: '#e67e22', text: '#fff' };
    case 'TVMA':
      return { bg: '#e74c3c', text: '#fff' };
    case 'NR':
    case 'UNRATED':
    case 'NOTRATED':
      return { bg: '#7f8c8d', text: '#fff' };
    default:
      return { bg: '#34495e', text: '#fff', border: '#fff' };
  }
};

// Format the rating text for display (fallback)
const formatRating = (rating: string): string => {
  const normalized = rating.toUpperCase().replace(/-/g, '');

  switch (normalized) {
    case 'PG13': return 'PG-13';
    case 'NC17': return 'NC-17';
    case 'TVY': return 'TV-Y';
    case 'TVY7': return 'TV-Y7';
    case 'TVG': return 'TV-G';
    case 'TVPG': return 'TV-PG';
    case 'TV14': return 'TV-14';
    case 'TVMA': return 'TV-MA';
    case 'NR': return 'NR';
    case 'UNRATED': return 'NR';
    case 'NOTRATED': return 'NR';
    default: return rating.toUpperCase();
  }
};

const ContentRatingBadge: React.FC<ContentRatingBadgeProps> = ({ rating, size = 18 }) => {
  const imageKey = getRatingImageKey(rating);
  let pg13Size = false;
  let pgSize = false;
  if (imageKey === 'pg13' || imageKey === 'unrated' || imageKey === 'tvma' || imageKey === 'tvpg' || imageKey === 'tv14' || imageKey === 'tvg') {
    pg13Size = true;
  }
  if (imageKey === 'pg') {
    pgSize = true;
  }
  // If we have an image for this rating, use it
  if (imageKey && ratingImages[imageKey]) {
    return (
      <View style={styles.container}>
        <Image
          source={ratingImages[imageKey]}
          style={{ height: pg13Size ? 20 : pgSize ? 16 : size, width: pg13Size ? 20*1.5 : pgSize ? 16*1.5 : size * 1.5 }}
          resizeMode="contain"
        />
      </View>
    );
  }

  // Fallback to text-based badge
  const style = getRatingStyle(rating);
  const displayRating = formatRating(rating);

  return (
    <View style={[
      styles.badge,
      {
        backgroundColor: style.bg,
        borderColor: style.border || style.bg,
        borderWidth: style.border ? 1 : 0,
      }
    ]}>
      <Text style={[
        styles.badgeText,
        {
          color: style.text,
          fontSize: size * 0.7,
        }
      ]}>
        {displayRating}
      </Text>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  badge: {
    paddingHorizontal: 6,
    paddingVertical: 3,
    borderRadius: 4,
    justifyContent: 'center',
    alignItems: 'center',
  },
  badgeText: {
    fontWeight: '700',
    letterSpacing: 0.3,
  },
});

export default ContentRatingBadge;
