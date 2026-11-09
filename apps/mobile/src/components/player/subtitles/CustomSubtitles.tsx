import React from 'react';
import { StyleSheet, Text, View, useWindowDimensions } from 'react-native';

type Props = {
  enabled: boolean;
  text: string;
  controlsVisible?: boolean;
  /** mpv scale: text height is this many units of a 720-unit-tall screen. */
  fontSize?: number;
  color?: string;
  borderSize?: number;
  /** mpv sub-pos: 0 is the top of the screen, 100 the bottom baseline. */
  position?: number;
};

const OUTLINE_DIRECTIONS = [
  [-1, -1],
  [1, -1],
  [-1, 1],
  [1, 1],
  [-1, 0],
  [1, 0],
  [0, -1],
  [0, 1],
];
const BOTTOM_BASELINE = 42;
const RAISED_ABOVE_CONTROLS = 120;

export default function CustomSubtitles({
  enabled,
  text,
  controlsVisible,
  fontSize = 55,
  color = '#FFFFFF',
  borderSize = 3,
  position = 100,
}: Props) {
  const { height } = useWindowDimensions();
  if (!enabled || !text) {
    return null;
  }

  // Same scale as mpv, so addon and embedded subtitles match at one setting.
  const scale = height / 720;
  const size = Math.max(10, fontSize * scale);
  const outline = borderSize * scale;
  const fromBottom = BOTTOM_BASELINE + ((100 - position) / 100) * Math.max(0, height - BOTTOM_BASELINE * 2 - size);
  const bottom = controlsVisible ? Math.max(fromBottom, RAISED_ABOVE_CONTROLS) : Math.max(fromBottom, 8);
  const textStyle = [styles.text, { fontSize: size, lineHeight: size * 1.25 }];

  return (
    <View pointerEvents="none" style={[styles.container, { bottom }]}>
      <View style={styles.textBox}>
        {outline > 0
          ? OUTLINE_DIRECTIONS.map(([x, y]) => (
              <Text
                key={`${x}:${y}`}
                style={[
                  textStyle,
                  styles.outline,
                  { transform: [{ translateX: x * outline }, { translateY: y * outline }] },
                ]}
              >
                {text}
              </Text>
            ))
          : null}
        <Text style={[textStyle, { color }]}>{text}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    left: 16,
    right: 16,
    alignItems: 'center',
  },
  textBox: {
    maxWidth: '94%',
  },
  text: {
    textAlign: 'center',
    fontWeight: '700',
  },
  outline: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: 0,
    color: '#000000',
  },
});
