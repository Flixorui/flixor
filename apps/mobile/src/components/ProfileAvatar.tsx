import React from 'react';
import { View, Text, Image, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';

interface ProfileAvatarProps {
  thumb?: string;
  title: string;
  size?: number;
  isActive?: boolean;
  isRestricted?: boolean;
  isProtected?: boolean;
}

export default function ProfileAvatar({
  thumb,
  title,
  size = 80,
  isActive = false,
  isRestricted = false,
  isProtected = false,
}: ProfileAvatarProps) {
  const initial = title?.[0]?.toUpperCase() || '?';

  return (
    <View style={[styles.container, isActive && styles.containerActive]}>
      {thumb ? (
        <Image
          source={{ uri: thumb }}
          style={[
            styles.avatar,
            { width: size, height: size, borderRadius: size / 2 },
          ]}
        />
      ) : (
        <View
          style={[
            styles.placeholder,
            {
              width: size,
              height: size,
              borderRadius: size / 2,
              backgroundColor: getColorForInitial(initial),
            },
          ]}
        >
          <Text style={[styles.initial, { fontSize: size * 0.4 }]}>
            {initial}
          </Text>
        </View>
      )}

      {isProtected && (
        <View style={styles.lockBadge}>
          <Ionicons name="lock-closed" size={12} color="#fff" />
        </View>
      )}

      {isRestricted && (
        <View style={styles.kidsBadge}>
          <Text style={styles.kidsBadgeText}>KIDS</Text>
        </View>
      )}

      {isActive && (
        <View style={styles.activeBadge}>
          <Ionicons name="checkmark" size={12} color="#fff" />
        </View>
      )}
    </View>
  );
}

// Generate a consistent color based on the initial letter
function getColorForInitial(initial: string): string {
  const colors = [
    '#e74c3c', // red
    '#e67e22', // orange
    '#f1c40f', // yellow
    '#27ae60', // green
    '#3498db', // blue
    '#9b59b6', // purple
    '#1abc9c', // teal
    '#34495e', // dark gray
  ];
  const index = initial.charCodeAt(0) % colors.length;
  return colors[index];
}

const styles = StyleSheet.create({
  container: {
    position: 'relative',
    borderRadius: 100,
    borderWidth: 3,
    borderColor: 'transparent',
  },
  containerActive: {
    borderColor: '#e5a00d', // Plex orange
  },
  avatar: {
    backgroundColor: '#1a1b20',
  },
  placeholder: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  initial: {
    color: '#fff',
    fontWeight: '700',
  },
  lockBadge: {
    position: 'absolute',
    bottom: 0,
    right: 0,
    backgroundColor: '#3498db',
    borderRadius: 10,
    width: 20,
    height: 20,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 2,
    borderColor: '#0d0d0d',
  },
  kidsBadge: {
    position: 'absolute',
    top: 0,
    right: -4,
    backgroundColor: '#27ae60',
    borderRadius: 4,
    paddingHorizontal: 4,
    paddingVertical: 2,
    borderWidth: 2,
    borderColor: '#0d0d0d',
  },
  kidsBadgeText: {
    color: '#fff',
    fontSize: 8,
    fontWeight: '800',
  },
  activeBadge: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    backgroundColor: '#27ae60',
    borderRadius: 10,
    width: 20,
    height: 20,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 2,
    borderColor: '#0d0d0d',
  },
});
