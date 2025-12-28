import React from 'react';
import Svg, { Path } from 'react-native-svg';

interface PlexIconProps {
  size?: number;
  color?: string;
}

const PlexIcon: React.FC<PlexIconProps> = ({ size = 24, color = '#e5e7eb' }) => {
  return (
    <Svg width={size} height={size} viewBox="0 0 512 512">
      <Path
        d="m256 70h-108l108 186-108 186h108l108-186z"
        fill={color}
      />
    </Svg>
  );
};

export default PlexIcon;
