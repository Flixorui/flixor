import React from 'react';
import { ActivityIndicator, ImageBackground, Pressable, ScrollView, StyleSheet, Text, View, Animated } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import SettingsHeader from '../components/settings/SettingsHeader';
import StremioProviderChips from '../components/stremio/StremioProviderChips';
import StremioStreamCard from '../components/stremio/StremioStreamCard';
import { useStremioSources, type StremioSourcesRouteParams } from '../hooks/useStremioSources';
import {
  rankedPlayable,
  RELEASE_CATEGORY_LABEL,
  RELEASE_CATEGORY_ORDER,
  releaseCategory,
  resolutionGroup,
  type ReleaseCategory,
  type ResolutionGroup,
} from '../stremio/StremioSourceRanking';
import type { StremioPlayableStream } from '../stremio/types';

/** Rows per category before "Show all". */
const ROWS_PER_CATEGORY = 3;
const RESOLUTION_LABEL: Record<ResolutionGroup, string> = { '4K': '4K', '1080p': '1080p', Lower: '720p & lower' };

type Entry = { stream: StremioPlayableStream; category: ReleaseCategory; resolution: ResolutionGroup };

function entriesFor(streams: StremioPlayableStream[]): Entry[] {
  return streams.map((stream) => {
    const category = releaseCategory(stream);
    return { stream, category, resolution: resolutionGroup(stream, category) };
  });
}

type RouteParams = {
  route?: {
    params?: StremioSourcesRouteParams;
  };
};

export default function StremioSources({ route }: RouteParams) {
  const headerScrollY = React.useRef(new Animated.Value(0)).current;
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
    hiddenStreams,
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

  const [resolutionFilter, setResolutionFilter] = React.useState<'all' | ResolutionGroup>('all');
  // Categories shown as a header only (Pre-release starts that way), and ones showing every row.
  const [collapsed, setCollapsed] = React.useState<Set<ReleaseCategory>>(() => new Set(['preRelease']));
  const [expanded, setExpanded] = React.useState<Set<ReleaseCategory>>(() => new Set());
  const [showHidden, setShowHidden] = React.useState(false);

  // Playable sources best first, grouped by release type; unsupported ones listed after.
  const allEntries = React.useMemo(() => entriesFor(rankedPlayable(visibleResults)), [visibleResults]);
  const unsupported = React.useMemo(
    () => visibleResults.flatMap((result) => result.streams.filter((stream) => !stream.playable)),
    [visibleResults]
  );
  const hiddenEntries = React.useMemo(() => entriesFor(hiddenStreams), [hiddenStreams]);
  const filtered = resolutionFilter === 'all' ? allEntries : allEntries.filter((e) => e.resolution === resolutionFilter);
  const resolutionChips = React.useMemo(() => {
    const chips = [{ id: 'all', label: `All  ${allEntries.length}` }];
    for (const group of ['4K', '1080p', 'Lower'] as ResolutionGroup[]) {
      const count = allEntries.filter((e) => e.resolution === group).length;
      if (count > 0) chips.push({ id: group, label: `${RESOLUTION_LABEL[group]}  ${count}` });
    }
    return chips;
  }, [allEntries]);

  const toggle = (set: Set<ReleaseCategory>, category: ReleaseCategory) => {
    const next = new Set(set);
    if (next.has(category)) next.delete(category);
    else next.add(category);
    return next;
  };

  const renderCard = (stream: StremioPlayableStream, key: string) => {
    const isCachedMatch =
      cachedSource?.addonId === stream.addonId && cachedSource?.streamLabel === (stream.name || stream.title);
    return (
      <StremioStreamCard
        key={key}
        stream={stream}
        onPress={() => navigateToPlayer(stream)}
        disabled={!stream.playable}
        isCached={isCachedMatch}
        resumePositionLabel={isCachedMatch ? resumePositionLabel : undefined}
      />
    );
  };
  const streamKey = (stream: StremioPlayableStream, i: number) =>
    `${stream.addonInstallationId || stream.addonId}-${stream.streamIndex}-${stream.url || i}`;

  return (
    <View style={styles.container}>
      {params?.backdrop ? (
        <ImageBackground source={{ uri: params.backdrop }} style={styles.backdrop} resizeMode="cover">
          <LinearGradient
            colors={['rgba(8,8,10,0.1)', 'rgba(8,8,10,0.75)', '#08080a']}
            style={StyleSheet.absoluteFill}
          />
        </ImageBackground>
      ) : null}

      <SettingsHeader scrollY={headerScrollY} title="Stremio Sources" onBack={() => nav.goBack()} />

      <Animated.ScrollView
        scrollEventThrottle={16}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: headerScrollY } } }], { useNativeDriver: false })}
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

        {!loading && !autoSelecting && (allEntries.length > 0 || hiddenStreams.length > 0) ? (
          <>
            {resolutionChips.length > 2 ? (
              <StremioProviderChips
                providers={resolutionChips}
                selectedProvider={resolutionFilter}
                onSelect={(id) => setResolutionFilter(id as 'all' | ResolutionGroup)}
              />
            ) : null}

            {hiddenStreams.length > 0 ? (
              <View style={styles.hiddenNote}>
                <Text style={styles.hiddenText}>
                  {hiddenStreams.length} hidden · for a different title or year
                </Text>
                <Pressable onPress={() => setShowHidden((v) => !v)} accessibilityRole="button" style={styles.hiddenButton}>
                  <Text style={styles.hiddenButtonText}>{showHidden ? 'Hide' : 'Show'}</Text>
                </Pressable>
              </View>
            ) : null}
            {showHidden && hiddenEntries.length > 0 ? (
              <View style={[styles.section, { opacity: 0.55 }]}>
                <Text style={styles.sectionTitle}>Different title or year</Text>
                <View style={styles.cards}>{hiddenEntries.map((e, i) => renderCard(e.stream, `hidden-${streamKey(e.stream, i)}`))}</View>
              </View>
            ) : null}

            {filtered.length === 0 ? (
              <View style={styles.stateCard}>
                <Text style={styles.stateText}>
                  {allEntries.length === 0 ? 'No source is for this title.' : 'No sources at this quality.'}
                </Text>
              </View>
            ) : null}

            {RELEASE_CATEGORY_ORDER.map((category) => {
              const rows = filtered.filter((e) => e.category === category);
              if (rows.length === 0) return null;
              const all = allEntries.filter((e) => e.category === category);
              const breakdown = (['4K', '1080p', 'Lower'] as ResolutionGroup[])
                .map((group) => [group, all.filter((e) => e.resolution === group).length] as const)
                .filter(([, n]) => n > 0)
                .map(([group, n]) => `${RESOLUTION_LABEL[group]} ${n}`)
                .join(' · ');
              const isCollapsed = collapsed.has(category);
              const shown = expanded.has(category) ? rows : rows.slice(0, ROWS_PER_CATEGORY);
              return (
                <View key={category} style={styles.section}>
                  <View style={styles.categoryHeader}>
                    <View style={{ flex: 1 }}>
                      <Text style={styles.sectionTitle}>
                        {RELEASE_CATEGORY_LABEL[category]} <Text style={styles.count}>{rows.length}</Text>
                      </Text>
                      <Text style={styles.breakdown}>{breakdown}</Text>
                    </View>
                    <Pressable onPress={() => setCollapsed((set) => toggle(set, category))} accessibilityRole="button" hitSlop={8}>
                      <Text style={styles.toggle}>{isCollapsed ? 'Expand' : 'Collapse'}</Text>
                    </Pressable>
                  </View>
                  {category === 'preRelease' ? (
                    <Text style={styles.warning}>⚠︎ Recorded in a cinema or from a screener. Picture and sound are poor.</Text>
                  ) : null}
                  {!isCollapsed ? (
                    <View style={styles.cards}>
                      {shown.map((e, i) => renderCard(e.stream, streamKey(e.stream, i)))}
                      {shown.length < rows.length ? (
                        <Pressable
                          onPress={() => setExpanded((set) => toggle(set, category))}
                          accessibilityRole="button"
                          style={styles.showAll}
                        >
                          <Text style={styles.showAllText}>Show all {rows.length}</Text>
                        </Pressable>
                      ) : null}
                    </View>
                  ) : null}
                </View>
              );
            })}
          </>
        ) : null}

        {unsupported.length > 0 ? (
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Not playable in-app</Text>
            <View style={styles.cards}>{unsupported.map((stream, i) => renderCard(stream, `unsupported-${streamKey(stream, i)}`))}</View>
          </View>
        ) : null}

        {visibleResults.filter((result) => result.error && result.streams.length === 0).map((result) => (
          <Text key={result.installationId} style={[styles.sectionError, { marginHorizontal: 16, marginTop: 16 }]}>
            {result.addonName}: {result.error}
          </Text>
        ))}
      </Animated.ScrollView>
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
    ...StyleSheet.absoluteFill,
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
  categoryHeader: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: 12,
  },
  count: {
    color: '#9ca3af',
    fontSize: 15,
    fontWeight: '600',
  },
  breakdown: {
    color: '#6b7280',
    fontSize: 12,
    marginTop: 2,
  },
  toggle: {
    color: '#9ca3af',
    fontSize: 13,
    fontWeight: '700',
  },
  warning: {
    color: '#fbbf24',
    fontSize: 12,
    lineHeight: 17,
  },
  showAll: {
    paddingVertical: 10,
    alignItems: 'center',
    borderRadius: 12,
    backgroundColor: 'rgba(255,255,255,0.06)',
  },
  showAllText: {
    color: '#d1d5db',
    fontSize: 13,
    fontWeight: '700',
  },
  hiddenNote: {
    marginTop: 16,
    marginHorizontal: 16,
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: 12,
    backgroundColor: 'rgba(255,255,255,0.05)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  hiddenText: {
    flex: 1,
    color: '#e5e7eb',
    fontSize: 14,
  },
  hiddenButton: {
    paddingHorizontal: 12,
    paddingVertical: 5,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.2)',
  },
  hiddenButtonText: {
    color: '#ffffff',
    fontSize: 12,
    fontWeight: '700',
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
