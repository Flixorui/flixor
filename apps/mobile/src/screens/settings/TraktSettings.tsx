import React, { useEffect, useRef, useState } from 'react';
import { View, Text, ScrollView, Pressable, StyleSheet, Linking } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import {
  getTraktProfile,
  startTraktDeviceAuth,
  pollTraktToken,
  saveTraktTokens,
  signOutTrakt,
} from '../../core/SettingsData';

export default function TraktSettings() {
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const headerHeight = insets.top + 52;
  const [profile, setProfile] = useState<any | null>(null);
  const [deviceCode, setDeviceCode] = useState<any | null>(null);
  const pollRef = useRef<any>(null);

  useEffect(() => {
    (async () => {
      setProfile(await getTraktProfile());
    })();
    return () => {
      if (pollRef.current) clearInterval(pollRef.current);
    };
  }, []);

  const startAuth = async () => {
    const dc = await startTraktDeviceAuth();
    if (!dc) return;
    setDeviceCode(dc);
    Linking.openURL(dc.verification_url);

    if (pollRef.current) clearInterval(pollRef.current);
    pollRef.current = setInterval(async () => {
      try {
        const res = await pollTraktToken(dc.device_code);
        if (res && res.access_token) {
          await saveTraktTokens(res);
          clearInterval(pollRef.current);
          setDeviceCode(null);
          setProfile(await getTraktProfile());
        }
      } catch {}
    }, Math.max(5, Number(dc.interval || 5)) * 1000);
  };

  const handleSignOut = async () => {
    await signOutTrakt();
    setProfile(null);
  };

  return (
    <View style={styles.container}>
      <SettingsHeader title="Trakt" onBack={() => nav.goBack()} />
      <ScrollView contentContainerStyle={[styles.content, { paddingTop: headerHeight }]}>
        <SettingsCard title="ACCOUNT">
          {profile ? (
            <View style={styles.statusRow}>
              <Ionicons name="checkmark-circle" size={18} color="#22c55e" />
              <Text style={styles.statusText}>Connected as @{profile?.username || profile?.ids?.slug}</Text>
              <Pressable style={styles.secondaryButton} onPress={handleSignOut}>
                <Text style={styles.secondaryButtonText}>Sign out</Text>
              </Pressable>
            </View>
          ) : (
            <View style={styles.statusRow}>
              <Ionicons name="close-circle" size={18} color="#ef4444" />
              <Text style={styles.statusText}>Not connected</Text>
              <Pressable style={styles.primaryButton} onPress={startAuth}>
                <Text style={styles.primaryButtonText}>Connect Trakt</Text>
              </Pressable>
            </View>
          )}
        </SettingsCard>

        {deviceCode && (
          <SettingsCard title="DEVICE CODE">
            <Text style={styles.codeText}>Visit:</Text>
            <Text style={styles.codeValue}>{deviceCode.verification_url}</Text>
            <Text style={[styles.codeText, { marginTop: 12 }]}>Enter code:</Text>
            <Text style={styles.codeValue}>{deviceCode.user_code}</Text>
          </SettingsCard>
        )}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0b0b0d',
  },
  content: {
    paddingHorizontal: 16,
    paddingBottom: 40,
  },
  statusRow: {
    padding: 14,
    gap: 10,
  },
  statusText: {
    color: '#e5e7eb',
    fontSize: 14,
  },
  primaryButton: {
    backgroundColor: '#fff',
    borderRadius: 10,
    paddingVertical: 10,
    alignItems: 'center',
  },
  primaryButtonText: {
    color: '#0b0b0d',
    fontWeight: '700',
  },
  secondaryButton: {
    backgroundColor: 'rgba(255,255,255,0.08)',
    borderRadius: 10,
    paddingVertical: 10,
    alignItems: 'center',
  },
  secondaryButtonText: {
    color: '#fff',
    fontWeight: '600',
  },
  codeText: {
    color: '#9ca3af',
    fontSize: 12,
  },
  codeValue: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '700',
    marginTop: 4,
  },
});
