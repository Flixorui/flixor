/**
 * Full page for one Blu-ray or 4K edition, opened from Physical Releases on
 * Details and from Library → Physical. Laid out like the Person page: a faded
 * screenshot behind the cover, title and facts, then the content blocks
 * chosen in Settings → MyBluray → Edition Page.
 * macOS reference: Views/Details/EditionDetailView.swift
 */
import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Animated, Linking, Pressable, ScrollView, StyleSheet, Text, useWindowDimensions, View } from 'react-native';
import { useNavigation, useRoute } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import FastImage from '@d11/react-native-fast-image';
import { LinearGradient } from 'expo-linear-gradient';
import HeaderGlass, { HEADER_GLASS_MIN_OPACITY } from '../components/HeaderGlass';
import GlassMenu from '../components/GlassMenu';
import { GlassPill, RoundGlassButton } from '../components/GlassPill';
import ImageViewer, { type ImageViewerItem } from '../components/ImageViewer';
import { EDITION_ASPECT, collectionMenuItems } from '../components/details/EditionCoverCard';
import { useTheme } from '../hooks/useTheme';
import { useAppSettings } from '../hooks/useAppSettings';
import { useEdition } from '../core/mybluray/hooks';
import { isMyBlurayOn } from '../core/mybluray/options';
import { isUHD, loadCollection, useCollectionStore } from '../core/mybluray/collectionStore';
import { baseTitle, editionName, releaseDateText } from '../core/mybluray/editionText';
import { matchPlexMovie } from '../core/mybluray/plexMatch';
import { myblurayErrorMessage } from '../core/mybluray/client';
import type { MBEdition, MBEditionSummary, MBScoreSet } from '../core/mybluray/types';

const INSET = 16;
const NAV_ROW = 52;
const COVER = 170;
const SYNOPSIS_LINES = 4;

export default function Edition() {
  const nav: any = useNavigation();
  const route: any = useRoute();
  const params: { id: string; summary?: MBEditionSummary; offersLibraryLink?: boolean } = route.params ?? {};
  const insets = useSafeAreaInsets();
  const theme = useTheme();
  const { width } = useWindowDimensions();
  const { settings } = useAppSettings();
  const collection = useCollectionStore();
  const { edition, loading, error } = useEdition(params.id);
  const [retry, setRetry] = useState(0);
  const [plexMatch, setPlexMatch] = useState<{ ratingKey: string; title: string } | null>(null);
  const [viewer, setViewer] = useState<{ items: ImageViewerItem[]; index: number } | null>(null);
  const [synopsisOpen, setSynopsisOpen] = useState(false);
  const [synopsisTruncates, setSynopsisTruncates] = useState(false);
  const scrollY = useRef(new Animated.Value(0)).current;

  // The summary from the list draws the page at once; the full edition fills it in
  const summary: MBEditionSummary = params.summary ?? (edition as MBEditionSummary) ?? { id: params.id };
  const on = (option: Parameters<typeof isMyBlurayOn>[0]) => isMyBlurayOn(option, settings);

  useEffect(() => {
    if (on('quickAdd') || on('librarySection')) loadCollection();
  }, []);

  useEffect(() => {
    if (!params.offersLibraryLink) return;
    let cancelled = false;
    matchPlexMovie(summary.title, summary.year ?? edition?.year).then((m) => !cancelled && setPlexMatch(m));
    return () => {
      cancelled = true;
    };
  }, [params.offersLibraryLink, summary.title, edition?.year]);

  const navBarHeight = insets.top + NAV_ROW;
  const headerGlassOpacity = useMemo(
    () => scrollY.interpolate({ inputRange: [0, 8, 60], outputRange: [HEADER_GLASS_MIN_OPACITY, HEADER_GLASS_MIN_OPACITY, 1], extrapolate: 'clamp' }),
    [scrollY]
  );
  const titleOpacity = scrollY.interpolate({ inputRange: [COVER * EDITION_ASPECT, COVER * EDITION_ASPECT + 60], outputRange: [0, 1], extrapolate: 'clamp' });

  const title = baseTitle(summary) || edition?.title || '';
  const name = edition?.editionTitle || editionName(summary);
  const backdrop = edition?.screenshots[0]?.url ?? summary.coverImage ?? undefined;
  const current = collection.listFor[summary.id];
  const canEdit = on('quickAdd') && collection.phase === 'loaded' && collection.lists.length > 0;

  const facts: { label: string; value: string }[] = [];
  const add = (label: string, value?: string | null) => {
    if (value) facts.push({ label, value });
  };
  add('Released', releaseDateText(summary.releaseDate ?? edition?.releaseDate));
  add('Country', (edition?.country ?? summary.country)?.name);
  add('Studio', edition?.metadata?.studio);
  const runtime = edition?.metadata?.runtime;
  if (runtime && runtime > 0) add('Runtime', runtime >= 60 ? `${Math.floor(runtime / 60)}h ${runtime % 60}m` : `${runtime} min`);
  add('Discs', edition?.discs?.join(' · '));
  add('Region', edition?.region?.join(' · '));
  add('Packaging', edition?.packaging?.join(' · '));
  add('Exclusive', edition?.exclusive);

  const openCover = () => {
    if (summary.coverImage) setViewer({ items: [{ url: summary.coverImage, caption: summary.title ?? undefined }], index: 0 });
  };

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      <View style={[styles.header, { paddingTop: insets.top }]} pointerEvents="box-none">
        <Animated.View style={[StyleSheet.absoluteFill, { opacity: headerGlassOpacity }]} pointerEvents="none">
          <HeaderGlass fallbackIntensity={80} />
        </Animated.View>
        <View style={styles.navRow}>
          <RoundGlassButton icon="chevron-back" label="Back" size={36} iconSize={22} onPress={() => nav.goBack()} />
          <Animated.Text numberOfLines={1} style={[styles.navTitle, { opacity: titleOpacity }]}>{title}</Animated.Text>
          <View style={{ width: 36 }} />
        </View>
      </View>

      <Animated.ScrollView
        scrollEventThrottle={16}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: scrollY } } }], { useNativeDriver: true })}
        contentContainerStyle={{ paddingBottom: insets.bottom + 110 }}
      >
        <View style={[styles.identity, { paddingTop: navBarHeight + 12 }]}>
          {backdrop ? (
            <View style={styles.backdrop} pointerEvents="none">
              <FastImage source={{ uri: backdrop }} style={StyleSheet.absoluteFill} resizeMode="cover" />
              <LinearGradient colors={['rgba(0,0,0,0.35)', 'rgba(0,0,0,0.15)', theme.background]} locations={[0, 0.45, 1]} style={StyleSheet.absoluteFill} />
            </View>
          ) : null}
          <Pressable onPress={openCover} accessibilityRole="imagebutton" accessibilityLabel="Show the cover larger">
            <View style={[styles.cover, { width: COVER, height: Math.round(COVER * EDITION_ASPECT) }]}>
              {summary.coverImage ? (
                <FastImage source={{ uri: summary.coverImage }} style={StyleSheet.absoluteFill} resizeMode="cover" />
              ) : (
                <Ionicons name="disc-outline" size={40} color="rgba(255,255,255,0.3)" />
              )}
            </View>
          </Pressable>
          <Text style={styles.formatLabel}>{isUHD(summary) ? '4K ULTRA HD' : 'BLU-RAY'}</Text>
          <Text style={styles.title} accessibilityRole="header" selectable>{title}</Text>
          <Text style={styles.editionName}>{name}</Text>

          {canEdit || plexMatch ? (
            <View style={styles.actions}>
              {canEdit ? (
                <GlassMenu
                  accessibilityLabel={current ? `In ${current.name}. Change` : 'Add to Collection'}
                  items={collectionMenuItems(summary, current?.id, collection.lists)}
                >
                  <View style={[styles.collectionButton, current ? styles.collectionButtonIn : styles.collectionButtonAdd]}>
                    <Ionicons name={current ? 'checkmark' : 'add'} size={16} color={current ? '#fff' : '#000'} />
                    <Text style={[styles.collectionText, { color: current ? '#fff' : '#000' }]}>{current?.name ?? 'Add to Collection'}</Text>
                    <Ionicons name="chevron-down" size={12} color={current ? 'rgba(255,255,255,0.6)' : 'rgba(0,0,0,0.6)'} />
                  </View>
                </GlassMenu>
              ) : null}
              {plexMatch ? (
                <GlassPill
                  label="Open in Library"
                  icon="play"
                  onPress={() => nav.push('Details', { type: 'plex', ratingKey: plexMatch.ratingKey })}
                />
              ) : null}
            </View>
          ) : null}
          {collection.message ? <Text style={styles.message}>{collection.message}</Text> : null}

          {on('editionLinks') && edition && (edition.websiteUrl || edition.reviewScores?.critic?.sourceUrl) ? (
            <View style={styles.links}>
              {edition.websiteUrl ? (
                <GlassPill label="Blu-ray.com" icon="disc-outline" accessibilityRole="link" onPress={() => Linking.openURL(edition.websiteUrl!).catch(() => undefined)} />
              ) : null}
              {edition.reviewScores?.critic?.sourceUrl ? (
                <GlassPill label="Review" icon="chatbox-ellipses-outline" accessibilityRole="link" onPress={() => Linking.openURL(edition.reviewScores!.critic!.sourceUrl!).catch(() => undefined)} />
              ) : null}
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

        {edition ? (
          <EditionContent
            edition={edition}
            width={width}
            on={on}
            synopsisOpen={synopsisOpen}
            synopsisTruncates={synopsisTruncates}
            onSynopsisLayout={setSynopsisTruncates}
            onToggleSynopsis={() => setSynopsisOpen((v) => !v)}
            onShowImages={(items, index) => setViewer({ items, index })}
          />
        ) : error && !loading ? (
          <View style={styles.centered}>
            <Text style={styles.errorTitle}>Couldn't load this edition</Text>
            <Text style={styles.errorText}>{myblurayErrorMessage(error)}</Text>
            <Pressable onPress={() => { setRetry(retry + 1); nav.replace('Edition', params); }} style={styles.secondaryButton} accessibilityRole="button">
              <Text style={styles.secondaryButtonText}>Try Again</Text>
            </Pressable>
          </View>
        ) : (
          <View style={styles.skeleton}>
            <View style={[styles.skeletonBlock, { width: 180, height: 22 }]} />
            {Array.from({ length: 6 }).map((_, i) => (
              <View key={i} style={[styles.skeletonBlock, { height: 14, width: i === 5 ? 220 : '100%' }]} />
            ))}
          </View>
        )}
      </Animated.ScrollView>

      <ImageViewer items={viewer?.items ?? []} index={viewer ? viewer.index : null} onClose={() => setViewer(null)} />
    </View>
  );
}

function artworkLabel(type?: string | null): string {
  switch (type) {
    case 'front-cover': return 'Front';
    case 'back-cover': return 'Back';
    case 'slipcover-front': return 'Slipcover';
    case 'slipcover-back': return 'Slipcover back';
    case 'packaging-overview': return 'Packaging';
    default: return (type ?? '').replace(/-/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
  }
}

/** "Batman Begins 4K English, FrenchThe Dark Knight 4K English" → one line per film and list. */
export function splitSubtitles(text: string, titles: string[]): string[] {
  if (text.includes('\n')) return text.split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
  if (!titles.length) return [text];
  const lines: string[] = [];
  let rest = text;
  while (rest.length) {
    let next: { at: number; title: string } | null = null;
    for (const t of titles) {
      const at = rest.indexOf(t);
      if (at >= 0 && (!next || at < next.at)) next = { at, title: t };
    }
    if (!next) {
      lines.push(rest.trim());
      break;
    }
    const before = rest.slice(0, next.at).trim();
    if (before) lines.push(before);
    lines.push(next.title);
    rest = rest.slice(next.at + next.title.length);
  }
  return lines.filter(Boolean);
}

const SCORE_KEYS: [string, string][] = [
  ['overall', 'Overall'], ['movie', 'Movie'], ['video4k', '4K video'], ['video2k', '1080p video'],
  ['video', 'Video'], ['audio', 'Audio'], ['extras', 'Extras'],
];

function EditionContent({
  edition,
  width,
  on,
  synopsisOpen,
  synopsisTruncates,
  onSynopsisLayout,
  onToggleSynopsis,
  onShowImages,
}: {
  edition: MBEdition;
  width: number;
  on: (o: any) => boolean;
  synopsisOpen: boolean;
  synopsisTruncates: boolean;
  onSynopsisLayout: (t: boolean) => void;
  onToggleSynopsis: () => void;
  onShowImages: (items: ImageViewerItem[], index: number) => void;
}) {
  const synopsis = edition.metadata?.synopsis;
  const showSynopsis = !!synopsis && !synopsis.toLowerCase().startsWith('see individual titles');
  const scoreCards = ([
    ['Critic review', edition.reviewScores?.critic],
    ['Community reviews', edition.reviewScores?.communityReviews],
    ['Community ratings', edition.reviewScores?.communityRatings],
  ] as [string, MBScoreSet | null | undefined][]).filter(([, set]) => set && set.scores && Object.keys(set.scores).length);
  const videoFacts: { label: string; value: string }[] = [];
  const addVideo = (label: string, value?: string | null) => value && videoFacts.push({ label, value });
  addVideo('Video', edition.video?.codec);
  addVideo('Resolution', edition.video?.resolution);
  addVideo('HDR', edition.video?.hdr);
  addVideo('Aspect ratio', [edition.video?.aspectRatio, edition.video?.originalAspectRatio ? `original ${edition.video.originalAspectRatio}` : null].filter(Boolean).join(' · '));
  // Film names in a box set's audio list (entries with no "Language: format")
  const discTitles = (edition.audio ?? []).filter((a) => !a.includes(':'));
  const seenArt = new Set<string>();
  const artwork = edition.artwork.filter((a) => {
    const key = a.type ?? a.url;
    if (seenArt.has(key)) return false;
    seenArt.add(key);
    return true;
  });
  const shotWidth = Math.floor((width - INSET * 2 - 10) / 2);
  const copy = edition.digitalCopy;
  const offer = edition.metadata?.amazon;
  const showCopy = on('editionDigitalCopy') && copy?.included === true;
  const showPrice = on('editionPrice') && !!offer?.price;

  const group = (label: string, lines: string[]) => (
    <View style={{ gap: 4 }}>
      <Text style={styles.factLabel}>{label}</Text>
      {lines.map((line, i) =>
        discTitles.includes(line) ? (
          <Text key={i} style={[styles.groupTitle, i > 0 && { marginTop: 6 }]}>{line}</Text>
        ) : (
          <Text key={i} selectable style={styles.groupLine}>{line}</Text>
        )
      )}
    </View>
  );

  return (
    <View>
      {showSynopsis ? (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>About</Text>
          <Text style={[styles.bio, styles.measure]} onTextLayout={(e) => onSynopsisLayout(e.nativeEvent.lines.length > SYNOPSIS_LINES)}>{synopsis}</Text>
          <Text style={styles.bio} numberOfLines={synopsisOpen ? undefined : SYNOPSIS_LINES}>{synopsis}</Text>
          {synopsisTruncates ? (
            <Pressable onPress={onToggleSynopsis} style={styles.readMore} hitSlop={8} accessibilityRole="button">
              <Text style={styles.readMoreText}>{synopsisOpen ? 'Show less' : 'Read more'}</Text>
              <Ionicons name={synopsisOpen ? 'chevron-up' : 'chevron-down'} size={14} color="#fff" />
            </Pressable>
          ) : null}
        </View>
      ) : null}

      {on('editionScores') && scoreCards.length ? (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Review Scores</Text>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: INSET, gap: 12 }}>
            {scoreCards.map(([label, set]) => (
              <View key={label} style={styles.scoreCard}>
                <Text style={styles.factLabel}>{label.toUpperCase()}</Text>
                <Text style={styles.scoreByline}>
                  {set!.author ? `by ${set!.author}` : set!.voteCount ? (set!.voteCount === 1 ? '1 vote' : `${set!.voteCount} votes`) : ' '}
                </Text>
                {SCORE_KEYS.filter(([k]) => set!.scores?.[k] != null).map(([k, l]) => {
                  const v = set!.scores![k];
                  return (
                    <View key={k} style={styles.scoreRow}>
                      <Text style={styles.scoreLabel}>{l}</Text>
                      <Ionicons name="star" size={10} color="#F5C518" />
                      <Text style={styles.scoreValue}>{Number.isInteger(v) ? v : v.toFixed(1)}</Text>
                      <Text style={styles.scoreScale}>/ {set!.scale ?? 5}</Text>
                    </View>
                  );
                })}
              </View>
            ))}
          </ScrollView>
        </View>
      ) : null}

      {on('editionSpecs') && (videoFacts.length || edition.audio?.length || edition.subtitles) ? (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Video & Audio</Text>
          <View style={{ paddingHorizontal: INSET, gap: 18 }}>
            {videoFacts.length ? (
              <View style={[styles.facts, { paddingHorizontal: 0, marginTop: 0 }]}>
                {videoFacts.map((f) => (
                  <View key={f.label} style={styles.fact}>
                    <Text style={styles.factLabel}>{f.label}</Text>
                    <Text style={styles.factValue}>{f.value}</Text>
                  </View>
                ))}
              </View>
            ) : null}
            {edition.audio?.length ? group('Audio', edition.audio) : null}
            {edition.subtitles ? group('Subtitles', splitSubtitles(edition.subtitles, discTitles)) : null}
          </View>
        </View>
      ) : null}

      {on('editionScreenshots') && edition.screenshots.length ? (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Screenshots</Text>
          <View style={styles.shotGrid}>
            {edition.screenshots.map((shot, i) => (
              <Pressable
                key={`${shot.url}-${i}`}
                onPress={() => onShowImages(edition.screenshots.map((s) => ({ url: s.url, thumbnail: s.thumbnailUrl ?? undefined })), i)}
                accessibilityRole="imagebutton"
                accessibilityLabel={`Screenshot ${i + 1}`}
              >
                <FastImage source={{ uri: shot.thumbnailUrl ?? shot.url }} style={[styles.shot, { width: shotWidth, height: Math.round((shotWidth * 9) / 16) }]} resizeMode="cover" />
              </Pressable>
            ))}
          </View>
          {edition.screenshots[0]?.provenance?.note ? <Text style={styles.note}>{edition.screenshots[0].provenance.note}</Text> : null}
        </View>
      ) : null}

      {on('editionArtwork') && artwork.length ? (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Artwork</Text>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: INSET, gap: 14 }}>
            {artwork.map((art, i) => (
              <Pressable
                key={`${art.url}-${i}`}
                onPress={() => onShowImages(artwork.map((a) => ({ url: a.url, caption: artworkLabel(a.type) })), i)}
                accessibilityRole="imagebutton"
                accessibilityLabel={artworkLabel(art.type)}
              >
                <FastImage source={{ uri: art.url }} style={styles.art} resizeMode="contain" />
                <Text style={[styles.factLabel, { marginTop: 6 }]}>{artworkLabel(art.type).toUpperCase()}</Text>
              </Pressable>
            ))}
          </ScrollView>
        </View>
      ) : null}

      {showCopy || showPrice ? (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Digital Copy & Price</Text>
          <View style={{ paddingHorizontal: INSET, gap: 18 }}>
            {showCopy ? (
              <View style={{ gap: 8 }}>
                <Text style={styles.factLabel}>{copy?.resolution ? `DIGITAL COPY · ${copy.resolution.toUpperCase()}` : 'DIGITAL COPY'}</Text>
                <View style={styles.chips}>
                  {copy!.platforms.length ? (
                    copy!.platforms.map((p, i) => (
                      <View key={i} style={styles.chip}>
                        <Text style={styles.chipText}>{p.label ?? p.value}</Text>
                      </View>
                    ))
                  ) : (
                    <Text style={styles.groupLine}>Included</Text>
                  )}
                </View>
              </View>
            ) : null}
            {showPrice ? (
              <View style={{ gap: 8 }}>
                <Text style={styles.factLabel}>{offer?.availability ? `PRICE · ${offer.availability.toUpperCase()}` : 'PRICE'}</Text>
                <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
                  <Text style={styles.price}>{`${offer?.currency ?? ''}${offer?.price}`}</Text>
                  {offer?.listPrice && offer.listPrice !== offer.price ? (
                    <Text style={styles.listPrice}>{`${offer.currency ?? ''}${offer.listPrice}`}</Text>
                  ) : null}
                  {offer?.purchaseUrl ? (
                    <GlassPill label="Amazon" icon="cart-outline" accessibilityRole="link" onPress={() => Linking.openURL(offer.purchaseUrl!).catch(() => undefined)} />
                  ) : null}
                </View>
              </View>
            ) : null}
          </View>
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  header: { position: 'absolute', top: 0, left: 0, right: 0, zIndex: 2 },
  navRow: { height: NAV_ROW, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 12, gap: 8 },
  navTitle: { flex: 1, color: '#fff', fontSize: 17, fontWeight: '600', textAlign: 'center' },
  identity: { alignItems: 'center', paddingHorizontal: INSET },
  backdrop: { position: 'absolute', top: 0, left: 0, right: 0, height: 420, opacity: 0.55 },
  cover: {
    borderRadius: 8,
    overflow: 'hidden',
    backgroundColor: '#1c1c1e',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.25)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  formatLabel: { color: 'rgba(255,255,255,0.55)', fontSize: 12, fontWeight: '600', letterSpacing: 0.6, marginTop: 16 },
  title: { color: '#fff', fontSize: 26, fontWeight: '700', marginTop: 4, textAlign: 'center' },
  editionName: { color: 'rgba(255,255,255,0.7)', fontSize: 16, fontWeight: '500', marginTop: 4, textAlign: 'center' },
  actions: { flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'center', alignItems: 'center', gap: 8, marginTop: 16 },
  collectionButton: { flexDirection: 'row', alignItems: 'center', gap: 6, height: 36, paddingHorizontal: 14, borderRadius: 18 },
  collectionButtonAdd: { backgroundColor: '#fff' },
  collectionButtonIn: { backgroundColor: 'rgba(255,255,255,0.14)', borderWidth: StyleSheet.hairlineWidth, borderColor: 'rgba(255,255,255,0.2)' },
  collectionText: { fontSize: 15, fontWeight: '600' },
  message: { color: 'rgba(255,255,255,0.55)', fontSize: 12, marginTop: 8 },
  links: { flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'center', gap: 8, marginTop: 12 },
  facts: { flexDirection: 'row', flexWrap: 'wrap', paddingHorizontal: INSET, marginTop: 22, rowGap: 14 },
  fact: { width: '50%', paddingRight: 12 },
  factLabel: { color: 'rgba(255,255,255,0.5)', fontSize: 12, fontWeight: '500', marginBottom: 2 },
  factValue: { color: '#fff', fontSize: 15 },
  section: { marginTop: 28 },
  sectionTitle: { color: '#fff', fontSize: 20, fontWeight: '700', paddingHorizontal: INSET, marginBottom: 12 },
  bio: { color: 'rgba(255,255,255,0.85)', fontSize: 15, lineHeight: 22, paddingHorizontal: INSET },
  measure: { position: 'absolute', opacity: 0, left: 0, right: 0, top: 30 },
  readMore: { flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: INSET, marginTop: 8, alignSelf: 'flex-start' },
  readMoreText: { color: '#fff', fontSize: 15, fontWeight: '600' },
  scoreCard: { width: 230, padding: 14, borderRadius: 12, backgroundColor: 'rgba(255,255,255,0.06)', borderWidth: StyleSheet.hairlineWidth, borderColor: 'rgba(255,255,255,0.1)', gap: 8 },
  scoreByline: { color: 'rgba(255,255,255,0.45)', fontSize: 12, marginTop: -6 },
  scoreRow: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  scoreLabel: { flex: 1, color: 'rgba(255,255,255,0.75)', fontSize: 14 },
  scoreValue: { color: '#fff', fontSize: 14, fontWeight: '600' },
  scoreScale: { color: 'rgba(255,255,255,0.45)', fontSize: 12 },
  groupTitle: { color: '#fff', fontSize: 14, fontWeight: '600' },
  groupLine: { color: 'rgba(255,255,255,0.75)', fontSize: 15, lineHeight: 21 },
  shotGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 10, paddingHorizontal: INSET },
  shot: { borderRadius: 8, backgroundColor: '#1c1c1e', borderWidth: StyleSheet.hairlineWidth, borderColor: 'rgba(255,255,255,0.1)' },
  note: { color: 'rgba(255,255,255,0.45)', fontSize: 12, paddingHorizontal: INSET, marginTop: 8 },
  art: { height: 180, width: 142, borderRadius: 6 },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  chip: { paddingHorizontal: 12, paddingVertical: 6, borderRadius: 999, backgroundColor: 'rgba(255,255,255,0.1)', borderWidth: StyleSheet.hairlineWidth, borderColor: 'rgba(255,255,255,0.15)' },
  chipText: { color: 'rgba(255,255,255,0.8)', fontSize: 13, fontWeight: '600' },
  price: { color: '#fff', fontSize: 22, fontWeight: '700' },
  listPrice: { color: 'rgba(255,255,255,0.45)', fontSize: 15, textDecorationLine: 'line-through' },
  centered: { alignItems: 'center', padding: 32, gap: 8 },
  errorTitle: { color: '#fff', fontSize: 18, fontWeight: '600', textAlign: 'center' },
  errorText: { color: 'rgba(255,255,255,0.6)', fontSize: 15, textAlign: 'center', marginBottom: 12 },
  secondaryButton: { height: 44, paddingHorizontal: 20, borderRadius: 12, backgroundColor: 'rgba(255,255,255,0.12)', justifyContent: 'center' },
  secondaryButtonText: { color: '#fff', fontSize: 16, fontWeight: '600' },
  skeleton: { paddingHorizontal: INSET, marginTop: 28, gap: 12 },
  skeletonBlock: { backgroundColor: 'rgba(255,255,255,0.08)', borderRadius: 6 },
});
