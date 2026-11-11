import React, { useCallback, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Text, TextInput, View, Animated } from 'react-native';
import { useFocusEffect, useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsSwitch from '../../components/settings/SettingsSwitch';
import { useAppSettings } from '../../hooks/useAppSettings';
import { useTheme } from '../../hooks/useTheme';
import {
  HOME_CONTINUE_WATCHING_ROW_ID,
  homeRowTitle,
  moveHomeRow,
  orderedHomeRowCatalog,
  renameHomeRow,
  resetHomeRowOrder,
  setHomeRowHidden,
  showAllHomeRows,
} from '../../core/HomeRowsStore';
import type { HomeRowDescriptor, HomeRowKind } from '../../core/SettingsData';

const KIND_ICONS: Record<HomeRowKind, keyof typeof Ionicons.glyphMap> = {
  continueWatching: 'play-circle-outline',
  recentlyAdded: 'time-outline',
  collection: 'sparkles-outline',
  watchlist: 'bookmark-outline',
  discovery: 'flame-outline',
  genre: 'pricetags-outline',
  trakt: 'stats-chart-outline',
  stremioCatalog: 'extension-puzzle-outline',
  userCollection: 'albums-outline',
};

const KIND_LABELS: Record<HomeRowKind, string> = {
  continueWatching: 'Continue Watching',
  recentlyAdded: 'Plex library',
  collection: 'Plex collection',
  watchlist: 'Watchlist',
  discovery: 'Discovery',
  genre: 'Genre',
  trakt: 'Trakt',
  stremioCatalog: 'Addon catalog',
  userCollection: 'Your collection',
};

export default function HomeRowsSettings() {
  const headerScrollY = React.useRef(new Animated.Value(0)).current;
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const theme = useTheme();
  const { settings, updateSetting, refresh } = useAppSettings();
  const [renaming, setRenaming] = useState<HomeRowDescriptor | null>(null);
  const [draft, setDraft] = useState('');

  useFocusEffect(
    useCallback(() => {
      refresh();
    }, [refresh])
  );

  const rows = orderedHomeRowCatalog(settings);
  const hidden = new Set(settings.homeRowHidden);
  const hasHiddenRows = settings.homeRowHidden.length > 0;

  const isVisible = (row: HomeRowDescriptor) =>
    row.id === HOME_CONTINUE_WATCHING_ROW_ID ? settings.showContinueWatchingRow : !hidden.has(row.id);

  const setVisible = (row: HomeRowDescriptor, visible: boolean) => {
    // Continue Watching already has its own switch; both controls share it.
    if (row.id === HOME_CONTINUE_WATCHING_ROW_ID) updateSetting('showContinueWatchingRow', visible);
    else setHomeRowHidden(row.id, !visible);
  };

  const startRename = (row: HomeRowDescriptor) => {
    setDraft(homeRowTitle(settings.homeRowTitles, row.id, row.defaultTitle));
    setRenaming(row);
  };

  const finishRename = (value: string | undefined) => {
    if (renaming) renameHomeRow(renaming.id, value, renaming.defaultTitle);
    setRenaming(null);
  };

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      <SettingsHeader scrollY={headerScrollY} title="Home Rows" onBack={() => nav.goBack()} />
      {rows.length === 0 ? (
        <View style={[styles.empty, { paddingTop: insets.top + 52 }]}>
          <Ionicons name="reorder-three-outline" size={40} color={theme.textTertiary} />
          <Text style={[styles.emptyTitle, { color: theme.textPrimary }]}>No rows to arrange yet</Text>
          <Text style={[styles.emptySubtitle, { color: theme.textSecondary }]}>
            Your rows appear here once the Home screen has loaded.
          </Text>
        </View>
      ) : (
        <Animated.ScrollView
        scrollEventThrottle={16}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: headerScrollY } } }], { useNativeDriver: false })}
          contentContainerStyle={{ paddingTop: insets.top + 64, paddingBottom: insets.bottom + 100, paddingHorizontal: 16 }}
        >
          <View style={styles.toolbar}>
            <Pressable onPress={resetHomeRowOrder} disabled={settings.homeRowOrder.length === 0} hitSlop={8}>
              <Text style={[styles.toolbarText, { color: settings.homeRowOrder.length ? theme.accentBright : theme.textDisabled }]}>
                Reset Order
              </Text>
            </Pressable>
            <Pressable onPress={showAllHomeRows} disabled={!hasHiddenRows} hitSlop={8}>
              <Text style={[styles.toolbarText, { color: hasHiddenRows ? theme.accentBright : theme.textDisabled }]}>
                Show All
              </Text>
            </Pressable>
          </View>

          <View style={[styles.card, { backgroundColor: theme.surface }]}>
            {rows.map((row, index) => {
              const visible = isVisible(row);
              const title = homeRowTitle(settings.homeRowTitles, row.id, row.defaultTitle);
              const renamed = title !== row.defaultTitle;
              const subtitle = [row.detail ?? KIND_LABELS[row.kind], renamed ? `Originally "${row.defaultTitle}"` : null]
                .filter(Boolean)
                .join(' · ');
              return (
                <View
                  key={row.id}
                  style={[styles.row, index > 0 && { borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: theme.separator }]}
                >
                  <View style={styles.moveButtons}>
                    <Pressable
                      onPress={() => moveHomeRow(row.id, -1)}
                      disabled={index === 0}
                      hitSlop={4}
                      accessibilityRole="button"
                      accessibilityLabel={`Move ${title} up`}
                    >
                      <Ionicons name="chevron-up" size={18} color={index === 0 ? theme.textDisabled : theme.textSecondary} />
                    </Pressable>
                    <Pressable
                      onPress={() => moveHomeRow(row.id, 1)}
                      disabled={index === rows.length - 1}
                      hitSlop={4}
                      accessibilityRole="button"
                      accessibilityLabel={`Move ${title} down`}
                    >
                      <Ionicons
                        name="chevron-down"
                        size={18}
                        color={index === rows.length - 1 ? theme.textDisabled : theme.textSecondary}
                      />
                    </Pressable>
                  </View>
                  <Ionicons name={KIND_ICONS[row.kind]} size={18} color={theme.textSecondary} style={styles.kindIcon} />
                  <Pressable style={styles.titleBlock} onPress={() => startRename(row)} accessibilityLabel={`Rename ${title}`}>
                    <Text style={[styles.title, { color: visible ? theme.textPrimary : theme.textTertiary }]} numberOfLines={1}>
                      {title}
                    </Text>
                    <Text style={[styles.subtitle, { color: theme.textTertiary }]} numberOfLines={1}>
                      {subtitle}
                    </Text>
                  </Pressable>
                  <SettingsSwitch value={visible} onValueChange={(value) => setVisible(row, value)} />
                </View>
              );
            })}
          </View>

          <Text style={[styles.note, { color: theme.textSecondary }]}>
            Tap a row to rename it. Rows you turn off stay here so you can bring them back. New rows appear next to where
            they would normally be.
          </Text>
        </Animated.ScrollView>
      )}

      <Modal visible={renaming !== null} transparent animationType="fade" onRequestClose={() => setRenaming(null)}>
        <View style={styles.modalBackdrop}>
          <View style={[styles.modal, { backgroundColor: theme.surfaceElevated }]}>
            <Text style={[styles.modalTitle, { color: theme.textPrimary }]}>Rename Row</Text>
            <TextInput
              value={draft}
              onChangeText={setDraft}
              placeholder={renaming?.defaultTitle}
              placeholderTextColor={theme.textTertiary}
              autoFocus
              returnKeyType="done"
              onSubmitEditing={() => finishRename(draft)}
              style={[styles.input, { color: theme.textPrimary, borderColor: theme.separatorStrong }]}
            />
            <View style={styles.modalActions}>
              <Pressable onPress={() => finishRename(undefined)} hitSlop={8}>
                <Text style={[styles.modalAction, { color: theme.textSecondary }]}>Use Default</Text>
              </Pressable>
              <View style={styles.modalActionsRight}>
                <Pressable onPress={() => setRenaming(null)} hitSlop={8}>
                  <Text style={[styles.modalAction, { color: theme.textSecondary }]}>Cancel</Text>
                </Pressable>
                <Pressable onPress={() => finishRename(draft)} hitSlop={8}>
                  <Text style={[styles.modalAction, { color: theme.accentBright }]}>Save</Text>
                </Pressable>
              </View>
            </View>
          </View>
        </View>
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  empty: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 32 },
  emptyTitle: { fontSize: 18, fontWeight: '600', marginTop: 12, textAlign: 'center' },
  emptySubtitle: { fontSize: 14, marginTop: 6, textAlign: 'center' },
  toolbar: { flexDirection: 'row', justifyContent: 'space-between', marginBottom: 10, paddingHorizontal: 4 },
  toolbarText: { fontSize: 14, fontWeight: '600' },
  card: { borderRadius: 14, overflow: 'hidden' },
  row: { flexDirection: 'row', alignItems: 'center', paddingVertical: 8, paddingHorizontal: 12, minHeight: 60 },
  moveButtons: { marginRight: 10, alignItems: 'center' },
  kindIcon: { marginRight: 10 },
  titleBlock: { flex: 1, marginRight: 10 },
  title: { fontSize: 15, fontWeight: '500' },
  subtitle: { fontSize: 12, marginTop: 2 },
  note: { fontSize: 12, lineHeight: 17, marginTop: 12, paddingHorizontal: 4 },
  modalBackdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.6)', justifyContent: 'center', padding: 28 },
  modal: { borderRadius: 16, padding: 18 },
  modalTitle: { fontSize: 17, fontWeight: '700', marginBottom: 12 },
  input: { borderWidth: 1, borderRadius: 10, paddingHorizontal: 12, paddingVertical: 10, fontSize: 15 },
  modalActions: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginTop: 16 },
  modalActionsRight: { flexDirection: 'row', gap: 20 },
  modalAction: { fontSize: 15, fontWeight: '600' },
});
