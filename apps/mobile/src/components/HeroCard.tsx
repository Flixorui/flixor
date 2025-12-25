import React from 'react';
import { View, Text, Pressable, Alert, StyleSheet, ActivityIndicator } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { Image as ExpoImage } from 'expo-image';

// Blurhash for hero images
const HERO_BLURHASH = 'L6PZfSi_.AyE_3t7t7R**0o#DgR4';

type Hero = {
  title: string;
  subtitle?: string; // e.g., "#2 in Movies Today"
  imageUri?: string;
  logoUri?: string;
};

type HeroCardProps = {
  hero: Hero;
  authHeaders?: Record<string, string>;
  onPlay?: () => void;
  onAdd?: () => void;
  inWatchlist?: boolean;
  watchlistLoading?: boolean;
};

export default function HeroCard({ hero, authHeaders, onPlay, onAdd, inWatchlist = false, watchlistLoading = false }: HeroCardProps) {
  return (
    <View style={{ paddingHorizontal: 16, marginTop: -40 }}>
      <View style={{ borderRadius: 12, overflow: 'hidden', backgroundColor: '#111', shadowColor: '#000', shadowOpacity: 0.35, shadowRadius: 12, shadowOffset: { width: 0, height: 6 }, elevation: 8 }}>
        {/* Image container - wider aspect ratio like Netflix hero cards */}
        <View style={{ width: '100%', aspectRatio: 0.78 }}>
          {hero.imageUri ? (
            <ExpoImage
              source={{ uri: hero.imageUri, headers: authHeaders }}
              placeholder={{ blurhash: HERO_BLURHASH }}
              style={{ width: '100%', height: '100%' }}
              contentFit="cover"
              cachePolicy="memory-disk"
              priority="high"
              transition={300}
            />
          ) : (
            <View style={{ flex:1, alignItems:'center', justifyContent:'center' }}>
              <Text style={{ color:'#666' }}>No Artwork</Text>
            </View>
          )}
        </View>

        {/* Bottom gradient overlay for better text/button visibility */}
        <LinearGradient
          colors={[ 'rgba(0,0,0,0)', 'rgba(0,0,0,0.7)', 'rgba(0,0,0,0.95)' ]}
          style={StyleSheet.absoluteFillObject}
          start={{ x: 0.5, y: 0.5 }}
          end={{ x: 0.5, y: 1 }}
          pointerEvents="none"
        />

        {/* Content overlay at bottom */}
        <View style={{ position: 'absolute', bottom: 0, left: 0, right: 0, paddingHorizontal: 20, paddingBottom: 20 }}>
          {/* Logo or Title */}
          {hero.logoUri ? (
            <View style={{ marginBottom: 12, alignItems: 'center', width: '100%' }}>
              <ExpoImage
                source={{ uri: hero.logoUri, headers: authHeaders }}
                style={{ width: 240, height: 80 }}
                contentFit="contain"
                cachePolicy="memory-disk"
                transition={200}
              />
            </View>
          ) : (
            <>
              {/* N SERIES badge (fallback when no logo) */}
              <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'center', marginBottom: 8, width: '100%' }}>
                <Text style={{ color: '#E50914', fontSize: 20, fontWeight: '900', letterSpacing: -0.5 }}>N</Text>
                <Text style={{ color: '#fff', fontSize: 11, fontWeight: '700', marginLeft: 6, letterSpacing: 0.5, textTransform: 'uppercase' }}>SERIES</Text>
              </View>

              {/* Title (fallback when no logo) */}
              <Text style={{ color: '#fff', fontSize: 32, fontWeight: '900', letterSpacing: 1.5, textTransform: 'uppercase', marginBottom: 6, textShadowColor: 'rgba(0,0,0,0.8)', textShadowOffset: { width: 0, height: 2 }, textShadowRadius: 4, textAlign: 'center' }}>
                {hero.title}
              </Text>
            </>
          )}

          {/* Subtitle */}
          {hero.subtitle ? (
            <Text style={{ color: '#e0e0e0', fontSize: 13, marginBottom: 14, fontWeight: '400', textAlign: 'center', width: '100%' }}>{hero.subtitle}</Text>
          ) : null}

          {/* Action buttons */}
          <View style={{ flexDirection: 'row', gap: 12 }}>
            <Pressable onPress={onPlay || (()=>Alert.alert('Play', 'TODO'))} style={{ flex: 1, backgroundColor: '#fff', paddingVertical: 12, borderRadius: 6, flexDirection: 'row', alignItems: 'center', justifyContent: 'center' }}>
              <Ionicons name="play" size={20} color="#000" style={{ marginRight: 8 }} />
              <Text style={{ color: '#000', fontWeight: '800', fontSize: 16 }}>Play</Text>
            </Pressable>
            <Pressable
              onPress={onAdd || (() => Alert.alert('My List', 'TODO'))}
              disabled={watchlistLoading}
              style={{
                flex: 1,
                backgroundColor: inWatchlist ? 'rgba(255,255,255,0.2)' : 'rgba(109,109,110,0.7)',
                paddingVertical: 12,
                borderRadius: 6,
                flexDirection: 'row',
                alignItems: 'center',
                justifyContent: 'center',
                opacity: watchlistLoading ? 0.6 : 1,
              }}
            >
              {watchlistLoading ? (
                <ActivityIndicator size="small" color="#fff" style={{ marginRight: 8 }} />
              ) : (
                <Ionicons name={inWatchlist ? 'checkmark' : 'add'} size={20} color="#fff" style={{ marginRight: 8 }} />
              )}
              <Text style={{ color: '#fff', fontWeight: '800', fontSize: 16 }}>
                {inWatchlist ? 'In List' : 'My List'}
              </Text>
            </Pressable>
          </View>
        </View>
      </View>
    </View>
  );
}
