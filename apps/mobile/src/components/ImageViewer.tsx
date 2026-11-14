/**
 * Full-screen image viewer above everything (no back button or tab bar
 * showing): solid black, × at the top right, "4 / 5", a thumbnail strip,
 * swipe between images, pinch or double-tap to zoom, swipe down to close.
 * Loads only the full image: a thumbnail placeholder under it left a doubled
 * watermark on Blu-ray.com screenshots.
 * macOS reference: Views/Components/ImageViewer.swift
 */
import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  Modal,
  Pressable,
  ScrollView,
  StatusBar,
  StyleSheet,
  Text,
  useWindowDimensions,
  View,
  type NativeScrollEvent,
  type NativeSyntheticEvent,
} from 'react-native';
import FastImage from '@d11/react-native-fast-image';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { RoundGlassButton } from './GlassPill';

export interface ImageViewerItem {
  url: string;
  thumbnail?: string;
  caption?: string;
}

export default function ImageViewer({
  items,
  index,
  onClose,
}: {
  items: ImageViewerItem[];
  /** Shown when not null. */
  index: number | null;
  onClose: () => void;
}) {
  const { width, height } = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const listRef = useRef<FlatList<ImageViewerItem>>(null);
  const thumbsRef = useRef<FlatList<ImageViewerItem>>(null);
  const [current, setCurrent] = useState(index ?? 0);

  useEffect(() => {
    if (index != null) setCurrent(index);
  }, [index]);

  useEffect(() => {
    if (items.length > 1) thumbsRef.current?.scrollToIndex({ index: current, viewPosition: 0.5, animated: true });
  }, [current, items.length]);

  const go = useCallback(
    (to: number) => {
      const next = Math.max(0, Math.min(items.length - 1, to));
      setCurrent(next);
      listRef.current?.scrollToIndex({ index: next, animated: true });
    },
    [items.length]
  );

  const onMomentumEnd = (e: NativeSyntheticEvent<NativeScrollEvent>) => {
    const page = Math.round(e.nativeEvent.contentOffset.x / width);
    if (page !== current) setCurrent(page);
  };

  if (index == null) return null;
  const item = items[current];
  const showThumbs = items.length > 1;

  return (
    <Modal visible transparent={false} animationType="fade" statusBarTranslucent supportedOrientations={['portrait', 'landscape']} onRequestClose={onClose}>
      <StatusBar hidden />
      <View style={styles.root}>
        <FlatList
          ref={listRef}
          data={items}
          horizontal
          pagingEnabled
          initialScrollIndex={index}
          getItemLayout={(_, i) => ({ length: width, offset: width * i, index: i })}
          keyExtractor={(it, i) => `${it.url}-${i}`}
          showsHorizontalScrollIndicator={false}
          onMomentumScrollEnd={onMomentumEnd}
          renderItem={({ item: it }) => <ZoomableImage uri={it.url} width={width} height={height} onClose={onClose} />}
        />

        <View style={[styles.topBar, { top: insets.top + 8 }]} pointerEvents="box-none">
          <Text style={styles.counter} accessibilityLabel={`Image ${current + 1} of ${items.length}`}>
            {items.length > 1 ? `${current + 1} / ${items.length}` : ''}
          </Text>
          <RoundGlassButton icon="close" label="Close" size={38} iconSize={22} onPress={onClose} />
        </View>

        <View style={[styles.bottom, { paddingBottom: insets.bottom + 12 }]} pointerEvents="box-none">
          {item?.caption ? <Text style={styles.caption}>{item.caption}</Text> : null}
          {showThumbs ? (
            <FlatList
              ref={thumbsRef}
              data={items}
              horizontal
              keyExtractor={(it, i) => `t-${it.url}-${i}`}
              showsHorizontalScrollIndicator={false}
              contentContainerStyle={{ paddingHorizontal: 16, gap: 8 }}
              getItemLayout={(_, i) => ({ length: 72, offset: 16 + 72 * i, index: i })}
              onScrollToIndexFailed={() => undefined}
              renderItem={({ item: it, index: i }) => (
                <Pressable onPress={() => go(i)} accessibilityRole="button" accessibilityLabel={`Show image ${i + 1}`}>
                  <FastImage
                    source={{ uri: it.thumbnail ?? it.url }}
                    style={[styles.thumb, i === current && styles.thumbActive]}
                    resizeMode={FastImage.resizeMode.cover}
                  />
                </Pressable>
              )}
            />
          ) : null}
        </View>
      </View>
    </Modal>
  );
}

/** One page: pinch to zoom (native scroll-view zoom), double-tap toggles, pull down closes. */
function ZoomableImage({ uri, width, height, onClose }: { uri: string; width: number; height: number; onClose: () => void }) {
  const scrollRef = useRef<ScrollView>(null);
  const [loading, setLoading] = useState(true);
  const zoomed = useRef(false);
  const lastTap = useRef(0);

  const onTap = () => {
    const now = Date.now();
    if (now - lastTap.current < 280) {
      zoomed.current = !zoomed.current;
      (scrollRef.current as any)?.scrollResponderZoomTo?.(
        zoomed.current
          ? { x: width / 4, y: height / 4, width: width / 2, height: height / 2, animated: true }
          : { x: 0, y: 0, width, height, animated: true }
      );
    }
    lastTap.current = now;
  };

  return (
    <ScrollView
      ref={scrollRef}
      style={{ width, height }}
      contentContainerStyle={{ width, height, alignItems: 'center', justifyContent: 'center' }}
      maximumZoomScale={4}
      minimumZoomScale={1}
      bouncesZoom
      alwaysBounceVertical
      showsHorizontalScrollIndicator={false}
      showsVerticalScrollIndicator={false}
      centerContent
      onScroll={(e) => {
        zoomed.current = e.nativeEvent.zoomScale > 1.01;
      }}
      scrollEventThrottle={32}
      onScrollEndDrag={(e) => {
        const { zoomScale, contentOffset } = e.nativeEvent;
        if (zoomScale <= 1.01 && contentOffset.y < -90) onClose();
      }}
    >
      <Pressable onPress={onTap} style={{ width, height, alignItems: 'center', justifyContent: 'center' }} accessibilityLabel="Image">
        <FastImage
          source={{ uri, priority: FastImage.priority.high }}
          style={{ width, height }}
          resizeMode={FastImage.resizeMode.contain}
          onLoadEnd={() => setLoading(false)}
        />
        {loading ? <ActivityIndicator color="rgba(255,255,255,0.7)" style={StyleSheet.absoluteFill} /> : null}
      </Pressable>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#000' },
  topBar: { position: 'absolute', left: 16, right: 16, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  counter: { color: 'rgba(255,255,255,0.85)', fontSize: 15, fontWeight: '600', fontVariant: ['tabular-nums'] },
  bottom: { position: 'absolute', left: 0, right: 0, bottom: 0, gap: 10 },
  caption: { color: 'rgba(255,255,255,0.8)', fontSize: 14, textAlign: 'center', paddingHorizontal: 24 },
  thumb: { width: 64, height: 40, borderRadius: 6, opacity: 0.5, backgroundColor: '#111' },
  thumbActive: { opacity: 1, borderWidth: 2, borderColor: '#fff' },
});
