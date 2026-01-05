import React from 'react';
import Svg, { Path, Defs, LinearGradient, Stop } from 'react-native-svg';

interface OverseerrIconProps {
  size?: number;
  color?: string;
}

export default function OverseerrIcon({ size = 24, color }: OverseerrIconProps) {
  // If color is provided, use monochrome version
  if (color) {
    return (
      <Svg width={size} height={size} viewBox="0 0 96 96" fill="none">
        <Path
          fillRule="evenodd"
          clipRule="evenodd"
          d="M48 96C74.5097 96 96 74.5097 96 48C96 21.4903 74.5097 0 48 0C21.4903 0 0 21.4903 0 48C0 74.5097 21.4903 96 48 96ZM80.0001 52C80.0001 67.464 67.4641 80 52.0001 80C36.5361 80 24.0001 67.464 24.0001 52C24.0001 49.1303 24.4318 46.3615 25.2338 43.7548C27.4288 48.6165 32.3194 52 38.0001 52C45.7321 52 52.0001 45.732 52.0001 38C52.0001 32.3192 48.6166 27.4287 43.755 25.2337C46.3616 24.4317 49.1304 24 52.0001 24C67.4641 24 80.0001 36.536 80.0001 52Z"
          fill={color}
        />
      </Svg>
    );
  }

  // Default gradient version
  return (
    <Svg width={size} height={size} viewBox="0 0 96 96" fill="none">
      <Path
        fillRule="evenodd"
        clipRule="evenodd"
        d="M48 96C74.5097 96 96 74.5097 96 48C96 21.4903 74.5097 0 48 0C21.4903 0 0 21.4903 0 48C0 74.5097 21.4903 96 48 96ZM80.0001 52C80.0001 67.464 67.4641 80 52.0001 80C36.5361 80 24.0001 67.464 24.0001 52C24.0001 49.1303 24.4318 46.3615 25.2338 43.7548C27.4288 48.6165 32.3194 52 38.0001 52C45.7321 52 52.0001 45.732 52.0001 38C52.0001 32.3192 48.6166 27.4287 43.755 25.2337C46.3616 24.4317 49.1304 24 52.0001 24C67.4641 24 80.0001 36.536 80.0001 52Z"
        fill="url(#overseerr_gradient)"
      />
      <Path
        fillRule="evenodd"
        clipRule="evenodd"
        d="M80.0002 52C80.0002 67.464 67.4642 80 52.0002 80C36.864 80 24.5329 67.9897 24.017 52.9791C24.0057 53.318 24 53.6583 24 54C24 70.5685 37.4315 84 54 84C70.5685 84 84 70.5685 84 54C84 37.4315 70.5685 24 54 24C53.6597 24 53.3207 24.0057 52.9831 24.0169C67.9919 24.5347 80.0002 36.865 80.0002 52Z"
        fill="#131928"
        fillOpacity={0.2}
      />
      <Defs>
        <LinearGradient
          id="overseerr_gradient"
          x1="48"
          y1="0"
          x2="117.5"
          y2="69.5"
          gradientUnits="userSpaceOnUse"
        >
          <Stop stopColor="#C395FC" />
          <Stop offset="1" stopColor="#4F65F5" />
        </LinearGradient>
      </Defs>
    </Svg>
  );
}
