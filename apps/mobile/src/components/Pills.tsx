import React from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { BlurView } from 'expo-blur';
import * as Haptics from 'expo-haptics';

type Props = {
  selected: 'all'|'movies'|'shows';
  onChange: (tab: 'all'|'movies'|'shows') => void;
  onOpenCategories?: () => void;
  onClose?: () => void;
  activeGenre?: string;
  onClearGenre?: () => void;
};

function Pill({ active, label, onPress }: { active?: boolean; label: string; onPress?: () => void }) {
  const handlePress = () => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    onPress?.();
  };

  return (
    <Pressable onPress={handlePress} style={{
      paddingHorizontal: 14,
      paddingVertical: 8,
      borderRadius: 999,
      borderWidth: 1,
      borderColor: '#4a4a4a',
      overflow: 'hidden',
      backgroundColor: active ? undefined : 'transparent',
    }}>
      {/* Blur background only when active */}
      {active && (
        <>
          <BlurView intensity={20} tint="dark" style={StyleSheet.absoluteFillObject} />
          <View style={[StyleSheet.absoluteFillObject, { backgroundColor: 'rgba(255,255,255,0.15)' }]} />
        </>
      )}
      <Text style={{ color: '#fff', fontWeight: '600' }}>{label}</Text>
    </Pressable>
  );
}

export default function Pills({ selected, onChange, onOpenCategories, onClose, activeGenre, onClearGenre }: Props) {
  return (
    <View style={{ flexDirection: 'row', paddingHorizontal: 0, paddingVertical: 6, alignItems: 'center' }}>
      {/* Render different layouts based on selected state */}
      {selected === 'all' && (
        <>
          <Pill label="Shows" active={false} onPress={() => onChange('shows')} />
          <View style={{ width: 8 }} />
          <Pill label="Movies" active={false} onPress={() => onChange('movies')} />
          <View style={{ width: 8 }} />
        </>
      )}
      
      {selected === 'shows' && (
        <>
          <Pressable onPress={() => { Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light); onClose && onClose(); onChange('all'); }} style={{ width: 36, height: 36, borderRadius: 18, borderWidth: 1, borderColor: '#4a4a4a', backgroundColor: 'transparent', alignItems: 'center', justifyContent: 'center', marginRight: 8 }}>
            <Ionicons name="close-outline" color="#fff" size={20} />
          </Pressable>
          <Pill label="Shows" active={true} onPress={() => onChange('shows')} />
          <View style={{ width: 8 }} />
          
        </>
      )}
      
      {selected === 'movies' && (
        <>
          <Pressable onPress={() => { Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light); onClose && onClose(); onChange('all'); }} style={{ width: 36, height: 36, borderRadius: 18, borderWidth: 1, borderColor: '#4a4a4a', backgroundColor: 'transparent', alignItems: 'center', justifyContent: 'center', marginRight: 8 }}>
            <Ionicons name="close-outline" color="#fff" size={20} />
          </Pressable>
          <Pill label="Movies" active={true} onPress={() => onChange('movies')} />
          <View style={{ width: 8 }} />
          
        </>
      )}
      
      {activeGenre ? (
        <>
          <Pressable
            onPress={() => {
              Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
              onClearGenre?.();
            }}
            style={{
              width: 36,
              height: 36,
              borderRadius: 18,
              borderWidth: 1,
              borderColor: '#4a4a4a',
              backgroundColor: 'transparent',
              alignItems: 'center',
              justifyContent: 'center',
              marginRight: 8
            }}
          >
            <Ionicons name="close-outline" color="#fff" size={20} />
          </Pressable>
          <Pressable
            onPress={() => { Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light); onOpenCategories?.(); }}
            style={{
              paddingHorizontal: 14,
              paddingVertical: 8,
              borderRadius: 999,
              borderWidth: 1,
              borderColor: '#4a4a4a',
              overflow: 'hidden',
            }}
          >
            <BlurView intensity={20} tint="dark" style={StyleSheet.absoluteFillObject} />
            <View style={[StyleSheet.absoluteFillObject, { backgroundColor: 'rgba(255,255,255,0.15)' }]} />
            <Text style={{ color: '#fff', fontWeight: '600' }}>{activeGenre}</Text>
          </Pressable>
        </>
      ) : (
        <Pressable onPress={() => { Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light); onOpenCategories?.(); }} style={{ flexDirection: 'row', alignItems: 'center', paddingHorizontal: 14, paddingVertical: 8, borderRadius: 999, borderWidth: 1, borderColor: '#4a4a4a', backgroundColor: 'transparent' }}>
          <Text style={{ color: '#fff', fontWeight: '600', marginRight: 6 }}>Categories</Text>
          <Ionicons name="chevron-down" color="#fff" size={16} />
        </Pressable>
      )}
    </View>
  );
}
