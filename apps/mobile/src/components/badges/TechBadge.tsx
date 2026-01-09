import React from 'react';
import { View, Image, StyleSheet, ImageSourcePropType } from 'react-native';

type TechBadgeType = '4k' | 'hd' | '720p' | 'dolby-vision' | 'dolby-atmos' | 'hdr' | 'hdr10' | 'hdr10+' | 'hlg' | 'cc' | 'sdh' | 'ad' | 'atmos' | '5.1' | '7.1';

interface TechBadgeProps {
  type: TechBadgeType;
  size?: number;
}

// Badge image assets
const badgeImages: Record<string, ImageSourcePropType> = {
  '4k': require('../../../assets/badges/4k.png'),
  'hd': require('../../../assets/badges/hd.png'),
  'dolby-vision': require('../../../assets/badges/dolby-vision.png'),
  'dolby-atmos': require('../../../assets/badges/dolby-atmos.png'),
  'cc': require('../../../assets/badges/cc.png'),
  'sdh': require('../../../assets/badges/sdh.png'),
  'ad': require('../../../assets/badges/ad.png'),
  'hdr': require('../../../assets/badges/hdr.png'),
  'hdr10plus': require('../../../assets/badges/hdr10plus.png'),
};

const TechBadge: React.FC<TechBadgeProps> = ({ type, size = 18 }) => {
  // Map aliases to main badge types
  const normalizedType = (() => {
    switch (type) {
      case 'atmos':
        return 'dolby-atmos';
      case '720p':
        return 'hd'; // Use HD badge for 720p
      case 'hdr':
      case 'hdr10':
      case 'hlg':
        return 'hdr'; // Use generic HDR badge for HDR10 and HLG
      case 'hdr10+':
        return 'hdr10plus'; // HDR10+ has its own badge
      case '5.1':
      case '7.1':
        // Audio channel badges don't have custom images yet
        return null;
      default:
        return type;
    }
  })();

  // If no image available for this type, return null
  if (!normalizedType || !badgeImages[normalizedType]) {
    return null;
  }

  return (
    <View style={styles.container}>
      <Image
        source={badgeImages[normalizedType]}
        style={{ height: size, width: size * 2.5 }}
        resizeMode="contain"
      />
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    justifyContent: 'center',
    alignItems: 'center',
  },
});

export default TechBadge;
