import React from 'react';
import { ActivityIndicator, ImageBackground, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import SettingsHeader from '../components/settings/SettingsHeader';
import StremioProviderChips from '../components/stremio/StremioProviderChips';
import StremioStreamCard from '../components/stremio/StremioStreamCard';
import { useStremioSources, type StremioSourcesRouteParams } from '../hooks/useStremioSources';

type RouteParams = {
  route?: {
    params?: StremioSourcesRouteParams;
  };
};

export default function StremioSources({ route }: RouteParams) {
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const headerHeight = insets.top + 52;
  const params = route?.params;
  const {
    loading,
    autoSelecting,
    autoSelectNotice,
    chooseSourceInstead,
    visibleResults,
    providers,
    selectedProvider,
    setSelectedProvider,
    cachedSource,
    resumePositionLabel,
    navigateToPlayer,
    openCachedSource,
    state,
  } = useStremioSources(params as StremioSourcesRouteParams);

  const title = params?.episodeTitle || params?.title || 'Stremio Sources';

  return (
    <View style={styles.container}>
      {params?.backdrop ? (
        <ImageBackground source={{ uri: params.backdrop }} style={styles.backdrop} resizeMode="cover">
          <LinearGradient
            colors={['rgba(8,8,10,0.1)', 'rgba(8,8,10,0.75)', '#08080a']}
            style={StyleSheet.absoluteFillObject}
          />
        </ImageBackground>
      ) : null}

      <SettingsHeader title="Stremio Sources" onBack={() => nav.goBack()} />

      <ScrollView
        contentContainerStyle={[
          styles.content,
          { paddingTop: headerHeight + 24, paddingBottom: insets.bottom + 80 },
        ]}
      >
        <View style={styles.hero}>
          <Text style={styles.eyebrow}>Alternate Playback</Text>
          <Text style={styles.title}>{title}</Text>
          <Text style={styles.subtitle}>
            Browse addon sources, pick a direct stream, or resume the cached Stremio source for this title.
          </Text>
        </View>

        {autoSelectNotice ? (
          <View style={styles.stateCard}>
            <Text style={styles.stateText}>{autoSelectNotice}</Text>
          </View>
        ) : null}

        {cachedSource && !autoSelecting ? (
          <View style={styles.resumeSection}>
            <Text style={styles.sectionTitle}>Resume Cached Source</Text>
            <StremioStreamCard
              stream={{
                url: cachedSource.uri,
                name: cachedSource.streamLabel || cachedSource.title,
                addonId: cachedSource.addonId,
                addonName: cachedSource.addonName,
                streamIndex: 0,
                sourceType: 'url',
                playable: true,
                subtitles: cachedSource.externalSubtitles,
              }}
              onPress={() => openCachedSource()}
              isCached
              resumePositionLabel={resumePositionLabel}
            />
          </View>
        ) : null}

        <StremioProviderChips
          providers={providers}
          selectedProvider={selectedProvider}
          onSelect={setSelectedProvider}
        />

        {autoSelecting ? (
          <View style={styles.loadingState}>
            <ActivityIndicator color="#ffffff" />
            <Text style={styles.stateText}>Finding a source…</Text>
            <Pressable onPress={chooseSourceInstead} accessibilityRole="button" style={styles.chooseButton}>
              <Text style={styles.chooseButtonText}>Choose a Source Instead</Text>
            </Pressable>
          </View>
        ) : loading ? (
          <View style={styles.loadingState}>
            <ActivityIndicator color="#ffffff" />
            <Text style={styles.stateText}>Loading addon sources…</Text>
          </View>
        ) : !state.hasAddons ? (
          <View style={styles.stateCard}>
            <Text style={styles.stateTitle}>No stream-capable addons installed</Text>
            <Text style={styles.stateText}>
              Enable Stremio playback and install at least one addon that exposes a stream resource for this title.
            </Text>
          </View>
        ) : !state.hasAnyResults ? (
          <View style={styles.stateCard}>
            <Text style={styles.stateTitle}>No streams returned</Text>
            <Text style={styles.stateText}>
              Your installed addons responded, but none returned sources for this title.
            </Text>
          </View>
        ) : state.hasUnsupportedOnly ? (
          <View style={styles.stateCard}>
            <Text style={styles.stateTitle}>Only unsupported sources were returned</Text>
            <Text style={styles.stateText}>
              This release only supports direct HTTP(S) streams for in-app playback.
            </Text>
          </View>
        ) : null}

        {visibleResults.map((result) => (
          <View key={result.installationId} style={styles.section}>
            <View style={styles.sectionHeader}>
              <Text style={styles.sectionTitle}>{result.addonName}</Text>
              {result.error ? <Text style={styles.sectionError}>{result.error}</Text> : null}
            </View>
            <View style={styles.cards}>
              {result.streams.map((stream) => {
                const isCachedMatch =
                  cachedSource?.addonId === stream.addonId &&
                  cachedSource?.streamLabel === (stream.name || stream.title);
                return (
                  <StremioStreamCard
                    key={`${result.installationId}-${stream.streamIndex}-${stream.name || stream.title || 'stream'}`}
                    stream={stream}
                    onPress={() => navigateToPlayer(stream)}
                    disabled={!stream.playable}
                    isCached={isCachedMatch}
                    resumePositionLabel={isCachedMatch ? resumePositionLabel : undefined}
                  />
                );
              })}
            </View>
          </View>
        ))}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  chooseButton: {
    marginTop: 4,
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 10,
    backgroundColor: 'rgba(255,255,255,0.12)',
  },
  chooseButtonText: {
    color: '#ffffff',
    fontSize: 14,
    fontWeight: '700',
  },
  container: {
    flex: 1,
    backgroundColor: '#08080a',
  },
  backdrop: {
    ...StyleSheet.absoluteFillObject,
  },
  content: {
    gap: 0,
  },
  hero: {
    paddingHorizontal: 16,
    gap: 8,
  },
  eyebrow: {
    color: '#f59e0b',
    fontSize: 12,
    fontWeight: '800',
    letterSpacing: 1.2,
    textTransform: 'uppercase',
  },
  title: {
    color: '#f9fafb',
    fontSize: 30,
    fontWeight: '900',
  },
  subtitle: {
    color: '#d1d5db',
    fontSize: 15,
    lineHeight: 22,
    maxWidth: 640,
  },
  resumeSection: {
    marginTop: 24,
    paddingHorizontal: 16,
    gap: 12,
  },
  section: {
    marginTop: 24,
    paddingHorizontal: 16,
    gap: 12,
  },
  sectionHeader: {
    gap: 4,
  },
  sectionTitle: {
    color: '#ffffff',
    fontSize: 18,
    fontWeight: '800',
  },
  sectionError: {
    color: '#fca5a5',
    fontSize: 12,
    fontWeight: '600',
  },
  cards: {
    gap: 12,
  },
  loadingState: {
    paddingVertical: 32,
    alignItems: 'center',
    gap: 10,
  },
  stateCard: {
    marginTop: 24,
    marginHorizontal: 16,
    padding: 18,
    borderRadius: 18,
    backgroundColor: 'rgba(17,24,39,0.85)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    gap: 8,
  },
  stateTitle: {
    color: '#f9fafb',
    fontSize: 17,
    fontWeight: '800',
  },
  stateText: {
    color: '#d1d5db',
    fontSize: 14,
    lineHeight: 20,
  },
});
