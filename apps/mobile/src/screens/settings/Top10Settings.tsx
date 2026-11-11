/**
 * Top 10 Lists settings: an overview page with each source's status, the row choices and
 * usage, and drill-in pages for FlixPatrol, Streaming Availability, the services, the
 * region and usage / saved lists. Red is only for switches; buttons are neutral and
 * removal is red text. Keys are pasted by the user, shown masked, and stored in the Keychain.
 * macOS reference: Views/Settings/StreamingAvailabilitySettingsView.swift
 */

import React, { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, TextInput, View, Animated } from 'react-native';
import { useNavigation, useRoute } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingsSwitch from '../../components/settings/SettingsSwitch';
import GlassMenu from '../../components/GlassMenu';
import { useAppSettings } from '../../hooks/useAppSettings';
import { useTheme } from '../../hooks/useTheme';
import * as Store from '../../core/top10/Top10Store';
import * as Budget from '../../core/top10/Top10Budget';
import { REGIONS, SERVICE_NAMES, hasStreamingAvailability, quotaRemaining, type StreamingServiceId } from '../../core/top10/Top10Models';

// ---------------------------------------------------------------- shared pieces

function Page({ title, children }: { title: string; children: React.ReactNode }) {
  const headerScrollY = React.useRef(new Animated.Value(0)).current;
  const nav: any = useNavigation();
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  return (
    <View style={[styles.container, { backgroundColor: theme.settingsBackground }]}>
      <SettingsHeader scrollY={headerScrollY} title={title} onBack={() => nav.goBack()} />
      <Animated.ScrollView
        scrollEventThrottle={16}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: headerScrollY } } }], { useNativeDriver: false })}
        keyboardShouldPersistTaps="handled"
        contentContainerStyle={[styles.content, { paddingTop: insets.top + 64, paddingBottom: insets.bottom + 100 }]}
      >
        {children}
      </Animated.ScrollView>
    </View>
  );
}

function Group({ title, footer, children }: { title?: string; footer?: string; children: React.ReactNode }) {
  return (
    <View>
      <SettingsCard title={title?.toUpperCase()}>{children}</SettingsCard>
      {footer ? <Text style={styles.footer}>{footer}</Text> : null}
    </View>
  );
}

function Row({
  title, subtitle, right, onPress, chevron, first,
}: {
  title: React.ReactNode; subtitle?: React.ReactNode; right?: React.ReactNode; onPress?: () => void; chevron?: boolean; first?: boolean;
}) {
  return (
    <Pressable onPress={onPress} disabled={!onPress} style={({ pressed }) => [styles.row, !first && styles.rowBorder, pressed && onPress && styles.pressed]}>
      <View style={styles.rowText}>
        {typeof title === 'string' ? <Text style={styles.rowTitle}>{title}</Text> : title}
        {subtitle ? (typeof subtitle === 'string' ? <Text style={styles.rowSub}>{subtitle}</Text> : subtitle) : null}
      </View>
      {right}
      {chevron ? <Ionicons name="chevron-forward" size={18} color="#6b7280" style={{ marginLeft: 6 }} /> : null}
    </Pressable>
  );
}

function Button({ label, onPress, kind = 'neutral', busy }: { label: string; onPress: () => void; kind?: 'neutral' | 'primary' | 'danger'; busy?: boolean }) {
  return (
    <Pressable
      onPress={onPress}
      disabled={busy}
      accessibilityRole="button"
      style={({ pressed }) => [styles.btn, kind === 'primary' && styles.btnPrimary, kind === 'danger' && styles.btnDanger, (pressed || busy) && { opacity: 0.6 }]}
    >
      {busy ? (
        <ActivityIndicator size="small" color={kind === 'primary' ? '#000' : '#fff'} />
      ) : (
        <Text style={[styles.btnText, kind === 'primary' && { color: '#000' }, kind === 'danger' && { color: '#ff453a' }]}>{label}</Text>
      )}
    </Pressable>
  );
}

function StatusTitle({ ok, text }: { ok: boolean | null; text: string }) {
  return (
    <View style={styles.statusLine}>
      <View style={[styles.dot, ok === true && styles.dotOk, ok === false && styles.dotErr]} />
      <Text style={styles.rowTitle}>{text}</Text>
    </View>
  );
}

function Value({ text }: { text: string }) {
  return <Text style={styles.value}>{text}</Text>;
}

function Segmented<T extends string | boolean>({ options, value, onChange }: { options: Array<{ label: string; value: T }>; value: T; onChange: (v: T) => void }) {
  return (
    <View style={styles.seg}>
      {options.map((o) => (
        <Pressable key={String(o.value)} onPress={() => onChange(o.value)} style={[styles.segItem, o.value === value && styles.segOn]}>
          <Text style={[styles.segText, o.value === value && { color: '#000' }]}>{o.label}</Text>
        </Pressable>
      ))}
    </View>
  );
}

function Field(props: React.ComponentProps<typeof TextInput>) {
  return <TextInput placeholderTextColor="#6b7280" autoCapitalize="none" autoCorrect={false} spellCheck={false} style={styles.field} {...props} />;
}

function useStore() {
  const version = Store.useTop10Version();
  const [, force] = useState(0);
  useEffect(() => {
    Store.initTop10().then(() => force((n) => n + 1));
  }, []);
  return version;
}

function ago(at?: number): string {
  if (!at) return 'not fetched yet';
  const mins = Math.round((Date.now() - at) / 60000);
  if (mins < 1) return 'updated just now';
  if (mins < 60) return `updated ${mins} min ago`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `updated ${hours} hour${hours === 1 ? '' : 's'} ago`;
  const days = Math.round(hours / 24);
  return days === 1 ? 'updated yesterday' : `updated ${days} days ago`;
}

const regionName = (code: string) => REGIONS.find((r) => r.code === code)?.name ?? code.toUpperCase();
const servicesList = (ids: Iterable<string>) =>
  Array.from(ids).map((id) => SERVICE_NAMES[id as StreamingServiceId] ?? id).join(', ');

function resetDate(fps: string[]): string | null {
  const resets = fps.map((fp) => Budget.quotaFor(fp)?.resetsAt).filter((d): d is number => !!d);
  if (!resets.length) return null;
  const d = new Date(Math.min(...resets));
  return `${d.getUTCDate()} ${d.toLocaleString('en', { month: 'short', timeZone: 'UTC' })}, ${String(d.getUTCHours()).padStart(2, '0')}:00 UTC`;
}

function callsLeftThisMonth(fps: string[]): number | null {
  const quotas = fps.map((fp) => Budget.quotaFor(fp));
  if (quotas.some((q) => !q)) return null;
  return quotas.reduce((n, q) => n + quotaRemaining(q!), 0);
}

// ---------------------------------------------------------------- overview

export function Top10ListsSettings() {
  const nav: any = useNavigation();
  useStore();
  const { settings } = useAppSettings();
  const fpCount = Store.sourceInfos().length;
  const keyCount = Store.keyInfos().length;
  const fps = Store.keyFingerprints();
  const left = callsLeftThisMonth(fps);
  const region = Store.region();
  const topOn = Store.availableServices().filter((s) => settings.top10Services.includes(s)).length;
  const newOn = Store.newRowServices().filter((s) => settings.top10NewServices.includes(s)).length;
  const refreshLabel = settings.top10RefreshHours === 12 ? 'Every 12 hours' : settings.top10RefreshHours === 48 ? 'Every 2 days' : 'Every day';

  return (
    <Page title="Top 10 Lists">
      <Group>
        <Row
          first
          title="Show on Home"
          subtitle={Store.hasAnySource() ? 'Top 10 rows for each service after Continue Watching' : 'Add a FlixPatrol API or a Streaming Availability key first'}
          right={<SettingsSwitch value={settings.top10Enabled} onValueChange={(v) => Store.updateTop10Settings({ top10Enabled: v })} />}
        />
      </Group>

      <Group title="Sources" footer="Top 10 lists come from FlixPatrol first, then Streaming Availability. New This Week uses Streaming Availability.">
        <Row
          first
          title="FlixPatrol"
          subtitle={
            <View style={styles.statusLine}>
              <View style={[styles.dot, fpCount > 0 && (Store.getFlixPatrolError() ? styles.dotErr : styles.dotOk)]} />
              <Text style={styles.rowSub}>
                {fpCount === 0 ? 'Not set up' : `${fpCount} API${fpCount === 1 ? '' : 's'} · tried first for Top 10`}
              </Text>
            </View>
          }
          chevron
          onPress={() => nav.navigate('Top10FlixPatrolSettings')}
        />
        <Row
          title="Streaming Availability"
          subtitle={
            <View style={styles.statusLine}>
              <View style={[styles.dot, keyCount > 0 && (Store.getLastError() ? styles.dotErr : styles.dotOk)]} />
              <Text style={styles.rowSub}>
                {keyCount === 0 ? 'Not set up' : `${keyCount} key${keyCount === 1 ? '' : 's'}${left !== null ? ` · ${left.toLocaleString()} calls left` : ''}`}
              </Text>
            </View>
          }
          chevron
          onPress={() => nav.navigate('Top10KeysSettings')}
        />
      </Group>

      <Group title="Rows">
        <Row first title="Region" right={<Value text={regionName(region)} />} chevron onPress={() => nav.navigate('Top10RegionSettings')} />
        <Row
          title="Movies and Shows"
          subtitle={settings.top10SplitByType ? 'Two rows per service' : 'One mixed row per service'}
          right={
            <Segmented
              options={[{ label: 'Separate', value: true }, { label: 'Mixed', value: false }]}
              value={settings.top10SplitByType}
              onChange={(v) => Store.updateTop10Settings({ top10SplitByType: v })}
            />
          }
        />
        <Row
          title="Top 10 Services"
          right={<Value text={Store.hasAnySource() ? `${topOn} on` : 'None yet'} />}
          chevron
          onPress={() => nav.navigate('Top10ServicesSettings', { mode: 'top' })}
        />
        {Store.hasKey() ? (
          <Row title="New This Week" right={<Value text={`${newOn} on`} />} chevron onPress={() => nav.navigate('Top10ServicesSettings', { mode: 'new' })} />
        ) : null}
      </Group>

      <Group title="Usage">
        <Row
          first
          title="Refresh Lists"
          right={
            <GlassMenu
              items={[12, 24, 48].map((h) => ({
                title: h === 12 ? 'Every 12 hours' : h === 48 ? 'Every 2 days' : 'Every day',
                checked: settings.top10RefreshHours === h,
                onPress: () => Store.updateTop10Settings({ top10RefreshHours: h }),
              }))}
              accessibilityLabel="Refresh lists"
            >
              <View style={styles.menuValue}>
                <Value text={refreshLabel} />
                <Ionicons name="chevron-expand" size={14} color="#6b7280" style={{ marginLeft: 4 }} />
              </View>
            </GlassMenu>
          }
        />
        <Row
          title="Usage and Saved Lists"
          subtitle={keyCount ? `${Budget.totalCallsToday(fps)} of ${Budget.dailyLimit() * keyCount} calls today` : 'FlixPatrol lists are free to refresh'}
          chevron
          onPress={() => nav.navigate('Top10UsageSettings')}
        />
      </Group>
    </Page>
  );
}

// ---------------------------------------------------------------- FlixPatrol

export function Top10FlixPatrolSettings() {
  useStore();
  const sources = Store.sourceInfos();
  const services = Store.getFlixPatrolServices();
  const error = Store.getFlixPatrolError();
  const [url, setUrl] = useState('');
  const [key, setKey] = useState('');
  const [adding, setAdding] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  const add = async () => {
    setAdding(true);
    setMessage(null);
    const err = await Store.addFlixPatrolSource(url, key);
    setAdding(false);
    if (err) setMessage(err);
    else {
      setUrl('');
      setKey('');
    }
  };

  const status =
    sources.length === 0
      ? { ok: null, title: 'Not set up', sub: 'Add the URL of a FlixPatrol JSON API and its key.' }
      : error
        ? { ok: false, title: `${sources.length} API${sources.length === 1 ? '' : 's'} · last check failed`, sub: error }
        : {
            ok: true,
            title: `Connected · ${sources.length} API${sources.length === 1 ? '' : 's'}`,
            sub: services === null ? 'Checking which charts this region has…' : services.size ? `Charts here: ${servicesList(services)}` : `No charts for ${regionName(Store.region())}`,
          };

  return (
    <Page title="FlixPatrol">
      <Group>
        <Row first title={<StatusTitle ok={status.ok} text={status.title} />} subtitle={status.sub} />
      </Group>

      {sources.length ? (
        <Group title="APIs" footer="Tried in order for every Top 10 row; the next one is used if one fails. No call limit.">
          {sources.map((s, i) => (
            <Row
              key={s.id}
              first={i === 0}
              title={s.host}
              subtitle={`Key ${s.masked} · ${i === 0 ? 'tried first' : `fallback ${i}`}`}
              right={
                <View style={styles.btnRow}>
                  {i > 0 ? <Button label="Use First" onPress={() => Store.preferFlixPatrolSource(s.id)} /> : null}
                  <Button label="Remove" kind="danger" onPress={() => Store.removeFlixPatrolSource(s.id)} />
                </View>
              }
            />
          ))}
        </Group>
      ) : null}

      <Group title="Add an API" footer="The base URL of a FlixPatrol JSON API (v2) and its key. It is checked before it is saved.">
        <View style={styles.form}>
          <Field value={url} onChangeText={setUrl} placeholder="https://… (FlixPatrol JSON API v2)" keyboardType="url" textContentType="URL" />
          <Field value={key} onChangeText={setKey} placeholder="API key" secureTextEntry textContentType="password" />
          {message ? <Text style={styles.error}>{message}</Text> : null}
          <View style={styles.formEnd}>
            <Button label={adding ? 'Checking…' : 'Add'} kind="primary" busy={adding} onPress={add} />
          </View>
        </View>
      </Group>
    </Page>
  );
}

// ---------------------------------------------------------------- Streaming Availability

export function Top10KeysSettings() {
  useStore();
  const keys = Store.keyInfos();
  const fps = keys.map((k) => k.id);
  const left = callsLeftThisMonth(fps);
  const reset = resetDate(fps);
  const [key, setKey] = useState('');
  const [adding, setAdding] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  const add = async () => {
    setAdding(true);
    setMessage(null);
    const err = await Store.addKey(key);
    setAdding(false);
    if (err) setMessage(err);
    else setKey('');
  };

  const error = Store.getLastError();
  const statusTitle = keys.length === 0 ? 'Not set up' : left !== null ? `${left.toLocaleString()} calls left this month` : `${keys.length} key${keys.length === 1 ? '' : 's'} added`;
  const statusSub =
    keys.length === 0
      ? 'Free keys come from developers.movieofthenight.com.'
      : error ?? `Across ${keys.length} key${keys.length === 1 ? '' : 's'}${reset ? ` · resets ${reset}` : ''}`;

  return (
    <Page title="Streaming Availability">
      <Group>
        <Row first title={<StatusTitle ok={keys.length === 0 ? null : !error} text={statusTitle} />} subtitle={statusSub} />
      </Group>

      {keys.length ? (
        <Group title="Keys" footer="Each key has 1,000 calls a month; more keys add up. Each request uses the key with the most calls left.">
          {keys.map((k, i) => {
            const quota = Budget.quotaFor(k.id);
            const usage = quota ? `${quota.used} used · ${quotaRemaining(quota)} left · ${Budget.callsToday(k.id)} today` : `${Budget.callsToday(k.id)} calls today`;
            return (
              <Row
                key={k.id}
                first={i === 0}
                title={`Key ${k.masked}`}
                subtitle={usage}
                right={<Button label="Remove" kind="danger" onPress={() => Store.removeKey(k.id)} />}
              />
            );
          })}
        </Group>
      ) : null}

      <Group title="Add a Key" footer="Used for New This Week rows, and for Top 10 lists FlixPatrol doesn't have. Adding a key uses one call to check it.">
        <View style={styles.form}>
          <Field value={key} onChangeText={setKey} placeholder="Paste a Streaming Availability key" secureTextEntry textContentType="password" />
          {message ? <Text style={styles.error}>{message}</Text> : null}
          <View style={styles.formEnd}>
            <Button label={adding ? 'Checking…' : 'Add Key'} kind="primary" busy={adding} onPress={add} />
          </View>
        </View>
      </Group>
    </Page>
  );
}

// ---------------------------------------------------------------- services

export function Top10ServicesSettings() {
  useStore();
  const route: any = useRoute();
  const mode: 'top' | 'new' = route.params?.mode === 'new' ? 'new' : 'top';
  const { settings } = useAppSettings();
  const field = mode === 'top' ? 'top10Services' : 'top10NewServices';
  const chosen = settings[field];
  const services = mode === 'top' ? Store.availableServices() : Store.newRowServices();

  const toggle = (service: StreamingServiceId, on: boolean) => {
    const next = on ? Array.from(new Set([...chosen, service])) : chosen.filter((s) => s !== service);
    Store.updateTop10Settings({ [field]: next } as any);
  };

  return (
    <Page title={mode === 'top' ? 'Top 10 Services' : 'New This Week'}>
      {services.length === 0 ? (
        <Group>
          <Row first title="No services yet" subtitle="Add a FlixPatrol API or a Streaming Availability key to see the services for your region." />
        </Group>
      ) : (
        <Group
          title={regionName(Store.region())}
          footer={mode === 'top' ? 'Services marked FlixPatrol only have no Streaming Availability chart.' : 'Titles added to each service in the last 7 days.'}
        >
          {services.map((service, i) => (
            <Row
              key={service}
              first={i === 0}
              title={mode === 'top' ? SERVICE_NAMES[service] : `New on ${SERVICE_NAMES[service]}`}
              subtitle={mode === 'top' && !hasStreamingAvailability(service) ? 'FlixPatrol only' : undefined}
              right={<SettingsSwitch value={chosen.includes(service)} onValueChange={(v) => toggle(service, v)} />}
            />
          ))}
        </Group>
      )}
    </Page>
  );
}

// ---------------------------------------------------------------- region

export function Top10RegionSettings() {
  const nav: any = useNavigation();
  useStore();
  const current = Store.region();
  return (
    <Page title="Region">
      <Group footer="Charts and availability for this country. Defaults to your iPhone's region.">
        {REGIONS.map((r, i) => (
          <Row
            key={r.code}
            first={i === 0}
            title={r.name}
            right={r.code === current ? <Ionicons name="checkmark" size={20} color="#fff" /> : undefined}
            onPress={() => {
              Store.updateTop10Settings({ top10Region: r.code });
              nav.goBack();
            }}
          />
        ))}
      </Group>
    </Page>
  );
}

// ---------------------------------------------------------------- usage and saved lists

export function Top10UsageSettings() {
  const version = useStore();
  const keys = Store.keyInfos();
  const fps = keys.map((k) => k.id);
  const [lists, setLists] = useState<Store.SavedList[]>([]);
  const [busy, setBusy] = useState<string | null>(null);
  const [limit, setLimit] = useState(Budget.dailyLimit());

  const reload = useCallback(() => {
    Store.savedLists().then(setLists);
  }, []);
  useEffect(reload, [reload, version]);

  const run = async (id: string, task: () => Promise<void>) => {
    setBusy(id);
    await task();
    setBusy(null);
    reload();
  };

  const perRefresh = Store.callsPerRefresh();

  return (
    <Page title="Usage and Saved Lists">
      {keys.length ? (
        <Group title="Streaming Availability" footer="Keys stop for the day at the limit, and keep 10 calls of each month in reserve.">
          <Row
            first
            title="Daily Limit per Key"
            right={
              <GlassMenu
                items={Budget.DAILY_LIMIT_CHOICES.map((n) => ({
                  title: `${n} calls`,
                  checked: limit === n,
                  onPress: () => {
                    Budget.setDailyLimit(n);
                    setLimit(n);
                  },
                }))}
                accessibilityLabel="Daily limit per key"
              >
                <View style={styles.menuValue}>
                  <Value text={`${limit} calls`} />
                  <Ionicons name="chevron-expand" size={14} color="#6b7280" style={{ marginLeft: 4 }} />
                </View>
              </GlassMenu>
            }
          />
          <Row
            title="Today"
            subtitle={perRefresh ? `About ${perRefresh} call${perRefresh === 1 ? '' : 's'} per refresh with these rows` : 'Every row comes from FlixPatrol'}
            right={<Value text={`${Budget.totalCallsToday(fps)} of ${limit * keys.length}`} />}
          />
        </Group>
      ) : null}

      <Group footer="Refetching costs Streaming Availability calls only; FlixPatrol is free.">
        <View style={[styles.row, styles.actions]}>
          <Button label={busy === 'all' ? 'Refetching…' : 'Refetch All'} busy={busy === 'all'} onPress={() => run('all', Store.refreshNow)} />
          <Button label="Clear Saved Lists" kind="danger" onPress={() => run('clear', Store.clearSavedLists)} />
        </View>
      </Group>

      <Group title="Saved Lists">
        {lists.length === 0 ? (
          <Row first title="No lists yet" subtitle="Lists appear here once a source is set up and Top 10 rows are on." />
        ) : (
          lists.map((list, i) => (
            <Row
              key={list.id}
              first={i === 0}
              title={list.title}
              subtitle={`${list.count} titles · ${list.source} · ${ago(list.fetchedAt)}`}
              right={<Button label="Refetch" busy={busy === list.id} onPress={() => run(list.id, () => Store.refetch(list.id))} />}
            />
          ))
        )}
      </Group>
    </Page>
  );
}

// ---------------------------------------------------------------- styles

const styles = StyleSheet.create({
  container: { flex: 1 },
  content: { paddingHorizontal: 16 },
  footer: { color: '#8e8e93', fontSize: 12, lineHeight: 16, marginTop: -10, marginBottom: 18, marginHorizontal: 4 },
  row: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 14, paddingVertical: 12, minHeight: 50, gap: 10 },
  rowBorder: { borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: 'rgba(255,255,255,0.08)' },
  pressed: { backgroundColor: 'rgba(255,255,255,0.06)' },
  rowText: { flex: 1, minWidth: 0 },
  rowTitle: { color: '#fff', fontSize: 15 },
  rowSub: { color: '#8e8e93', fontSize: 12.5, marginTop: 2, lineHeight: 17 },
  value: { color: '#8e8e93', fontSize: 15 },
  menuValue: { flexDirection: 'row', alignItems: 'center', paddingVertical: 4 },
  statusLine: { flexDirection: 'row', alignItems: 'center', gap: 7 },
  dot: { width: 8, height: 8, borderRadius: 4, backgroundColor: '#8e8e93', marginTop: 2 },
  dotOk: { backgroundColor: '#30d158' },
  dotErr: { backgroundColor: '#ff9f0a' },
  btnRow: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  btn: { paddingHorizontal: 12, height: 32, borderRadius: 8, backgroundColor: 'rgba(255,255,255,0.12)', alignItems: 'center', justifyContent: 'center', minWidth: 60 },
  btnPrimary: { backgroundColor: '#fff' },
  btnDanger: { backgroundColor: 'transparent', paddingHorizontal: 4, minWidth: 0 },
  btnText: { color: '#fff', fontSize: 14, fontWeight: '600' },
  seg: { flexDirection: 'row', backgroundColor: 'rgba(255,255,255,0.1)', borderRadius: 8, padding: 2 },
  segItem: { paddingHorizontal: 10, paddingVertical: 5, borderRadius: 6 },
  segOn: { backgroundColor: '#fff' },
  segText: { color: 'rgba(255,255,255,0.8)', fontSize: 13, fontWeight: '600' },
  form: { padding: 14, gap: 10 },
  field: {
    backgroundColor: 'rgba(0,0,0,0.35)',
    borderRadius: 10,
    paddingHorizontal: 12,
    height: 42,
    color: '#fff',
    fontSize: 15,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.14)',
  },
  formEnd: { flexDirection: 'row', justifyContent: 'flex-end' },
  error: { color: '#ff9f0a', fontSize: 13 },
  actions: { justifyContent: 'space-between' },
});
