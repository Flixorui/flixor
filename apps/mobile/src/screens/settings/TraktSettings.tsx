import React, { useEffect, useRef, useState } from 'react';
import { View, Text, ScrollView, Pressable, StyleSheet, Linking, ActivityIndicator } from 'react-native';
import * as Clipboard from 'expo-clipboard';
import * as Haptics from 'expo-haptics';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import TraktIcon from '../../components/icons/TraktIcon';
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
  const [copied, setCopied] = useState(false);
  const [polling, setPolling] = useState(false);
  const pollRef = useRef<any>(null);

  const copyCode = async () => {
    if (!deviceCode?.user_code) return;
    await Clipboard.setStringAsync(deviceCode.user_code);
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

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
    setPolling(true);
    setCopied(false);
    Linking.openURL(dc.verification_url);

    if (pollRef.current) clearInterval(pollRef.current);
    pollRef.current = setInterval(async () => {
      try {
        const res = await pollTraktToken(dc.device_code);
        if (res && res.access_token) {
          await saveTraktTokens(res);
          clearInterval(pollRef.current);
          setDeviceCode(null);
          setPolling(false);
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
      <ScrollView contentContainerStyle={[styles.content, { paddingTop: headerHeight + 12, paddingBottom: insets.bottom + 100 }]}>
        {/* Header with Trakt logo */}
        <View style={styles.logoHeader}>
          <View style={styles.logoContainer}>
            <TraktIcon size={32} color="#ed1c24" />
          </View>
          <Text style={styles.logoTitle}>Trakt</Text>
          <Text style={styles.logoSubtitle}>Track your watch history</Text>
        </View>

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
            <View style={styles.deviceCodeWrap}>
              {/* Polling indicator */}
              <View style={styles.pollingRow}>
                <ActivityIndicator size="small" color="#ed1c24" />
                <Text style={styles.pollingText}>Waiting for authorization...</Text>
              </View>

              {/* Code display */}
              <View style={styles.codeBox}>
                <Text style={styles.codeLabel}>Enter this code on Trakt</Text>
                <Text style={styles.userCode}>{deviceCode.user_code}</Text>
                <Pressable
                  style={[styles.copyButton, copied && styles.copyButtonCopied]}
                  onPress={copyCode}
                >
                  <Ionicons
                    name={copied ? 'checkmark' : 'copy-outline'}
                    size={16}
                    color={copied ? '#22c55e' : '#fff'}
                  />
                  <Text style={[styles.copyButtonText, copied && styles.copyButtonTextCopied]}>
                    {copied ? 'Copied!' : 'Copy Code'}
                  </Text>
                </Pressable>
              </View>

              {/* URL */}
              <View style={styles.urlRow}>
                <Text style={styles.urlLabel}>Visit:</Text>
                <Pressable onPress={() => Linking.openURL(deviceCode.verification_url)}>
                  <Text style={styles.urlValue}>{deviceCode.verification_url}</Text>
                </Pressable>
              </View>
            </View>
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
  logoHeader: {
    alignItems: 'center',
    marginBottom: 20,
    paddingVertical: 16,
  },
  logoContainer: {
    width: 64,
    height: 64,
    borderRadius: 16,
    backgroundColor: 'rgba(237, 28, 36, 0.1)',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 12,
  },
  logoTitle: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '700',
  },
  logoSubtitle: {
    color: '#9ca3af',
    fontSize: 13,
    marginTop: 4,
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
  deviceCodeWrap: {
    padding: 14,
    gap: 16,
  },
  pollingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    backgroundColor: 'rgba(237, 28, 36, 0.1)',
    padding: 12,
    borderRadius: 10,
  },
  pollingText: {
    color: '#ed1c24',
    fontSize: 13,
    fontWeight: '500',
  },
  codeBox: {
    alignItems: 'center',
    backgroundColor: 'rgba(255, 255, 255, 0.06)',
    borderRadius: 12,
    padding: 20,
    borderWidth: 1,
    borderColor: 'rgba(255, 255, 255, 0.1)',
  },
  codeLabel: {
    color: '#9ca3af',
    fontSize: 12,
    marginBottom: 8,
  },
  userCode: {
    color: '#fff',
    fontSize: 32,
    fontWeight: '800',
    letterSpacing: 4,
    marginBottom: 16,
  },
  copyButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 8,
  },
  copyButtonCopied: {
    backgroundColor: 'rgba(34, 197, 94, 0.15)',
  },
  copyButtonText: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '600',
  },
  copyButtonTextCopied: {
    color: '#22c55e',
  },
  urlRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  urlLabel: {
    color: '#9ca3af',
    fontSize: 13,
  },
  urlValue: {
    color: '#3b82f6',
    fontSize: 13,
    fontWeight: '500',
    textDecorationLine: 'underline',
  },
});
