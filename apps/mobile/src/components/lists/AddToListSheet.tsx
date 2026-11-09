import React, { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, Modal, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import * as Haptics from 'expo-haptics';
import { useTheme } from '../../hooks/useTheme';
import ToastHost, { showToast } from '../Toast';
import TraktListEditorSheet from './TraktListEditorSheet';
import {
  addTitleToTraktList,
  fetchTraktLists,
  isTraktAvailable,
  traktListErrorMessage,
  type TraktListTitle,
  type TraktUserList,
} from '../../core/TraktListsData';

/**
 * Picks one of the user's Trakt lists to add a title to. Self-contained, so any screen
 * can present it with a title.
 */
export default function AddToListSheet({
  title,
  onClose,
}: {
  /** The title to add. `null` hides the sheet. */
  title: TraktListTitle | null;
  onClose: () => void;
}) {
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const [lists, setLists] = useState<TraktUserList[]>([]);
  const [phase, setPhase] = useState<'loading' | 'loaded' | 'error'>('loading');
  const [busyId, setBusyId] = useState<number | null>(null);
  const [creating, setCreating] = useState(false);

  const visible = title !== null;

  const load = useCallback(async () => {
    setPhase('loading');
    try {
      setLists(await fetchTraktLists());
      setPhase('loaded');
    } catch (e) {
      console.log('[AddToListSheet] load error:', e);
      setPhase('error');
    }
  }, []);

  useEffect(() => {
    if (visible && isTraktAvailable()) void load();
  }, [visible, load]);

  const add = async (list: TraktUserList) => {
    if (!title || busyId !== null) return;
    setBusyId(list.ids.trakt);
    try {
      const added = await addTitleToTraktList(list.ids.trakt, title);
      if (added) {
        Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
        showToast(`Added to ${list.name}`, { kind: 'success' });
        onClose();
      } else {
        showToast(`Trakt couldn't find "${title.title}"`, { kind: 'error' });
      }
    } catch (e) {
      console.log('[AddToListSheet] add error:', e);
      showToast(traktListErrorMessage(e, "Couldn't add to this list."), { kind: 'error' });
    } finally {
      setBusyId(null);
    }
  };

  const connected = isTraktAvailable();

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable
          style={[styles.sheet, { backgroundColor: theme.surfaceElevated, paddingBottom: insets.bottom + 12 }]}
          onPress={() => undefined}
        >
          <Text style={[styles.title, { color: theme.textPrimary }]}>Add to List</Text>
          {title ? (
            <Text numberOfLines={1} style={[styles.subtitle, { color: theme.textTertiary }]}>
              {title.title}
            </Text>
          ) : null}

          {!connected ? (
            <Text style={[styles.message, { color: theme.textSecondary }]}>Connect Trakt in Settings to use lists.</Text>
          ) : phase === 'loading' ? (
            <View style={styles.center}>
              <ActivityIndicator color={theme.textPrimary} />
            </View>
          ) : phase === 'error' ? (
            <View style={styles.center}>
              <Text style={[styles.message, { color: theme.textSecondary }]}>Couldn't load your lists.</Text>
              <Pressable onPress={load}>
                <Text style={{ color: theme.accentBright, fontWeight: '600' }}>Try Again</Text>
              </Pressable>
            </View>
          ) : (
            <ScrollView style={{ maxHeight: 360 }}>
              {lists.map((list) => (
                <Pressable key={list.ids.trakt} onPress={() => add(list)} style={styles.row}>
                  <Ionicons name="list" size={20} color={theme.textSecondary} />
                  <View style={{ flex: 1, marginLeft: 12 }}>
                    <Text numberOfLines={1} style={{ color: theme.textPrimary, fontSize: 16, fontWeight: '500' }}>
                      {list.name}
                    </Text>
                    <Text style={{ color: theme.textTertiary, fontSize: 13, marginTop: 1 }}>
                      {list.item_count === 1 ? '1 title' : `${list.item_count} titles`}
                    </Text>
                  </View>
                  {busyId === list.ids.trakt ? <ActivityIndicator color={theme.textPrimary} /> : null}
                </Pressable>
              ))}
              <Pressable onPress={() => setCreating(true)} style={styles.row}>
                <Ionicons name="add" size={22} color={theme.accentBright} />
                <Text style={{ color: theme.accentBright, fontSize: 16, fontWeight: '600', marginLeft: 12 }}>New List</Text>
              </Pressable>
            </ScrollView>
          )}
        </Pressable>
      </Pressable>

      {/* The app's toast host sits behind this modal */}
      {visible ? <ToastHost /> : null}

      <TraktListEditorSheet
        visible={creating}
        onClose={() => setCreating(false)}
        onSaved={(list) => {
          setLists((prev) => [...prev, list]);
          void add(list);
        }}
      />
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.55)', justifyContent: 'flex-end' },
  sheet: { borderTopLeftRadius: 18, borderTopRightRadius: 18, paddingTop: 16, paddingHorizontal: 16 },
  title: { fontSize: 17, fontWeight: '700' },
  subtitle: { fontSize: 13, marginTop: 2, marginBottom: 8 },
  message: { fontSize: 15, paddingVertical: 12 },
  center: { alignItems: 'center', paddingVertical: 24 },
  row: { flexDirection: 'row', alignItems: 'center', paddingVertical: 12 },
});
