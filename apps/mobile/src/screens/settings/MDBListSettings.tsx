import React, { useMemo, useState } from 'react';
import { View, Text, ScrollView, TextInput, Pressable, StyleSheet, Switch, Linking, Image } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import { useAppSettings } from '../../hooks/useAppSettings';
import { clearMDBListCache, RATING_PROVIDERS } from '../../core/MDBListService';

// Rating source logos
const RATING_LOGOS = {
  imdb: require('../../../assets/ratings/imdb.png'),
  tmdb: require('../../../assets/ratings/tmdb.svg'),
  trakt: require('../../../assets/ratings/trakt.svg'),
  letterboxd: require('../../../assets/ratings/letterboxd.svg'),
  tomatoes: require('../../../assets/ratings/tomato-fresh.png'),
  audience: require('../../../assets/ratings/audienscore.png'),
  metacritic: require('../../../assets/ratings/metacritic.png'),
};

export default function MDBListSettings() {
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const headerHeight = insets.top + 52;
  const { settings, updateSetting } = useAppSettings();
  const [apiKey, setApiKey] = useState(settings.mdblistApiKey || '');
  const hasKey = useMemo(() => apiKey.trim().length > 0, [apiKey]);

  const saveKey = async () => {
    const trimmed = apiKey.trim();
    await updateSetting('mdblistApiKey', trimmed.length ? trimmed : undefined);
    clearMDBListCache();
  };

  const toggleEnabled = async (value: boolean) => {
    await updateSetting('mdblistEnabled', value);
    if (!value) {
      clearMDBListCache();
    }
  };

  const isReady = settings.mdblistEnabled && hasKey;

  return (
    <View style={styles.container}>
      <SettingsHeader title="MDBList" onBack={() => nav.goBack()} />
      <ScrollView contentContainerStyle={[styles.content, { paddingTop: headerHeight }]}>
        {/* Status Card */}
        <View style={[styles.statusCard, isReady ? styles.statusReady : styles.statusNotReady]}>
          <Ionicons
            name={isReady ? 'checkmark-circle' : 'alert-circle'}
            size={24}
            color={isReady ? '#22c55e' : '#f59e0b'}
          />
          <View style={styles.statusTextWrap}>
            <Text style={styles.statusTitle}>
              {!settings.mdblistEnabled
                ? 'MDBList Disabled'
                : !hasKey
                  ? 'API Key Required'
                  : 'MDBList Active'}
            </Text>
            <Text style={styles.statusDesc}>
              {!settings.mdblistEnabled
                ? 'Enable MDBList to fetch ratings from multiple sources.'
                : !hasKey
                  ? 'Enter your MDBList API key to start fetching ratings.'
                  : 'Fetching ratings from IMDb, TMDB, Trakt, RT, and more.'}
            </Text>
          </View>
        </View>

        <SettingsCard title="ENABLE MDBLIST">
          <SettingItem
            title="Enable MDBList Integration"
            description="Fetch ratings from multiple sources"
            icon="analytics-outline"
            renderRight={() => (
              <Switch
                value={settings.mdblistEnabled}
                onValueChange={toggleEnabled}
              />
            )}
            isLast={true}
          />
        </SettingsCard>

        <SettingsCard title="API KEY (REQUIRED)">
          <View style={[styles.inputWrap, !settings.mdblistEnabled && styles.disabled]}>
            <TextInput
              value={apiKey}
              onChangeText={setApiKey}
              placeholder="Enter your MDBList API key"
              placeholderTextColor="#6b7280"
              style={[styles.input, !settings.mdblistEnabled && styles.inputDisabled]}
              autoCapitalize="none"
              autoCorrect={false}
              editable={settings.mdblistEnabled}
            />
            <Pressable
              style={[styles.saveButton, (!settings.mdblistEnabled || !apiKey.trim()) && styles.buttonDisabled]}
              onPress={saveKey}
              disabled={!settings.mdblistEnabled || !apiKey.trim()}
            >
              <Text style={[styles.saveButtonText, (!settings.mdblistEnabled || !apiKey.trim()) && styles.buttonTextDisabled]}>
                Save Key
              </Text>
            </Pressable>
          </View>
          <Text style={styles.note}>
            MDBList requires your own API key. Get one free at mdblist.com.
          </Text>
        </SettingsCard>

        <SettingsCard title="AVAILABLE RATINGS">
          <View style={styles.ratingsGrid}>
            {Object.entries(RATING_PROVIDERS).map(([key, provider]) => {
              const logo = RATING_LOGOS[key as keyof typeof RATING_LOGOS];
              return (
                <View key={key} style={styles.ratingBadge}>
                  <Image source={logo} style={styles.ratingLogo} resizeMode="contain" />
                  <Text style={styles.ratingName}>{provider.name}</Text>
                </View>
              );
            })}
          </View>
        </SettingsCard>

        <SettingsCard title="GET YOUR API KEY">
          <View style={styles.stepsWrap}>
            <View style={styles.step}>
              <Text style={styles.stepNumber}>1.</Text>
              <Text style={styles.stepText}>
                Create an account at <Text style={styles.highlight}>mdblist.com</Text>
              </Text>
            </View>
            <View style={styles.step}>
              <Text style={styles.stepNumber}>2.</Text>
              <Text style={styles.stepText}>
                Go to <Text style={styles.highlight}>Settings</Text> {'>'} <Text style={styles.highlight}>API</Text>
              </Text>
            </View>
            <View style={styles.step}>
              <Text style={styles.stepNumber}>3.</Text>
              <Text style={styles.stepText}>Copy your API key and paste above</Text>
            </View>
            <Pressable
              style={styles.linkButton}
              onPress={() => Linking.openURL('https://mdblist.com/preferences/')}
            >
              <Text style={styles.linkButtonText}>Go to MDBList</Text>
              <Ionicons name="open-outline" size={16} color="#3b82f6" />
            </Pressable>
          </View>
        </SettingsCard>
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
  statusCard: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 14,
    borderRadius: 12,
    marginBottom: 16,
    gap: 12,
    borderWidth: 1,
  },
  statusReady: {
    backgroundColor: 'rgba(34, 197, 94, 0.1)',
    borderColor: 'rgba(34, 197, 94, 0.2)',
  },
  statusNotReady: {
    backgroundColor: 'rgba(245, 158, 11, 0.1)',
    borderColor: 'rgba(245, 158, 11, 0.2)',
  },
  statusTextWrap: {
    flex: 1,
  },
  statusTitle: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  statusDesc: {
    color: '#9ca3af',
    fontSize: 13,
    marginTop: 2,
  },
  inputWrap: {
    padding: 14,
    gap: 10,
  },
  input: {
    backgroundColor: 'rgba(255,255,255,0.06)',
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 10,
    color: '#fff',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
  },
  inputDisabled: {
    backgroundColor: 'rgba(255,255,255,0.02)',
    color: '#6b7280',
  },
  saveButton: {
    backgroundColor: '#fff',
    borderRadius: 10,
    paddingVertical: 10,
    alignItems: 'center',
  },
  saveButtonText: {
    color: '#0b0b0d',
    fontWeight: '700',
  },
  buttonDisabled: {
    backgroundColor: 'rgba(255,255,255,0.1)',
  },
  buttonTextDisabled: {
    color: '#6b7280',
  },
  note: {
    color: '#9ca3af',
    fontSize: 12,
    paddingHorizontal: 14,
    paddingBottom: 12,
  },
  disabled: {
    opacity: 0.5,
  },
  ratingsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    padding: 14,
  },
  ratingBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 12,
    paddingVertical: 8,
    backgroundColor: 'rgba(255,255,255,0.04)',
    borderRadius: 8,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
  },
  ratingLogo: {
    width: 20,
    height: 20,
  },
  ratingName: {
    color: '#e5e7eb',
    fontSize: 12,
    fontWeight: '500',
  },
  stepsWrap: {
    padding: 14,
    gap: 10,
  },
  step: {
    flexDirection: 'row',
    gap: 8,
  },
  stepNumber: {
    color: '#6b7280',
    fontSize: 14,
    width: 20,
  },
  stepText: {
    flex: 1,
    color: '#e5e7eb',
    fontSize: 14,
    lineHeight: 20,
  },
  highlight: {
    color: '#fff',
    fontWeight: '600',
  },
  linkButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    marginTop: 8,
    paddingVertical: 10,
    paddingHorizontal: 14,
    backgroundColor: 'rgba(59, 130, 246, 0.1)',
    borderRadius: 10,
    alignSelf: 'flex-start',
  },
  linkButtonText: {
    color: '#3b82f6',
    fontWeight: '600',
  },
});
