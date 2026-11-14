/**
 * Settings › Integrations › MyBluray: each person's own key, what that key
 * can reach, and what MyBluray adds to the app. Same choices as macOS
 * (MyBluraySettingsView); see MYBLURAY_PARITY.md §4.
 */
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { View, Text, TextInput, Pressable, StyleSheet, Linking, Animated, Modal, ScrollView, ActivityIndicator } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import SettingsSwitch from '../../components/settings/SettingsSwitch';
import { useAppSettings } from '../../hooks/useAppSettings';
import { useTheme } from '../../hooks/useTheme';
import { MYBLURAY_PORTAL_URL, myblurayErrorMessage } from '../../core/mybluray/client';
import { checkKey, clearMyBlurayCache, myblurayCacheSize } from '../../core/mybluray/service';
import { resetCollectionStore } from '../../core/mybluray/collectionStore';
import { DISC_COUNTRIES, countryName, isBlocked, isChosen, localRegion, type MyBlurayOption } from '../../core/mybluray/options';
import type { AccessState, MyBlurayAccess } from '../../core/mybluray/types';

type KeyStatus =
  | { kind: 'none' }
  | { kind: 'checking' }
  | { kind: 'valid'; access: MyBlurayAccess }
  | { kind: 'invalid'; message: string }
  | { kind: 'unreachable'; message: string };

/** Checked once per app session per key, like macOS. */
const sessionChecks = new Map<string, MyBlurayAccess>();

function maskedKey(key: string): string {
  const parts = key.split('_');
  if (parts.length >= 3 && parts[0] === 'mbr') return `mbr_${parts[1]}_••••••••`;
  return key ? `${key.slice(0, 4)}••••••••` : '';
}

type OptionRow = { option: MyBlurayOption; title: string; subtitle?: string };

const OPTION_ICONS: Record<string, string> = {"appleTrailers": "tv-outline", "highQualityTrailers": "sparkles-outline", "bonusVideos": "film-outline", "ratings": "star-outline", "ageRatings": "shield-checkmark-outline", "commonSense": "happy-outline", "imdbGuide": "people-outline", "guideDescriptions": "list-outline", "revealSpoilers": "eye-outline", "editionSpecs": "hardware-chip-outline", "editionScores": "trophy-outline", "editionScreenshots": "images-outline", "editionArtwork": "image-outline", "editionDigitalCopy": "cloud-download-outline", "editionPrice": "pricetag-outline", "editionLinks": "link-outline", "blurayFormat": "disc-outline", "uhdFormat": "diamond-outline", "boxSets": "cube-outline", "quickAdd": "add-circle-outline", "librarySection": "albums-outline"};

// No "Best quality" here (macOS has one): iOS's player picks the stream's quality itself and
// won't open a rewritten playlist, so the app can't cap it. It already adapts to the screen
// and connection, and draws HDR correctly in a normal view (macOS's colour cast doesn't happen).
const TRAILER_OPTIONS: OptionRow[] = [
  { option: 'appleTrailers', title: 'Apple TV trailers first', subtitle: 'YouTube trailers are used when Apple TV has none' },
  { option: 'bonusVideos', title: 'Bonus videos', subtitle: 'Featurettes and clips. Each title takes a larger request.' },
];
const RATING_OPTIONS: OptionRow[] = [
  { option: 'ratings', title: 'Ratings from MyBluray', subtitle: 'IMDb, Rotten Tomatoes, Letterboxd and TMDB on Details. Choose each rating’s source in Settings › Details.' },
];
const GUIDE_OPTIONS: OptionRow[] = [
  { option: 'ageRatings', title: 'Age ratings', subtitle: 'Certificates and the reasons given for them' },
  { option: 'commonSense', title: 'Common Sense Media', subtitle: 'Recommended age, and scores for violence, language and more' },
  { option: 'imdbGuide', title: 'IMDb parents guide', subtitle: 'How strong each category is, voted by IMDb users' },
  { option: 'guideDescriptions', title: 'Written descriptions', subtitle: 'What happens, listed under each category' },
  { option: 'revealSpoilers', title: 'Show spoilers', subtitle: 'Otherwise spoiler descriptions stay hidden until you tap them' },
];
const EDITION_OPTIONS: OptionRow[] = [
  { option: 'editionSpecs', title: 'Specs', subtitle: 'Video, audio, subtitles, discs and packaging' },
  { option: 'editionScores', title: 'Review scores', subtitle: 'Blu-ray.com and community scores for picture, sound and extras' },
  { option: 'editionScreenshots', title: 'Screenshots', subtitle: 'Frames taken from the disc' },
  { option: 'editionArtwork', title: 'Artwork', subtitle: 'Covers, slipcovers and packaging' },
  { option: 'editionDigitalCopy', title: 'Digital copy', subtitle: 'Whether a code is included, and where it redeems' },
  { option: 'editionPrice', title: 'Price', subtitle: 'Current price and a link to buy' },
  { option: 'editionLinks', title: 'Links', subtitle: 'Blu-ray.com and the review' },
];

export default function MyBluraySettings() {
  const headerScrollY = React.useRef(new Animated.Value(0)).current;
  const nav: any = useNavigation();
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const headerHeight = insets.top + 52;
  const { settings, updateSetting, isLoaded } = useAppSettings();

  const savedKey = (settings.myblurayApiKey ?? '').trim();
  const hasKey = savedKey.length > 0;
  const active = hasKey && settings.myblurayEnabled !== false;

  const [draft, setDraft] = useState('');
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [status, setStatus] = useState<KeyStatus>({ kind: 'none' });
  const [countryOpen, setCountryOpen] = useState(false);
  const [cacheSize, setCacheSize] = useState(0);

  const runCheck = useCallback(async (key: string, force = false) => {
    if (!key) { setStatus({ kind: 'none' }); return; }
    if (!force && sessionChecks.has(key)) { setStatus({ kind: 'valid', access: sessionChecks.get(key)! }); return; }
    setStatus({ kind: 'checking' });
    try {
      const access = await checkKey(key);
      sessionChecks.set(key, access);
      setStatus({ kind: 'valid', access });
    } catch (error: any) {
      const text = myblurayErrorMessage(error);
      setStatus(error?.kind === 'invalidKey' ? { kind: 'invalid', message: text } : { kind: 'unreachable', message: text });
    }
  }, []);

  useEffect(() => {
    if (!isLoaded) return;
    runCheck(savedKey);
    setCacheSize(myblurayCacheSize());
  }, [isLoaded, savedKey, runCheck]);

  const saveKey = async () => {
    const key = draft.trim();
    if (!key) { setMessage('Paste a key first.'); return; }
    if (!key.startsWith('mbr_')) { setMessage('MyBluray keys start with mbr_.'); return; }
    setSaving(true);
    setMessage(null);
    try {
      // Checked before saving; a key that can't be checked isn't saved.
      const access = await checkKey(key);
      sessionChecks.set(key, access);
      if (key !== savedKey) {
        clearMyBlurayCache();
        resetCollectionStore();
      }
      await updateSetting('myblurayApiKey', key);
      setStatus({ kind: 'valid', access });
      setDraft('');
      setEditing(false);
      setCacheSize(myblurayCacheSize());
    } catch (error) {
      setMessage(myblurayErrorMessage(error));
    } finally {
      setSaving(false);
    }
  };

  const removeKey = async () => {
    await updateSetting('myblurayApiKey', undefined);
    clearMyBlurayCache();
    resetCollectionStore();
    setStatus({ kind: 'none' });
    setCacheSize(0);
  };

  const setOption = (option: MyBlurayOption, value: boolean) => {
    updateSetting('myblurayOptions', { ...(settings.myblurayOptions ?? {}), [option]: value });
  };

  const optionRows = (rows: OptionRow[], extraDisabled = false) => rows.map((row, index) => {
    const blocked = isBlocked(row.option, settings);
    return (
      <SettingItem
        key={row.option}
        title={row.title}
        description={row.subtitle}
        icon={(OPTION_ICONS[row.option] ?? 'options-outline') as any}
        disabled={blocked || extraDisabled}
        renderRight={() => (
          <SettingsSwitch
            value={isChosen(row.option, settings)}
            onValueChange={(v) => setOption(row.option, v)}
            disabled={blocked || extraDisabled}
          />
        )}
        isLast={index === rows.length - 1}
      />
    );
  });

  const collectionNo = status.kind === 'valid' && status.access.collection === 'no';
  const countryLabel = useMemo(() => {
    const value = settings.myblurayDiscCountry || 'auto';
    if (value === 'auto') return `Automatic (${localRegion()})`;
    if (value === 'all') return 'All countries';
    return countryName(value);
  }, [settings.myblurayDiscCountry]);

  const statusLine = (() => {
    switch (status.kind) {
      case 'none': return { icon: 'remove-circle' as const, color: '#71717a', title: 'Not set up', sub: 'Add your key from the MyBluray portal' };
      case 'checking': return { icon: 'time' as const, color: '#71717a', title: 'Checking your key…', sub: undefined };
      case 'valid': return active
        ? { icon: 'checkmark-circle' as const, color: '#22c55e', title: 'Connected', sub: 'Trailers, ratings, parents guides and disc releases are on' }
        : { icon: 'remove-circle' as const, color: '#71717a', title: 'Off', sub: 'Your key is saved. Turn on MyBluray below.' };
      case 'invalid': return { icon: 'close-circle' as const, color: '#ef4444', title: 'Key not accepted', sub: status.message };
      case 'unreachable': return { icon: 'alert-circle' as const, color: '#f59e0b', title: 'Couldn’t check your key', sub: status.message };
    }
  })();

  return (
    <View style={[styles.container, { backgroundColor: theme.settingsBackground }]}>
      <SettingsHeader scrollY={headerScrollY} title="MyBluray" onBack={() => nav.goBack()} />
      <Animated.ScrollView
        scrollEventThrottle={16}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: headerScrollY } } }], { useNativeDriver: false })}
        contentContainerStyle={[styles.content, { paddingTop: headerHeight + 12, paddingBottom: insets.bottom + 100 }]}
        keyboardShouldPersistTaps="handled"
      >
        <SettingsCard>
          <View style={styles.statusRow}>
            {status.kind === 'checking'
              ? <ActivityIndicator color="#a1a1aa" />
              : <Ionicons name={statusLine.icon} size={24} color={statusLine.color} />}
            <View style={{ flex: 1 }}>
              <Text style={styles.statusTitle}>{statusLine.title}</Text>
              {statusLine.sub ? <Text style={styles.statusSub}>{statusLine.sub}</Text> : null}
            </View>
            {(status.kind === 'unreachable') ? (
              <Pressable style={styles.smallButton} onPress={() => runCheck(savedKey, true)}>
                <Text style={styles.smallButtonText}>Try Again</Text>
              </Pressable>
            ) : null}
          </View>
          <View style={styles.divider} />
          {hasKey && !editing ? (
            <SettingItem
              title="API Key"
              description={maskedKey(savedKey)}
              icon="key-outline"
              renderRight={() => (
                <View style={{ flexDirection: 'row', gap: 8 }}>
                  <Pressable style={styles.smallButton} onPress={() => { setEditing(true); setDraft(''); setMessage(null); }}>
                    <Text style={styles.smallButtonText}>Change</Text>
                  </Pressable>
                  <Pressable style={styles.smallButton} onPress={removeKey}>
                    <Text style={[styles.smallButtonText, { color: '#f87171' }]}>Remove</Text>
                  </Pressable>
                </View>
              )}
            />
          ) : (
            <View style={styles.keyEntry}>
              <Text style={styles.keyLabel}>{hasKey ? 'New API Key' : 'API Key'}</Text>
              <View style={styles.inputRow}>
                <TextInput
                  value={draft}
                  onChangeText={(t) => { setDraft(t); if (message) setMessage(null); }}
                  placeholder="mbr_…"
                  placeholderTextColor="#6b7280"
                  style={styles.input}
                  autoCapitalize="none"
                  autoCorrect={false}
                  secureTextEntry
                  onSubmitEditing={saveKey}
                  returnKeyType="done"
                />
                <Pressable style={[styles.saveButton, (saving || !draft.trim()) && styles.disabled]} onPress={saveKey} disabled={saving || !draft.trim()}>
                  <Text style={styles.saveButtonText}>{saving ? 'Checking…' : 'Save'}</Text>
                </Pressable>
                {hasKey ? (
                  <Pressable style={styles.smallButton} onPress={() => { setEditing(false); setDraft(''); setMessage(null); }} disabled={saving}>
                    <Text style={styles.smallButtonText}>Cancel</Text>
                  </Pressable>
                ) : null}
              </View>
              {message ? (
                <Text style={[styles.note, { color: '#f87171' }]}>{message}</Text>
              ) : (
                <Text style={styles.note} onPress={() => Linking.openURL(MYBLURAY_PORTAL_URL)}>
                  Create a key at <Text style={styles.link}>mybluray.devhomelab.app ↗</Text>
                </Text>
              )}
            </View>
          )}
          <View style={styles.divider} />
          <SettingItem
            title="Use MyBluray"
            icon="power-outline"
            description={hasKey ? 'Turn off to hide everything below without removing your key' : 'Add a key first'}
            disabled={!hasKey}
            renderRight={() => (
              <SettingsSwitch value={hasKey && settings.myblurayEnabled !== false} onValueChange={(v) => updateSetting('myblurayEnabled', v)} disabled={!hasKey} />
            )}
            isLast
          />
        </SettingsCard>
        <Text style={styles.footnote}>Each person uses their own key, saved for their profile.</Text>

        {status.kind === 'valid' ? (
          <>
            <SettingsCard title="WHAT YOUR KEY CAN REACH">
              {([
                ['apple-tv', 'Apple TV', 'Trailers in up to 4K HDR, ratings and age guidance', 'tv'],
                ['imdb', 'IMDb', 'Parents guide', 'people'],
                ['letterboxd', 'Letterboxd', 'Ratings', 'ellipsis-horizontal-circle'],
                ['justwatch', 'JustWatch', 'Ratings, age ratings and clips', 'play-circle'],
                ['bluray', 'Blu-ray.com', 'Disc releases, specs, reviews and screenshots', 'disc'],
                ['collection', 'Your Collection', collectionNo ? 'Attach your Blu-ray.com login to this key in the portal' : 'Your Blu-ray.com collection and wishlist', 'albums'],
              ] as const).map(([id, title, sub, icon], index, all) => (
                <SettingItem
                  key={id}
                  title={title}
                  description={sub}
                  icon={`${icon}-outline` as any}
                  renderRight={() => <AccessBadge state={status.access[id]} />}
                  isLast={index === all.length - 1}
                />
              ))}
            </SettingsCard>
            <View style={styles.inlineRow}>
              <Text style={styles.footnoteInline} onPress={() => Linking.openURL(MYBLURAY_PORTAL_URL)}>
                Change what a key can reach in the <Text style={styles.link}>portal ↗</Text>
              </Text>
              <Pressable style={styles.smallButton} onPress={() => runCheck(savedKey, true)}>
                <Text style={styles.smallButtonText}>Check Again</Text>
              </Pressable>
            </View>
          </>
        ) : null}

        <View style={!active && styles.dimmed} pointerEvents={active ? 'auto' : 'none'}>
          <SettingsCard title="TRAILERS">{optionRows(TRAILER_OPTIONS)}</SettingsCard>
          <SettingsCard title="RATINGS">{optionRows(RATING_OPTIONS)}</SettingsCard>
          <SettingsCard title="PARENTS GUIDE">{optionRows(GUIDE_OPTIONS)}</SettingsCard>
          <SettingsCard title="PHYSICAL RELEASES">
            <SettingItem
              title="Show on Details"
              icon="albums-outline"
              description="Blu-ray and 4K editions of the film you’re viewing"
              renderRight={() => <SettingsSwitch value={isChosen('physicalReleases', settings)} onValueChange={(v) => setOption('physicalReleases', v)} />}
            />
            <SettingItem
              title="Country"
              icon="globe-outline"
              description="Editions released in this market"
              disabled={!isChosen('physicalReleases', settings)}
              onPress={() => setCountryOpen(true)}
              renderRight={() => <Text style={styles.valueText}>{countryLabel}</Text>}
            />
            {optionRows([
              { option: 'blurayFormat', title: 'Blu-ray' },
              { option: 'uhdFormat', title: '4K Ultra HD' },
              { option: 'boxSets', title: 'Box sets', subtitle: 'Editions that bundle several films' },
              { option: 'quickAdd', title: 'Quick add to collection', subtitle: collectionNo ? 'Needs your Blu-ray.com login on the key' : 'A button on each edition to add it to a list' },
            ])}
          </SettingsCard>
          {settings.myblurayDiscCountry === 'all' ? (
            <Text style={styles.footnote}>Popular films can have hundreds of editions worldwide, so the first look takes longer.</Text>
          ) : null}
          <SettingsCard title="EDITION PAGE">{optionRows(EDITION_OPTIONS)}</SettingsCard>
          <SettingsCard title="LIBRARY">
            {optionRows([{ option: 'librarySection', title: 'Physical collection', subtitle: collectionNo ? 'Needs your Blu-ray.com login on the key' : 'Your owned discs and wishlist as a Library tab' }])}
          </SettingsCard>
        </View>

        <SettingsCard title="STORAGE">
          <SettingItem
            title="Saved Results"
            icon="server-outline"
            description={cacheSize ? `${cacheSize} saved · kept so titles you open again load at once` : 'Nothing saved yet'}
            renderRight={() => (
              <Pressable style={[styles.smallButton, !cacheSize && styles.disabled]} disabled={!cacheSize} onPress={() => { clearMyBlurayCache(); setCacheSize(0); }}>
                <Text style={styles.smallButtonText}>Clear</Text>
              </Pressable>
            )}
          />
          <SettingItem
            title="Reset Display Choices"
            icon="refresh-outline"
            description="Turns every option above back to its default. Keeps your key."
            renderRight={() => (
              <Pressable style={styles.smallButton} onPress={async () => { await updateSetting('myblurayOptions', {}); await updateSetting('myblurayDiscCountry', 'auto'); }}>
                <Text style={styles.smallButtonText}>Reset</Text>
              </Pressable>
            )}
            isLast
          />
        </SettingsCard>
      </Animated.ScrollView>

      <Modal visible={countryOpen} transparent animationType="slide" onRequestClose={() => setCountryOpen(false)}>
        <Pressable style={styles.sheetScrim} onPress={() => setCountryOpen(false)} />
        <View style={[styles.sheet, { backgroundColor: theme.surfaceElevated, paddingBottom: insets.bottom + 12 }]}>
          <View style={styles.grabber} />
          <Text style={styles.sheetTitle}>Country</Text>
          <ScrollView style={{ maxHeight: 460 }}>
            {[{ code: 'auto', name: `Automatic (${localRegion()})` }, { code: 'all', name: 'All countries' }, ...DISC_COUNTRIES].map((c) => {
              const selected = (settings.myblurayDiscCountry || 'auto') === c.code;
              return (
                <Pressable key={c.code} style={styles.sheetRow} onPress={() => { updateSetting('myblurayDiscCountry', c.code); setCountryOpen(false); }}>
                  <Text style={[styles.sheetRowText, selected && { fontWeight: '700' }]}>{c.name}</Text>
                  {selected ? <Ionicons name="checkmark" size={18} color="#fff" /> : null}
                </Pressable>
              );
            })}
          </ScrollView>
        </View>
      </Modal>
    </View>
  );
}

function AccessBadge({ state }: { state: AccessState }) {
  const color = state === 'yes' ? '#22c55e' : state === 'no' ? '#a1a1aa' : '#f59e0b';
  const label = state === 'yes' ? 'Included' : state === 'no' ? 'Not on this key' : 'Couldn’t check';
  const icon = state === 'yes' ? 'checkmark' : state === 'no' ? 'remove' : 'help';
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4 }}>
      <Ionicons name={icon} size={12} color={color} />
      <Text style={{ color, fontSize: 12, fontWeight: '600' }}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  content: { paddingHorizontal: 16 },
  statusRow: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 16, paddingVertical: 14 },
  statusTitle: { color: '#fff', fontSize: 15, fontWeight: '700' },
  statusSub: { color: '#a1a1aa', fontSize: 12, marginTop: 2 },
  divider: { height: StyleSheet.hairlineWidth, backgroundColor: 'rgba(255,255,255,0.1)', marginHorizontal: 16 },
  keyEntry: { paddingHorizontal: 16, paddingVertical: 12, gap: 8 },
  keyLabel: { color: '#fff', fontSize: 14 },
  inputRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  input: { flex: 1, height: 38, borderRadius: 10, paddingHorizontal: 12, color: '#fff', backgroundColor: 'rgba(255,255,255,0.06)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.14)', fontSize: 14 },
  saveButton: { height: 38, paddingHorizontal: 14, borderRadius: 19, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center' },
  saveButtonText: { color: '#000', fontWeight: '700', fontSize: 14 },
  smallButton: { paddingHorizontal: 12, height: 30, borderRadius: 15, backgroundColor: 'rgba(255,255,255,0.12)', alignItems: 'center', justifyContent: 'center' },
  smallButtonText: { color: '#fff', fontSize: 13, fontWeight: '600' },
  disabled: { opacity: 0.4 },
  dimmed: { opacity: 0.45 },
  note: { color: '#a1a1aa', fontSize: 12 },
  link: { color: '#60a5fa' },
  footnote: { color: '#8e8e93', fontSize: 12, marginTop: -8, marginBottom: 16, paddingHorizontal: 6 },
  footnoteInline: { color: '#8e8e93', fontSize: 12, flex: 1 },
  inlineRow: { flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: -8, marginBottom: 16, paddingHorizontal: 6 },
  valueText: { color: '#a1a1aa', fontSize: 14 },
  sheetScrim: { flex: 1, backgroundColor: 'rgba(0,0,0,0.5)' },
  sheet: { borderTopLeftRadius: 24, borderTopRightRadius: 24, paddingHorizontal: 16, paddingTop: 8 },
  grabber: { alignSelf: 'center', width: 40, height: 4, borderRadius: 2, backgroundColor: 'rgba(255,255,255,0.25)', marginBottom: 12 },
  sheetTitle: { color: '#fff', fontSize: 17, fontWeight: '700', marginBottom: 8 },
  sheetRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingVertical: 13, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: 'rgba(255,255,255,0.08)' },
  sheetRowText: { color: '#fff', fontSize: 15 },
});
