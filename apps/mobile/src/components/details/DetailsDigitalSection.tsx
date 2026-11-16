/**
 * Digital Releases on Details (films and shows, US): a specs strip, then
 * Stream / Rent / Buy rows of store pills with the official logo, lowest
 * price and a 4K tag. Each pill opens the store. On a phone the labels sit
 * above their pills.
 * macOS reference: DetailsWhereToWatchSection in Views/Details/DetailsPhysicalSection.swift
 */
import React from 'react';
import { Linking, Pressable, StyleSheet, Text, View } from 'react-native';
import FastImage from '@d11/react-native-fast-image';
import DetailsSectionHeading, { DetailsSectionStyle } from './DetailsSectionHeading';
import type { DigitalReleases, DigitalStore } from '../../core/mybluray/digitalReleases';

const TILE = 24;

export default function DetailsDigitalSection({ releases }: { releases: DigitalReleases }) {
  const groups: [string, DigitalStore[]][] = [
    ['Stream', releases.stream],
    ['Rent', releases.rent],
    ['Buy', releases.buy],
  ];
  return (
    <View>
      <DetailsSectionHeading title="Digital Releases" detail="United States" />
      {releases.specs.length ? (
        <View style={styles.specs}>
          {releases.specs.map((spec) => (
            <Text key={spec.title} style={styles.specTitle}>
              {spec.title}
              {spec.detail ? <Text style={styles.specDetail}>{`  ${spec.detail}`}</Text> : null}
            </Text>
          ))}
        </View>
      ) : null}
      {groups.filter(([, stores]) => stores.length).map(([label, stores]) => (
        <View key={label}>
          <Text style={styles.label}>{label.toUpperCase()}</Text>
          <View style={styles.pills}>
            {stores.map((store) => <StorePill key={store.id} store={store} />)}
          </View>
        </View>
      ))}
    </View>
  );
}

function StorePill({ store }: { store: DigitalStore }) {
  const price = store.priceText || (store.price != null ? `$${store.price.toFixed(2)}` : null);
  const label = [store.name, price, store.quality === '4K' ? '4K' : null].filter(Boolean).join(', ');
  return (
    <Pressable
      onPress={store.url ? () => Linking.openURL(store.url!).catch(() => undefined) : undefined}
      disabled={!store.url}
      accessibilityRole={store.url ? 'link' : 'text'}
      accessibilityLabel={label}
      style={({ pressed }) => [styles.pill, pressed && { opacity: 0.7 }]}
    >
      <StoreTile store={store} />
      <Text style={styles.name} numberOfLines={1}>{store.name}</Text>
      {price ? <Text style={styles.price}>{price}</Text> : null}
      {store.quality === '4K' ? (
        <View style={styles.badge}>
          <Text style={styles.badgeText}>4K</Text>
        </View>
      ) : null}
    </Pressable>
  );
}

/** TMDB's square app icon fills the tile; Apple's glyph sits inside a dark one; otherwise initials. */
function StoreTile({ store }: { store: DigitalStore }) {
  if (store.logo) {
    return (
      <View style={[styles.tile, !store.logoIsIcon && styles.tileDark]}>
        <FastImage
          source={{ uri: store.logo, cache: FastImage.cacheControl.immutable }}
          style={store.logoIsIcon ? StyleSheet.absoluteFill : { width: TILE - 8, height: TILE - 8 }}
          resizeMode={store.logoIsIcon ? 'cover' : 'contain'}
        />
      </View>
    );
  }
  const initials = store.name.split(/\s+/).slice(0, 2).map((w) => w[0]).join('').toUpperCase().slice(0, 2);
  return (
    <View style={[styles.tile, styles.tileInitials]}>
      <Text style={styles.initials}>{initials}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  specs: {
    marginHorizontal: DetailsSectionStyle.inset,
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderRadius: 12,
    gap: 4,
    backgroundColor: 'rgba(255,255,255,0.06)',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.1)',
  },
  specTitle: { color: '#fff', fontSize: 14, fontWeight: '600' },
  specDetail: { color: 'rgba(255,255,255,0.6)', fontWeight: '400' },
  label: {
    color: 'rgba(255,255,255,0.5)',
    fontSize: 12,
    fontWeight: '600',
    letterSpacing: 0.4,
    paddingHorizontal: DetailsSectionStyle.inset,
    marginTop: 14,
    marginBottom: 6,
  },
  pills: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, paddingHorizontal: DetailsSectionStyle.inset },
  pill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 7,
    height: 36,
    paddingLeft: 6,
    paddingRight: 12,
    borderRadius: 12,
    backgroundColor: 'rgba(255,255,255,0.1)',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.16)',
    maxWidth: '100%',
  },
  tile: { width: TILE, height: TILE, borderRadius: 6, overflow: 'hidden', alignItems: 'center', justifyContent: 'center' },
  tileDark: { backgroundColor: '#1c1c1e' },
  tileInitials: { backgroundColor: '#3a3a3e' },
  initials: { color: '#ddd', fontSize: 10, fontWeight: '700' },
  name: { color: '#fff', fontSize: 14, fontWeight: '600', flexShrink: 1 },
  price: { color: 'rgba(255,255,255,0.75)', fontSize: 14 },
  badge: { borderWidth: 1, borderColor: 'rgba(255,255,255,0.4)', borderRadius: 4, paddingHorizontal: 4 },
  badgeText: { color: 'rgba(255,255,255,0.85)', fontSize: 10, fontWeight: '700' },
});
