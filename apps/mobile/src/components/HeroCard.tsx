import React from 'react';
import { View, Text, Pressable, Alert, StyleSheet, ActivityIndicator } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import FastImage from '@d11/react-native-fast-image';

type Hero = {
  title: string;
  subtitle?: string; // e.g., "#2 in Movies Today"
  imageUri?: string;
  logoUri?: string;
};

type HeroCardProps = {
  hero: Hero;
  authHeaders?: Record<string, string>;
  onAdd?: () => void;
  inWatchlist?: boolean;
  watchlistLoading?: boolean;
};

function HeroCard({ hero, authHeaders, onAdd, inWatchlist = false, watchlistLoading = false }: HeroCardProps) {
  return (
    <View style={{ paddingHorizontal: 16, marginTop: 8 }}>
      <View style={{ borderRadius: 12, overflow: 'hidden', backgroundColor: '#111', shadowColor: '#000', shadowOpacity: 0.35, shadowRadius: 12, shadowOffset: { width: 0, height: 6 }, elevation: 8 }}>
        {/* Image container - wider aspect ratio like Netflix hero cards */}
        <View style={{ width: '100%', aspectRatio: 0.78 }}>
          {hero.imageUri ? (
            <FastImage
              source={{
                uri: hero.imageUri,
                headers: authHeaders,
                priority: FastImage.priority.high,
                cache: FastImage.cacheControl.immutable,
              }}
              style={{ width: '100%', height: '100%' }}
              resizeMode={FastImage.resizeMode.cover}
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

        {/* List button - top right corner */}
        <Pressable
          onPress={onAdd || (() => Alert.alert('My List', 'TODO'))}
          disabled={watchlistLoading}
          style={{
            position: 'absolute',
            top: 12,
            right: 12,
            width: 36,
            height: 36,
            borderRadius: 18,
            backgroundColor: 'rgba(0,0,0,0.5)',
            alignItems: 'center',
            justifyContent: 'center',
            borderWidth: 1,
            borderColor: 'rgba(255,255,255,0.2)',
            opacity: watchlistLoading ? 0.6 : 1,
          }}
        >
          {watchlistLoading ? (
            <ActivityIndicator size="small" color="#fff" />
          ) : (
            <Ionicons name={inWatchlist ? 'bookmark' : 'bookmark-outline'} size={20} color="#fff" />
          )}
        </Pressable>

        {/* Content overlay at bottom */}
        <View style={{ position: 'absolute', bottom: 0, left: 0, right: 0, paddingHorizontal: 20, paddingBottom: 20 }}>
          {/* Logo or Title */}
          {hero.logoUri ? (
            <View style={{ alignItems: 'center', width: '100%' }}>
              <FastImage
                source={{
                  uri: hero.logoUri,
                  headers: authHeaders,
                  priority: FastImage.priority.normal,
                  cache: FastImage.cacheControl.immutable,
                }}
                style={{ width: 240, height: 80 }}
                resizeMode={FastImage.resizeMode.contain}
              />
            </View>
          ) : (
            <>
              {/* Title (fallback when no logo) */}
              <Text style={{ color: '#fff', fontSize: 32, fontWeight: '900', letterSpacing: 1.5, textTransform: 'uppercase', marginBottom: 6, textShadowColor: 'rgba(0,0,0,0.8)', textShadowOffset: { width: 0, height: 2 }, textShadowRadius: 4, textAlign: 'center' }}>
                {hero.title}
              </Text>
            </>
          )}

          {/* Subtitle */}
          {hero.subtitle ? (
            <Text style={{ color: '#e0e0e0', fontSize: 13, fontWeight: '400', textAlign: 'center', width: '100%' }}>{hero.subtitle}</Text>
          ) : null}
        </View>
      </View>
    </View>
  );
}

export default React.memo(HeroCard);
