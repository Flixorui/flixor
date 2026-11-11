/**
 * The Flixor "F" mark: the first letter of the wordmark (assets/logo.svg), in its red
 * gradient. Used beside the page title on Home, the way Netflix shows its N.
 */

import React from 'react';
import Svg, { Defs, LinearGradient, Path, Stop } from 'react-native-svg';

// From assets/logo.svg: the F occupies a 45 x 60 box
const F_PATH = 'M 0,60 L 0,0 L 45,0 L 45,15 L 18,15 L 18,25 L 40,25 L 40,40 L 18,40 L 18,60 Z';

export default function FlixorMark({ height = 30 }: { height?: number }) {
  const width = (height * 45) / 60;
  return (
    <Svg width={width} height={height} viewBox="0 0 45 60" accessibilityLabel="Flixor">
      <Defs>
        <LinearGradient id="flixorMarkRed" x1="0" y1="0" x2="1" y2="0">
          <Stop offset="0" stopColor="#E50914" />
          <Stop offset="1" stopColor="#B20710" />
        </LinearGradient>
      </Defs>
      <Path d={F_PATH} fill="url(#flixorMarkRed)" />
    </Svg>
  );
}
