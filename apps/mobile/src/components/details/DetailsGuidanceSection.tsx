/**
 * Parents Guide: Age Rating, Common Sense and the IMDb parents guide, all
 * from MyBluray. Tapping an IMDb category opens a bottom panel like a Trakt
 * comment, with previous/next and spoilers hidden until tapped.
 * macOS reference: Views/Details/DetailsGuidanceSection.swift
 *
 * Decisions carried over: no stacked vote bars (people couldn't read them),
 * no IMDb usage notice, no "View on IMDb" (IMDb is linked under About), and a
 * bare rating with no reason isn't worth a card (the hero has its badge).
 */
import React, { useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Text, useWindowDimensions, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import DetailsSectionHeading, { DetailsSectionStyle } from './DetailsSectionHeading';
import { useTheme } from '../../hooks/useTheme';
import type { FlixorTheme } from '../../core/theme';
import type { AppSettings } from '../../core/SettingsData';
import { isMyBlurayOn } from '../../core/mybluray/options';
import type { MBGuidance, MBParentsGuide, MBParentsGuideCategory, MBTitle } from '../../core/mybluray/types';

export interface GuidanceContent {
  certificate?: { rating: string; reason?: string; advisories: string[] };
  commonSense?: MBGuidance;
  imdb?: MBParentsGuide;
}

export function guidanceContent(title: MBTitle | null, guide: MBParentsGuide | null, settings: AppSettings): GuidanceContent {
  const content: GuidanceContent = {};
  if (isMyBlurayOn('ageRatings', settings)) {
    // Apple's certificate carries the reason; IMDb's has one too
    const certificates = title?.certifications ?? [];
    const best = certificates.find((c) => !!c.explanation) ?? certificates[0];
    let candidate: GuidanceContent['certificate'];
    if (best?.value) {
      candidate = { rating: best.value, reason: best.explanation ?? guide?.certification?.reason ?? undefined, advisories: best.advisories ?? [] };
    } else if (guide?.certification?.rating && guide.certification.rating.toLowerCase() !== 'not rated') {
      candidate = { rating: guide.certification.rating, reason: guide.certification.reason ?? undefined, advisories: [] };
    }
    if (candidate && (candidate.reason || candidate.advisories.length)) content.certificate = candidate;
  }
  if (isMyBlurayOn('commonSense', settings)) {
    content.commonSense = title?.parentalGuidance.find((g) => g.recommendedAge != null || g.categories.length > 0);
  }
  if (isMyBlurayOn('imdbGuide', settings) && guide && guide.categories.length) content.imdb = guide;
  return content;
}

export function isGuidanceEmpty(c: GuidanceContent): boolean {
  return !c.certificate && !c.commonSense && !c.imdb;
}

export default function DetailsGuidanceSection({ content, settings }: { content: GuidanceContent; settings: AppSettings }) {
  const theme = useTheme();
  const { width } = useWindowDimensions();
  const [openIndex, setOpenIndex] = useState<number | null>(null);
  const showsDescriptions = isMyBlurayOn('guideDescriptions', settings);
  const cards = [
    content.certificate ? <CertificateCard key="cert" certificate={content.certificate} theme={theme} /> : null,
    content.commonSense ? <CommonSenseCard key="cs" guidance={content.commonSense} theme={theme} /> : null,
  ].filter(Boolean);
  // Three equal cards on a wide screen, rating and Common Sense side by side on a tablet, stacked on a phone
  const wide = width >= 1100;
  const medium = width >= 700;

  const imdbCard = content.imdb ? (
    <IMDbCard guide={content.imdb} showsDescriptions={showsDescriptions} onOpen={setOpenIndex} theme={theme} />
  ) : null;

  return (
    <View>
      <DetailsSectionHeading title="Parents Guide" />
      <View style={[styles.cards, (wide || medium) && styles.cardsRow]}>
        {wide ? (
          <>
            {cards.map((card, i) => <View key={i} style={styles.flexCard}>{card}</View>)}
            {imdbCard ? <View style={styles.flexCard}>{imdbCard}</View> : null}
          </>
        ) : medium ? (
          <View style={{ flex: 1, gap: 12 }}>
            {cards.length ? <View style={styles.cardsRow}>{cards.map((card, i) => <View key={i} style={styles.flexCard}>{card}</View>)}</View> : null}
            {imdbCard}
          </View>
        ) : (
          <>
            {cards}
            {imdbCard}
          </>
        )}
      </View>
      {content.imdb ? (
        <GuideCategoryPanel
          guide={content.imdb}
          index={openIndex}
          revealAll={isMyBlurayOn('revealSpoilers', settings)}
          onIndex={setOpenIndex}
          theme={theme}
        />
      ) : null}
    </View>
  );
}

function GuidanceCard({ title, theme, children }: { title: string; theme: FlixorTheme; children: React.ReactNode }) {
  return (
    <View style={[styles.card, { backgroundColor: theme.surfaceOverlay }]}>
      <Text style={[styles.cardTitle, { color: theme.textTertiary }]}>{title}</Text>
      {children}
    </View>
  );
}

/** "for intense sequences…" reads as a fragment on its own; start it with a capital. */
function sentenceCase(text: string): string {
  return text ? text[0].toUpperCase() + text.slice(1) : text;
}

function CertificateCard({ certificate, theme }: { certificate: NonNullable<GuidanceContent['certificate']>; theme: FlixorTheme }) {
  return (
    <GuidanceCard title="Age Rating" theme={theme}>
      <View style={styles.certRow}>
        <Text style={[styles.certBadge, { color: theme.textPrimary, borderColor: theme.textSecondary }]}>{certificate.rating}</Text>
        <View style={{ flex: 1, gap: 8 }}>
          {certificate.reason ? (
            <Text style={[styles.body, { color: theme.textSecondary }]}>{sentenceCase(certificate.reason)}</Text>
          ) : null}
          {certificate.advisories.length ? (
            <View style={styles.pills}>
              {certificate.advisories.map((a) => (
                <View key={a} style={[styles.advisory, { borderColor: theme.separator, backgroundColor: theme.pressedFill }]}>
                  <Text numberOfLines={1} style={[styles.advisoryText, { color: theme.textSecondary }]}>{a}</Text>
                </View>
              ))}
            </View>
          ) : null}
        </View>
      </View>
    </GuidanceCard>
  );
}

/** Positive categories in green; content concerns in amber. */
function commonSenseColor(name: string): string {
  const n = name.toLowerCase();
  return n.startsWith('positive') || n.includes('educational') ? '#34C759' : '#FF9F0A';
}

function CommonSenseCard({ guidance, theme }: { guidance: MBGuidance; theme: FlixorTheme }) {
  return (
    <GuidanceCard title="Common Sense Media" theme={theme}>
      {guidance.recommendedAge != null || guidance.summary ? (
        <Text style={[styles.body, { color: theme.textSecondary }]}>
          {guidance.recommendedAge != null ? <Text style={[styles.age, { color: theme.textPrimary }]}>Age {guidance.recommendedAge}+  </Text> : null}
          {guidance.summary ?? ''}
        </Text>
      ) : null}
      {guidance.categories.length ? (
        <View style={{ gap: 7, marginTop: 4 }}>
          {guidance.categories.map((c) => {
            const segments = Math.max(1, Math.round(c.scale ?? 5));
            const value = Math.round(c.value ?? 0);
            return (
              <View key={c.name} style={styles.csRow} accessibilityLabel={`${c.name}: ${value} of ${segments}`}>
                <Text numberOfLines={1} style={[styles.csLabel, { color: theme.textSecondary }]}>{c.name}</Text>
                <View style={styles.segments}>
                  {Array.from({ length: segments }).map((_, i) => (
                    <View key={i} style={[styles.segment, { backgroundColor: i < value ? commonSenseColor(c.name) : 'rgba(255,255,255,0.12)' }]} />
                  ))}
                </View>
              </View>
            );
          })}
        </View>
      ) : null}
    </GuidanceCard>
  );
}

const SEVERITY_COLORS: Record<string, string> = { severe: '#FF453A', moderate: '#FF9F0A', mild: '#FFD60A' };

function SeverityPill({ severity, label }: { severity?: string | null; label?: string | null }) {
  const color = SEVERITY_COLORS[severity ?? ''] ?? '#8E8E93';
  const text = label ?? (severity ? severity[0].toUpperCase() + severity.slice(1) : '');
  return (
    <View style={[styles.severity, { backgroundColor: color + '29' }]}>
      <Text numberOfLines={1} style={[styles.severityText, { color }]}>{text}</Text>
    </View>
  );
}

/** How IMDb users voted, in words: "60% of 949 voters" and "None 1% · Mild 12% · …". */
function voteSummary(category: MBParentsGuideCategory) {
  const v = category.votes ?? {};
  const parts: [string, string, number][] = [
    ['none', 'None', v.none ?? 0],
    ['mild', 'Mild', v.mild ?? 0],
    ['moderate', 'Moderate', v.moderate ?? 0],
    ['severe', 'Severe', v.severe ?? 0],
  ];
  const sum = parts.reduce((a, p) => a + p[2], 0);
  const total = category.totalVotes ?? sum;
  const shares = sum === 0 ? [] : parts.map(([key, label, n]) => ({ key, label, percent: Math.round((n * 100) / sum) }));
  const winner = shares.find((s) => s.key === category.severity);
  const fmt = (n: number) => n.toLocaleString('en-US');
  return {
    agreement: total > 0 ? (winner ? `${winner.percent}% of ${fmt(total)} voters` : `${fmt(total)} voters`) : undefined,
    breakdown: shares.length ? `${shares.map((s) => `${s.label} ${s.percent}%`).join(' · ')} · ${fmt(total)} voters` : undefined,
  };
}

function IMDbCard({ guide, showsDescriptions, onOpen, theme }: { guide: MBParentsGuide; showsDescriptions: boolean; onOpen: (i: number) => void; theme: FlixorTheme }) {
  return (
    <GuidanceCard title="IMDb Parents Guide" theme={theme}>
      <View>
        {guide.categories.map((category, index) => {
          const canOpen = showsDescriptions && category.descriptions.length > 0;
          const summary = voteSummary(category);
          return (
            <Pressable
              key={category.category}
              onPress={canOpen ? () => onOpen(index) : undefined}
              disabled={!canOpen}
              accessibilityRole={canOpen ? 'button' : undefined}
              accessibilityHint={canOpen ? 'Shows what happens' : undefined}
              style={({ pressed }) => [
                styles.imdbRow,
                index > 0 && { borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: 'rgba(255,255,255,0.08)' },
                pressed && { opacity: 0.6 },
              ]}
            >
              <View style={{ flex: 1 }}>
                <Text numberOfLines={1} style={[styles.imdbLabel, { color: theme.textPrimary }]}>{category.label ?? category.category}</Text>
                {summary.agreement ? <Text numberOfLines={1} style={[styles.caption, { color: theme.textTertiary }]}>{summary.agreement}</Text> : null}
              </View>
              <SeverityPill severity={category.severity} label={category.severityLabel} />
              {canOpen ? (
                <View style={styles.count}>
                  <Text style={[styles.caption, { color: theme.textTertiary }]}>{category.descriptions.length}</Text>
                  <Ionicons name="chevron-forward" size={14} color={theme.textTertiary} />
                </View>
              ) : (
                <View style={styles.count} />
              )}
            </Pressable>
          );
        })}
      </View>
    </GuidanceCard>
  );
}

function GuideCategoryPanel({
  guide,
  index,
  revealAll,
  onIndex,
  theme,
}: {
  guide: MBParentsGuide;
  index: number | null;
  revealAll: boolean;
  onIndex: (i: number | null) => void;
  theme: FlixorTheme;
}) {
  const insets = useSafeAreaInsets();
  const [revealed, setRevealed] = useState<Set<string>>(new Set());
  if (index == null) return null;
  const category = guide.categories[index];
  if (!category) return null;
  const total = guide.categories.length;
  const breakdown = voteSummary(category).breakdown;
  const close = () => onIndex(null);
  return (
    <Modal visible transparent animationType="slide" statusBarTranslucent onRequestClose={close}>
      <Pressable style={styles.scrim} onPress={close} accessibilityRole="button" accessibilityLabel="Close">
        <Pressable onPress={() => undefined} style={[styles.panel, { backgroundColor: theme.surfaceElevated, paddingBottom: insets.bottom + 20 }]}>
          <View style={[styles.handle, { backgroundColor: theme.separatorStrong }]} />
          <View style={styles.panelHeader}>
            <View style={{ flex: 1, gap: 6 }}>
              <Text style={[styles.panelTitle, { color: theme.textPrimary }]}>{category.label ?? category.category}</Text>
              <View style={{ flexDirection: 'row' }}>
                <SeverityPill severity={category.severity} label={category.severityLabel} />
              </View>
            </View>
            <Pager icon="chevron-back" label="Previous category" enabled={index > 0} onPress={() => onIndex(index - 1)} theme={theme} />
            <Text style={[styles.pagerCount, { color: theme.textSecondary }]}>{index + 1} / {total}</Text>
            <Pager icon="chevron-forward" label="Next category" enabled={index < total - 1} onPress={() => onIndex(index + 1)} theme={theme} />
          </View>
          {breakdown ? <Text style={[styles.caption, { color: theme.textTertiary }]}>{breakdown}</Text> : null}
          <ScrollView style={{ flexGrow: 0 }} key={category.category} contentContainerStyle={{ gap: 12, paddingTop: 4 }}>
            {category.descriptions.map((d, i) => {
              const key = d.id ?? `${category.category}-${i}`;
              const hidden = d.isSpoiler === true && !revealAll && !revealed.has(key);
              return (
                <View key={key} style={styles.bulletRow}>
                  <View style={[styles.bullet, { backgroundColor: theme.textTertiary }]} />
                  {hidden ? (
                    <Pressable
                      style={{ flex: 1 }}
                      onPress={() => setRevealed((s) => new Set(s).add(key))}
                      accessibilityRole="button"
                      accessibilityLabel="Reveal spoiler"
                    >
                      <Text style={[styles.panelText, { color: theme.warning }]}>Spoiler · tap to reveal</Text>
                    </Pressable>
                  ) : (
                    <Text selectable style={[styles.panelText, { color: theme.textPrimary, flex: 1 }]}>{d.text}</Text>
                  )}
                </View>
              );
            })}
          </ScrollView>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

function Pager({ icon, label, enabled, onPress, theme }: { icon: keyof typeof Ionicons.glyphMap; label: string; enabled: boolean; onPress: () => void; theme: FlixorTheme }) {
  return (
    <Pressable
      onPress={onPress}
      disabled={!enabled}
      hitSlop={4}
      accessibilityRole="button"
      accessibilityLabel={label}
      style={[styles.pager, { backgroundColor: theme.pressedFill, opacity: enabled ? 1 : 0.4 }]}
    >
      <Ionicons name={icon} size={18} color={enabled ? theme.textPrimary : theme.textTertiary} />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  cards: { paddingHorizontal: DetailsSectionStyle.inset, gap: 12 },
  cardsRow: { flexDirection: 'row', alignItems: 'stretch', gap: 12 },
  flexCard: { flex: 1 },
  card: { borderRadius: 12, padding: 16, gap: 10, flexGrow: 1 },
  cardTitle: { fontSize: 12, fontWeight: '600', letterSpacing: 0.5, textTransform: 'uppercase' },
  body: { fontSize: 15, lineHeight: 21 },
  age: { fontSize: 18, fontWeight: '700' },
  certRow: { flexDirection: 'row', alignItems: 'flex-start', gap: 12 },
  certBadge: { fontSize: 18, fontWeight: '700', borderWidth: 1.5, borderRadius: 4, paddingHorizontal: 8, paddingVertical: 2, overflow: 'hidden' },
  pills: { flexDirection: 'row', flexWrap: 'wrap', gap: 6 },
  advisory: { height: 26, borderRadius: 13, paddingHorizontal: 10, justifyContent: 'center', borderWidth: StyleSheet.hairlineWidth },
  advisoryText: { fontSize: 12, fontWeight: '500' },
  csRow: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  csLabel: { flex: 1, fontSize: 13 },
  segments: { flexDirection: 'row', gap: 3 },
  segment: { width: 16, height: 5, borderRadius: 1.5 },
  imdbRow: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 10 },
  imdbLabel: { fontSize: 15, fontWeight: '600' },
  caption: { fontSize: 12, marginTop: 2 },
  severity: { width: 84, paddingVertical: 4, borderRadius: 999, alignItems: 'center' },
  severityText: { fontSize: 12, fontWeight: '700' },
  count: { flexDirection: 'row', alignItems: 'center', gap: 2, minWidth: 28, justifyContent: 'flex-end' },
  scrim: { flex: 1, justifyContent: 'flex-end', backgroundColor: 'rgba(0,0,0,0.55)' },
  panel: { maxHeight: '75%', borderTopLeftRadius: 22, borderTopRightRadius: 22, paddingTop: 10, paddingHorizontal: 20, gap: 12 },
  handle: { alignSelf: 'center', width: 40, height: 4, borderRadius: 2 },
  panelHeader: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  panelTitle: { fontSize: 17, fontWeight: '700' },
  pager: { width: 36, height: 36, borderRadius: 18, alignItems: 'center', justifyContent: 'center' },
  pagerCount: { fontSize: 13, fontWeight: '500', fontVariant: ['tabular-nums'] },
  bulletRow: { flexDirection: 'row', alignItems: 'flex-start', gap: 10 },
  bullet: { width: 5, height: 5, borderRadius: 2.5, marginTop: 10 },
  panelText: { fontSize: 16, lineHeight: 24 },
});
