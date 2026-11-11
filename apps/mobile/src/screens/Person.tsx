/**
 * Person page, pushed on the current tab from Cast & Crew and Search.
 * Identity (avatar, links, facts, biography), Known for, then the Filmography with its
 * filter pills pinned under the navigation bar while scrolling.
 * Header: round Liquid Glass buttons over a glass band that fades in as the page scrolls
 * under it; the pills are Home's glass pills.
 * macOS reference: Views/Person/PersonDetailView.swift, PersonIdentityViews.swift
 */

import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Animated,
  Linking,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  useWindowDimensions,
  View,
} from 'react-native';
import { useFocusEffect, useNavigation, useRoute } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import FastImage from '@d11/react-native-fast-image';
import { LinearGradient } from 'expo-linear-gradient';
import { TopBarStore } from '../components/TopBarStore';
import HeaderGlass, { HEADER_GLASS_MIN_OPACITY } from '../components/HeaderGlass';
import GlassMenu from '../components/GlassMenu';
import { GlassDropdownPill, GlassPill, RoundGlassButton, RoundGlassIcon, glassPillStyles } from '../components/GlassPill';
import { useTheme } from '../hooks/useTheme';
import { useAppSettings } from '../hooks/useAppSettings';
import UserCollectionEditor from './UserCollectionEditor';
import { createUserCollectionId, type UserCollectionSource } from '../core/UserCollectionsStore';
import { findTmdbPersonIdByName } from '../core/DetailsData';
import {
  ageInYears,
  creditSubtitle,
  creditSummary,
  defaultDepartment,
  fetchPersonProfile,
  filterCredits,
  formatPersonDate,
  knownForCredits,
  sortCredits,
  type PersonCreditEntry,
  type PersonCreditOrder,
  type PersonDepartment,
  type PersonMediaFilter,
  type PersonProfile,
} from '../core/PersonData';

type Phase = 'loading' | 'loaded' | 'failed';

const INSET = 16;
const GRID_GAP = 10;
const AVATAR = 120;
const BIO_LINES = 4;
const SORT_LABELS: Record<PersonCreditOrder, string> = { popularity: 'Popular', newest: 'Newest', oldest: 'Oldest' };
const NAV_ROW = 52;
const SORT_ORDER: PersonCreditOrder[] = ['popularity', 'newest', 'oldest'];

function initials(name: string): string {
  const parts = name.trim().split(/\s+/);
  return (parts.length >= 2 ? parts[0][0] + parts[1][0] : name.slice(0, 2)).toUpperCase();
}

export default function Person() {
  const route: any = useRoute();
  const nav: any = useNavigation();
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const { width } = useWindowDimensions();
  const params: { id?: number; name?: string } = route.params ?? {};

  const [phase, setPhase] = useState<Phase>('loading');
  const [profile, setProfile] = useState<PersonProfile | null>(null);
  const [department, setDepartment] = useState<PersonDepartment>('acting');
  const [mediaFilter, setMediaFilter] = useState<PersonMediaFilter>('all');
  const [sort, setSort] = useState<PersonCreditOrder>('popularity');
  const [bioExpanded, setBioExpanded] = useState(false);
  const [bioTruncates, setBioTruncates] = useState(false);
  const [collectionSources, setCollectionSources] = useState<UserCollectionSource[] | null>(null);
  const scrollY = useRef(new Animated.Value(0)).current;
  const loadId = useRef(0);
  // Where the in-page filter bar sits; once it scrolls under the header, a copy joins the header
  const [filterY, setFilterY] = useState<number | null>(null);
  const [filtersPinned, setFiltersPinned] = useState(false);
  const pinnedRef = useRef(false);

  useFocusEffect(
    useCallback(() => {
      TopBarStore.setVisible(false);
    }, [])
  );

  const load = useCallback(async () => {
    const id = ++loadId.current;
    setPhase('loading');
    try {
      // Plex cast can arrive without a TMDB id: look the person up by name, as macOS does
      const personId = params.id ?? (params.name ? await findTmdbPersonIdByName(params.name) : null);
      if (!personId) throw new Error('not found');
      const result = await fetchPersonProfile(Number(personId));
      if (id !== loadId.current) return;
      setProfile(result);
      setDepartment(defaultDepartment(result));
      setPhase('loaded');
    } catch (e) {
      console.log('[Person] load error:', e);
      if (id === loadId.current) setPhase('failed');
    }
  }, [params.id, params.name]);

  useEffect(() => {
    load();
  }, [load]);

  const knownFor = useMemo(() => (profile ? knownForCredits(profile) : null), [profile]);
  const departmentCredits = useMemo(() => {
    if (!profile) return [];
    return sortCredits(department === 'acting' ? profile.cast : profile.crew, sort);
  }, [profile, department, sort]);
  const counts = useMemo(() => {
    const tv = departmentCredits.filter((c) => c.mediaType === 'tv').length;
    return { all: departmentCredits.length, movies: departmentCredits.length - tv, tv };
  }, [departmentCredits]);
  const visibleCredits = useMemo(() => filterCredits(departmentCredits, mediaFilter), [departmentCredits, mediaFilter]);

  const name = profile?.name ?? params.name ?? '';
  const backdrop = knownFor?.credits.find((c) => c.backdropUrl)?.backdropUrl;
  const navBarHeight = insets.top + NAV_ROW;
  const titleOpacity = scrollY.interpolate({ inputRange: [AVATAR + 40, AVATAR + 90], outputRange: [0, 1], extrapolate: 'clamp' });
  // Clear over the backdrop at the top, Liquid Glass once content scrolls under it. Never
  // fully 0: iOS stops drawing Liquid Glass once a parent has been at zero alpha.
  const headerGlassOpacity = useMemo(
    () => scrollY.interpolate({ inputRange: [0, 8, 60], outputRange: [HEADER_GLASS_MIN_OPACITY, HEADER_GLASS_MIN_OPACITY, 1], extrapolate: 'clamp' }),
    [scrollY]
  );
  const hairlineOpacity = useMemo(() => scrollY.interpolate({ inputRange: [0, 120], outputRange: [0, 1], extrapolate: 'clamp' }), [scrollY]);
  const onScroll = Animated.event([{ nativeEvent: { contentOffset: { y: scrollY } } }], {
    useNativeDriver: true,
    listener: (e: any) => {
      const pinned = filterY != null && e.nativeEvent.contentOffset.y >= filterY - navBarHeight;
      if (pinned !== pinnedRef.current) {
        pinnedRef.current = pinned;
        setFiltersPinned(pinned);
      }
    },
  });
  const tileWidth = Math.floor((width - INSET * 2 - GRID_GAP * 2) / 3);

  const openCredit = (credit: PersonCreditEntry) => {
    nav.push('Details', { type: 'tmdb', mediaType: credit.mediaType, id: String(credit.id) });
  };

  const onCreateCollection = () => {
    if (!profile) return;
    setCollectionSources([
      {
        id: createUserCollectionId(),
        kind: 'person',
        personId: profile.id,
        name: profile.name,
        profilePath: profile.profilePath,
        credits: 'knownFor',
        order: 'popularity',
      },
    ]);
  };

  const facts: Array<{ label: string; value: string }> = [];
  if (profile) {
    if (profile.knownForDepartment) facts.push({ label: 'Known for', value: profile.knownForDepartment });
    const summary = creditSummary(profile);
    if (summary) facts.push({ label: 'Credits', value: summary });
    const born = formatPersonDate(profile.birthday);
    if (born) {
      const age = profile.deathday ? undefined : ageInYears(profile.birthday);
      facts.push({ label: 'Born', value: age != null ? `${born} (age ${age})` : born });
    }
    const died = formatPersonDate(profile.deathday);
    if (died) {
      const aged = ageInYears(profile.birthday, profile.deathday);
      facts.push({ label: 'Died', value: aged != null ? `${died} (aged ${aged})` : died });
    }
    if (profile.placeOfBirth) facts.push({ label: 'Place of birth', value: profile.placeOfBirth });
  }

  const links: Array<{ key: string; label: string; icon: keyof typeof Ionicons.glyphMap; url: string }> = [];
  if (profile?.imdbId) links.push({ key: 'imdb', label: 'IMDb', icon: 'film-outline', url: `https://www.imdb.com/name/${profile.imdbId}` });
  if (profile?.instagramId) links.push({ key: 'ig', label: 'Instagram', icon: 'logo-instagram', url: `https://www.instagram.com/${profile.instagramId}` });
  if (profile?.homepage) links.push({ key: 'web', label: 'Website', icon: 'globe-outline', url: profile.homepage });

  const hasBoth = (profile?.cast.length ?? 0) > 0 && (profile?.crew.length ?? 0) > 0;
  const emptyLabel = mediaFilter === 'tv' ? 'No TV credits' : mediaFilter === 'movies' ? 'No movie credits' : 'No credits yet';

  const DEPARTMENT_LABELS: Record<PersonDepartment, string> = { acting: 'Acting', crew: 'Crew' };
  const MEDIA_LABELS: Record<PersonMediaFilter, string> = { all: 'All', movies: 'Movies', tv: 'TV' };
  const departmentCount = (dep: PersonDepartment) => (dep === 'acting' ? profile?.cast.length : profile?.crew.length) ?? 0;

  // Department and type as two dropdown pills on one row, then sort
  const renderFilterBar = () => (
    <View style={styles.filterBar}>
      <View style={[glassPillStyles.row, styles.filterRow]}>
        {hasBoth ? (
          <GlassMenu
            accessibilityLabel={`Credits: ${DEPARTMENT_LABELS[department]}`}
            items={(['acting', 'crew'] as PersonDepartment[]).map((dep) => ({
              title: `${DEPARTMENT_LABELS[dep]}  ${departmentCount(dep)}`,
              checked: dep === department,
              onPress: () => {
                setDepartment(dep);
                setMediaFilter('all');
              },
            }))}
          >
            <GlassDropdownPill label={DEPARTMENT_LABELS[department]} count={departmentCount(department)} />
          </GlassMenu>
        ) : null}
        <GlassMenu
          accessibilityLabel={`Show: ${MEDIA_LABELS[mediaFilter]}`}
          items={(['all', 'movies', 'tv'] as PersonMediaFilter[]).map((filter) => ({
            title: `${MEDIA_LABELS[filter]}  ${counts[filter]}`,
            checked: filter === mediaFilter,
            onPress: () => setMediaFilter(filter),
          }))}
        >
          <GlassDropdownPill label={MEDIA_LABELS[mediaFilter]} count={counts[mediaFilter]} />
        </GlassMenu>
        <View style={{ flex: 1 }} />
        <GlassMenu
          accessibilityLabel={`Sort by ${SORT_LABELS[sort]}`}
          items={SORT_ORDER.map((order) => ({ title: SORT_LABELS[order], checked: order === sort, onPress: () => setSort(order) }))}
        >
          <RoundGlassIcon icon="swap-vertical" />
        </GlassMenu>
      </View>
    </View>
  );

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      {/* Floating header: blurs the page scrolling under it; the filters join it once pinned */}
      <View style={[styles.header, { paddingTop: insets.top }]} pointerEvents="box-none">
        <Animated.View style={[StyleSheet.absoluteFill, { opacity: filtersPinned ? 1 : headerGlassOpacity }]} pointerEvents="none">
          <HeaderGlass fallbackIntensity={80} />
          <Animated.View style={[styles.headerHairline, { opacity: filtersPinned ? 1 : hairlineOpacity }]} />
        </Animated.View>
        <View style={styles.navRow}>
          <RoundGlassButton icon="chevron-back" label="Back" size={36} iconSize={22} onPress={() => nav.goBack()} />
          <Animated.Text numberOfLines={1} style={[styles.navTitle, { opacity: titleOpacity }]}>
            {name}
          </Animated.Text>
          {profile ? (
            <GlassMenu accessibilityLabel="More" items={[{ title: 'Create Collection', icon: 'albums-outline', onPress: onCreateCollection }]}>
              <RoundGlassIcon icon="ellipsis-horizontal" size={36} iconSize={20} />
            </GlassMenu>
          ) : (
            <View style={styles.navButtonSpacer} />
          )}
        </View>
        {filtersPinned && profile ? renderFilterBar() : null}
      </View>

      {phase === 'loading' ? (
        <View style={{ paddingTop: navBarHeight }}>
          <PersonSkeleton />
        </View>
      ) : phase === 'failed' || !profile ? (
        <View style={[styles.centered, { paddingTop: navBarHeight }]}>
          <Text style={styles.errorTitle}>Couldn't load {name || 'this person'}</Text>
          <Text style={styles.errorText}>Check your connection and try again.</Text>
          <Pressable onPress={load} style={styles.secondaryButton} accessibilityRole="button">
            <Text style={styles.secondaryButtonText}>Try Again</Text>
          </Pressable>
        </View>
      ) : (
        <Animated.ScrollView
          scrollEventThrottle={16}
          onScroll={onScroll}
          contentContainerStyle={{ paddingBottom: insets.bottom + 110 }}
        >
          {/* 0: identity, biography, known for and the Filmography heading */}
          <View>
            <View style={[styles.identity, { paddingTop: navBarHeight + 12 }]}>
              {backdrop ? (
                <View style={styles.backdrop} pointerEvents="none">
                  <FastImage source={{ uri: backdrop }} style={StyleSheet.absoluteFill} resizeMode="cover" />
                  {/* Runs under the transparent header and fades out into the page */}
                  <LinearGradient
                    colors={['rgba(0,0,0,0.35)', 'rgba(0,0,0,0.1)', theme.background]}
                    locations={[0, 0.45, 1]}
                    style={StyleSheet.absoluteFill}
                  />
                </View>
              ) : null}
              <View style={styles.avatarRing}>
                <View style={styles.avatar}>
                  {profile.profileUrl ? (
                    <FastImage source={{ uri: profile.profileUrl }} style={StyleSheet.absoluteFill} resizeMode="cover" />
                  ) : (
                    <Text style={styles.avatarInitials}>{initials(profile.name)}</Text>
                  )}
                </View>
              </View>
              <Text style={styles.name} accessibilityRole="header">{profile.name}</Text>
              {links.length ? (
                <View style={styles.links}>
                  {links.map((link) => (
                    <GlassPill
                      key={link.key}
                      label={link.label}
                      icon={link.icon}
                      accessibilityRole="link"
                      onPress={() => Linking.openURL(link.url).catch(() => undefined)}
                    />
                  ))}
                </View>
              ) : null}
            </View>

            {facts.length ? (
              <View style={styles.facts}>
                {facts.map((fact) => (
                  <View key={fact.label} style={styles.fact}>
                    <Text style={styles.factLabel}>{fact.label}</Text>
                    <Text style={styles.factValue}>{fact.value}</Text>
                  </View>
                ))}
              </View>
            ) : null}

            {profile.biography ? (
              <View style={styles.section}>
                <Text style={styles.sectionTitle}>Biography</Text>
                {/* Measures the full text, so "Read more" only shows when it truncates */}
                <Text
                  style={[styles.bio, styles.measure]}
                  onTextLayout={(e) => setBioTruncates(e.nativeEvent.lines.length > BIO_LINES)}
                >
                  {profile.biography}
                </Text>
                <Text style={styles.bio} numberOfLines={bioExpanded ? undefined : BIO_LINES}>
                  {profile.biography}
                </Text>
                {bioTruncates ? (
                  <Pressable onPress={() => setBioExpanded((v) => !v)} style={styles.readMore} hitSlop={8} accessibilityRole="button">
                    <Text style={styles.readMoreText}>{bioExpanded ? 'Show less' : 'Read more'}</Text>
                    <Ionicons name={bioExpanded ? 'chevron-up' : 'chevron-down'} size={14} color="#fff" />
                  </Pressable>
                ) : null}
              </View>
            ) : null}

            {knownFor && knownFor.credits.length ? (
              <View style={styles.section}>
                <Text style={styles.sectionTitle}>Known for</Text>
                <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.knownForRow}>
                  {knownFor.credits.map((credit) => (
                    <CreditTile
                      key={credit.key}
                      credit={credit}
                      subtitle={creditSubtitle(credit, knownFor.department)}
                      width={118}
                      onPress={() => openCredit(credit)}
                    />
                  ))}
                </ScrollView>
              </View>
            ) : null}

            <Text style={[styles.sectionTitle, styles.filmographyTitle]}>Filmography</Text>
          </View>

          {/* In-page filter bar; hidden while its pinned copy shows in the header */}
          <View
            onLayout={(e) => setFilterY(e.nativeEvent.layout.y)}
            style={{ opacity: filtersPinned ? 0 : 1 }}
            pointerEvents={filtersPinned ? 'none' : 'auto'}
          >
            {renderFilterBar()}
          </View>

          {/* 2: grid */}
          <View style={styles.grid}>
            {visibleCredits.length ? (
              visibleCredits.map((credit) => (
                <CreditTile
                  key={credit.key}
                  credit={credit}
                  subtitle={creditSubtitle(credit, department)}
                  width={tileWidth}
                  onPress={() => openCredit(credit)}
                />
              ))
            ) : (
              <Text style={styles.emptyText}>{emptyLabel}</Text>
            )}
          </View>
        </Animated.ScrollView>
      )}

      <UserCollectionEditor
        visible={collectionSources !== null}
        initialName={profile?.name}
        initialSources={collectionSources ?? undefined}
        onClose={() => setCollectionSources(null)}
      />
    </View>
  );
}

function CreditTile({
  credit,
  subtitle,
  width,
  onPress,
}: {
  credit: PersonCreditEntry;
  subtitle?: string;
  width: number;
  onPress: () => void;
}) {
  const { settings } = useAppSettings();
  return (
    <Pressable onPress={onPress} style={{ width }} accessibilityRole="button" accessibilityLabel={subtitle ? `${credit.title}, ${subtitle}` : credit.title}>
      <View style={[styles.poster, { width, height: Math.round(width * 1.5), borderRadius: settings.posterBorderRadius }]}>
        {credit.posterUrl ? (
          <FastImage source={{ uri: credit.posterUrl }} style={StyleSheet.absoluteFill} resizeMode="cover" />
        ) : (
          <Text style={styles.posterFallback} numberOfLines={3}>{credit.title}</Text>
        )}
      </View>
      {/* Follows the "Show titles" setting, like every other poster grid */}
      {settings.showPosterTitles ? (
        <>
          <Text style={styles.tileTitle} numberOfLines={1}>{credit.title}</Text>
          {subtitle ? <Text style={styles.tileSubtitle} numberOfLines={1}>{subtitle}</Text> : null}
        </>
      ) : null}
    </Pressable>
  );
}

function PersonSkeleton() {
  return (
    <View style={styles.skeleton}>
      <View style={[styles.skeletonBlock, { width: AVATAR, height: AVATAR, borderRadius: AVATAR / 2 }]} />
      <View style={[styles.skeletonBlock, { width: 180, height: 24, marginTop: 16 }]} />
      <View style={[styles.skeletonBlock, { width: 140, height: 14, marginTop: 12 }]} />
      <ActivityIndicator color="rgba(255,255,255,0.6)" style={{ marginTop: 32 }} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  header: { position: 'absolute', top: 0, left: 0, right: 0, zIndex: 2 },
  headerHairline: { position: 'absolute', left: 0, right: 0, bottom: 0, height: StyleSheet.hairlineWidth, backgroundColor: 'rgba(255,255,255,0.12)' },
  navRow: { height: NAV_ROW, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 12, gap: 8 },
  navButtonSpacer: { width: 36 },
  navTitle: { flex: 1, color: '#fff', fontSize: 17, fontWeight: '600', textAlign: 'center' },
  centered: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 32, gap: 8 },
  errorTitle: { color: '#fff', fontSize: 18, fontWeight: '600', textAlign: 'center' },
  errorText: { color: 'rgba(255,255,255,0.6)', fontSize: 15, textAlign: 'center', marginBottom: 12 },
  secondaryButton: { height: 44, paddingHorizontal: 20, borderRadius: 12, backgroundColor: 'rgba(255,255,255,0.12)', justifyContent: 'center' },
  secondaryButtonText: { color: '#fff', fontSize: 16, fontWeight: '600' },
  identity: { alignItems: 'center', paddingTop: 12, paddingHorizontal: INSET },
  backdrop: { position: 'absolute', top: 0, left: 0, right: 0, height: 360, opacity: 0.6 },
  avatarRing: {
    width: AVATAR + 8,
    height: AVATAR + 8,
    borderRadius: (AVATAR + 8) / 2,
    backgroundColor: 'rgba(255,255,255,0.12)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  avatar: {
    width: AVATAR,
    height: AVATAR,
    borderRadius: AVATAR / 2,
    overflow: 'hidden',
    backgroundColor: '#1c1c1e',
    alignItems: 'center',
    justifyContent: 'center',
  },
  avatarInitials: { color: 'rgba(255,255,255,0.6)', fontSize: 40, fontWeight: '500' },
  name: { color: '#fff', fontSize: 28, fontWeight: '700', marginTop: 14, textAlign: 'center' },
  links: { flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'center', gap: 8, marginTop: 12 },
  facts: { flexDirection: 'row', flexWrap: 'wrap', paddingHorizontal: INSET, marginTop: 22, rowGap: 14 },
  fact: { width: '50%', paddingRight: 12 },
  factLabel: { color: 'rgba(255,255,255,0.5)', fontSize: 12, fontWeight: '500', marginBottom: 2 },
  factValue: { color: '#fff', fontSize: 15 },
  section: { marginTop: 28 },
  sectionTitle: { color: '#fff', fontSize: 20, fontWeight: '700', paddingHorizontal: INSET, marginBottom: 10 },
  filmographyTitle: { marginTop: 28, marginBottom: 4 },
  bio: { color: 'rgba(255,255,255,0.85)', fontSize: 15, lineHeight: 22, paddingHorizontal: INSET },
  measure: { position: 'absolute', opacity: 0, left: 0, right: 0, top: 30 },
  readMore: { flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: INSET, marginTop: 8, alignSelf: 'flex-start' },
  readMoreText: { color: '#fff', fontSize: 15, fontWeight: '600' },
  knownForRow: { paddingHorizontal: INSET, gap: 12 },
  filterBar: { paddingTop: 2, paddingBottom: 6 },
  filterRow: { flexDirection: 'row', alignItems: 'center' },
  grid: { flexDirection: 'row', flexWrap: 'wrap', paddingHorizontal: INSET, columnGap: GRID_GAP, rowGap: 16, paddingTop: 6 },
  emptyText: { color: 'rgba(255,255,255,0.5)', fontSize: 15, paddingVertical: 40, width: '100%', textAlign: 'center' },
  poster: { overflow: 'hidden', backgroundColor: '#1c1c1e', justifyContent: 'center' },
  posterFallback: { color: 'rgba(255,255,255,0.6)', fontSize: 12, textAlign: 'center', padding: 6 },
  tileTitle: { color: '#fff', fontSize: 13, fontWeight: '600', marginTop: 6 },
  tileSubtitle: { color: 'rgba(255,255,255,0.5)', fontSize: 12, marginTop: 1 },
  skeleton: { alignItems: 'center', paddingTop: 24 },
  skeletonBlock: { backgroundColor: 'rgba(255,255,255,0.08)', borderRadius: 6 },
});
