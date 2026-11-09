import React, { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Dimensions,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { stremioService } from '../../stremio/StremioService';

const { width } = Dimensions.get('window');

type Props = {
  title: string;
  subtitle: string;
  description: string;
};

/** Onboarding step for Stremio-only mode. macOS reference: AddonSetupSlideView. */
export default function AddonSetupSlide({ title, subtitle, description }: Props) {
  const [url, setUrl] = useState('');
  const [installing, setInstalling] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hasAddons, setHasAddons] = useState(false);

  const refreshStatus = useCallback(async () => {
    try {
      setHasAddons(await stremioService.hasStreamProviders());
    } catch {
      setHasAddons(false);
    }
  }, []);

  useEffect(() => {
    refreshStatus();
  }, [refreshStatus]);

  const install = async () => {
    const trimmed = url.trim();
    if (!trimmed || installing) return;
    setInstalling(true);
    setError(null);
    try {
      await stremioService.installAddon(trimmed);
      setUrl('');
      await refreshStatus();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'This addon could not be installed.');
    } finally {
      setInstalling(false);
    }
  };

  return (
    <KeyboardAvoidingView
      style={styles.slide}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled" showsVerticalScrollIndicator={false}>
        <Text style={styles.title}>{title}</Text>
        <Text style={styles.subtitle}>{subtitle}</Text>
        <Text style={styles.description}>{description}</Text>

        <TextInput
          value={url}
          onChangeText={setUrl}
          onSubmitEditing={install}
          placeholder="https://example.com/manifest.json"
          placeholderTextColor="rgba(255,255,255,0.35)"
          autoCapitalize="none"
          autoCorrect={false}
          keyboardType="url"
          returnKeyType="done"
          editable={!installing}
          style={styles.input}
          accessibilityLabel="Addon manifest URL"
        />

        <Pressable
          onPress={install}
          disabled={!url.trim() || installing}
          style={[styles.button, (!url.trim() || installing) && styles.buttonDisabled]}
          accessibilityRole="button"
        >
          {installing ? (
            <ActivityIndicator color="#0A0A0A" />
          ) : (
            <Text style={styles.buttonText}>{hasAddons ? 'Install Another' : 'Install Addon'}</Text>
          )}
        </Pressable>

        {error ? <Text style={styles.error}>{error}</Text> : null}

        <View style={styles.statusRow}>
          <Ionicons
            name={hasAddons ? 'checkmark-circle' : 'alert-circle-outline'}
            size={16}
            color={hasAddons ? '#22c55e' : '#f59e0b'}
          />
          <Text style={styles.statusText}>{hasAddons ? 'Stream addon installed' : 'No stream addons yet'}</Text>
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  slide: { width, flex: 1 },
  content: { paddingHorizontal: 32, paddingTop: 24, paddingBottom: 160 },
  title: { color: '#FFFFFF', fontSize: 44, fontWeight: '800', lineHeight: 48 },
  subtitle: { color: 'rgba(255,255,255,0.6)', fontSize: 17, fontWeight: '600', marginTop: 12 },
  description: { color: 'rgba(255,255,255,0.45)', fontSize: 15, lineHeight: 22, marginTop: 12 },
  input: {
    marginTop: 28,
    backgroundColor: 'rgba(255,255,255,0.08)',
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 14,
    color: '#FFFFFF',
    fontSize: 15,
  },
  button: {
    marginTop: 12,
    backgroundColor: '#FFFFFF',
    borderRadius: 12,
    minHeight: 48,
    alignItems: 'center',
    justifyContent: 'center',
  },
  buttonDisabled: { opacity: 0.4 },
  buttonText: { color: '#0A0A0A', fontSize: 15, fontWeight: '700' },
  error: { color: '#ef4444', fontSize: 13, lineHeight: 18, marginTop: 10 },
  statusRow: { flexDirection: 'row', alignItems: 'center', gap: 6, marginTop: 14 },
  statusText: { color: 'rgba(255,255,255,0.7)', fontSize: 13 },
});
