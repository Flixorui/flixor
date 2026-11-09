import React, { useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import FastImage from '@d11/react-native-fast-image';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import SettingsSwitch from '../components/settings/SettingsSwitch';
import Chip from '../components/collections/Chip';
import OptionSheet from '../components/collections/OptionSheet';
import SourceEditor from '../components/collections/SourceEditor';
import { useTheme } from '../hooks/useTheme';
import ToastHost, { showToast } from '../components/Toast';
import {
  SOURCE_KIND_LABELS,
  createUserCollection,
  fetchUserCollectionPreview,
  saveUserCollection,
  sourceSubtitle,
  sourceTitle,
  userCollectionContentKey,
  type UserCollection,
  type UserCollectionCoverStyle,
  type UserCollectionItem,
  type UserCollectionSource,
  type UserCollectionSourceKind,
} from '../core/UserCollectionsStore';

const KIND_OPTIONS = (Object.keys(SOURCE_KIND_LABELS) as UserCollectionSourceKind[]).map((value) => ({
  value,
  label: SOURCE_KIND_LABELS[value],
}));

/**
 * Create or edit a user collection. Presented as a modal by whichever screen opens it.
 * `initialName` and `initialSources` prefill a new collection, e.g. from a person's page.
 */
export default function UserCollectionEditor({
  visible,
  collection,
  initialName,
  initialSources,
  onClose,
  onSaved,
}: {
  visible: boolean;
  collection?: UserCollection | null;
  initialName?: string;
  initialSources?: UserCollectionSource[];
  onClose: () => void;
  onSaved?: (collection: UserCollection) => void;
}) {
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const [draft, setDraft] = useState<UserCollection>(createUserCollection);
  const [saving, setSaving] = useState(false);
  const [pickingKind, setPickingKind] = useState(false);
  const [sourceEditor, setSourceEditor] = useState<{ kind: UserCollectionSourceKind; existing: UserCollectionSource | null } | null>(null);
  const [coverItems, setCoverItems] = useState<UserCollectionItem[]>([]);
  const [loadingCovers, setLoadingCovers] = useState(false);
  const [pendingStyle, setPendingStyle] = useState<UserCollectionCoverStyle>('poster');
  const wasVisible = useRef(false);

  // Seeds once per presentation so a store update can't wipe unsaved edits
  useEffect(() => {
    if (visible && !wasVisible.current) {
      setDraft(
        collection ?? { ...createUserCollection(), name: initialName ?? '', sources: initialSources ?? [] }
      );
      setSaving(false);
      setCoverItems([]);
      setPendingStyle(collection?.cover?.style ?? 'poster');
    }
    wasVisible.current = visible;
  }, [visible, collection, initialName, initialSources]);

  const contentKey = userCollectionContentKey(draft);

  useEffect(() => {
    if (!visible || draft.sources.length === 0) {
      setCoverItems([]);
      return;
    }
    let current = true;
    setLoadingCovers(true);
    fetchUserCollectionPreview(draft).then((preview) => {
      if (!current) return;
      setCoverItems(preview.items);
      setLoadingCovers(false);
    });
    return () => {
      current = false;
    };
    // contentKey stands in for the sources
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible, contentKey]);

  const name = draft.name.trim();
  const canSave = name.length > 0 && draft.sources.length > 0 && !saving;

  const save = async () => {
    if (!canSave) return;
    setSaving(true);
    const saved = { ...draft, name };
    try {
      await saveUserCollection(saved);
      onSaved?.(saved);
      onClose();
    } catch {
      setSaving(false);
      showToast("Couldn't save this collection.", { kind: 'error' });
    }
  };

  const upsertSource = (source: UserCollectionSource) => {
    setDraft((d) => ({
      ...d,
      sources: d.sources.some((s) => s.id === source.id)
        ? d.sources.map((s) => (s.id === source.id ? source : s))
        : [...d.sources, source],
    }));
  };

  const removeSource = (id: string) => {
    setDraft((d) => ({ ...d, sources: d.sources.filter((s) => s.id !== id) }));
  };

  const moveSource = (index: number, offset: -1 | 1) => {
    setDraft((d) => {
      const target = index + offset;
      if (target < 0 || target >= d.sources.length) return d;
      const sources = [...d.sources];
      [sources[index], sources[target]] = [sources[target], sources[index]];
      return { ...d, sources };
    });
  };

  const activeStyle: UserCollectionCoverStyle = draft.cover?.style ?? pendingStyle;
  const activeUrls = coverItems
    .map((item) => (activeStyle === 'poster' ? item.image : item.backdrop))
    .filter((url): url is string => !!url);

  const setCoverStyle = (style: UserCollectionCoverStyle) => {
    // A poster doesn't suit a backdrop slot, so the pick resets with the style
    setDraft((d) => (d.cover && d.cover.style !== style ? { ...d, cover: undefined } : d));
    setPendingStyle(style);
  };

  const heading = (text: string) => <Text style={[styles.heading, { color: theme.textSecondary }]}>{text}</Text>;

  return (
    <Modal visible={visible} animationType="slide" presentationStyle="pageSheet" onRequestClose={onClose}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        style={{ flex: 1, backgroundColor: theme.surfaceElevated, paddingTop: Platform.OS === 'android' ? insets.top : 0 }}
      >
        <View style={[styles.bar, { borderBottomColor: theme.separator }]}>
          <Pressable onPress={onClose} hitSlop={8}>
            <Text style={{ color: theme.textPrimary, fontSize: 16 }}>Cancel</Text>
          </Pressable>
          <Text style={[styles.barTitle, { color: theme.textPrimary }]}>{collection ? 'Edit Collection' : 'New Collection'}</Text>
          <Pressable onPress={save} disabled={!canSave} hitSlop={8}>
            {saving ? (
              <ActivityIndicator color={theme.textPrimary} />
            ) : (
              <Text style={{ color: canSave ? theme.accentBright : theme.textDisabled, fontSize: 16, fontWeight: '700' }}>Save</Text>
            )}
          </Pressable>
        </View>

        <ScrollView contentContainerStyle={{ padding: 16, paddingBottom: insets.bottom + 32 }} keyboardShouldPersistTaps="handled">
          {heading('Name')}
          <TextInput
            value={draft.name}
            onChangeText={(text) => setDraft((d) => ({ ...d, name: text }))}
            placeholder="Collection name"
            placeholderTextColor={theme.textTertiary}
            style={[styles.input, { color: theme.textPrimary, backgroundColor: theme.surfaceOverlay }]}
            accessibilityLabel="Collection name"
          />

          <View style={styles.toggle}>
            <View style={{ flex: 1 }}>
              <Text style={{ color: theme.textPrimary, fontSize: 16, fontWeight: '500' }}>Show on Home</Text>
              <Text style={{ color: theme.textTertiary, fontSize: 13, marginTop: 2 }}>Adds a row to your Home screen</Text>
            </View>
            <SettingsSwitch value={draft.showOnHome} onValueChange={(showOnHome) => setDraft((d) => ({ ...d, showOnHome }))} />
          </View>

          {heading('Sources')}
          {draft.sources.length === 0 ? (
            <Text style={{ color: theme.textTertiary, fontSize: 14, marginBottom: 8 }}>
              Add at least one source. Titles from every source are merged without duplicates.
            </Text>
          ) : null}
          {draft.sources.map((source, index) => (
            <View key={source.id} style={[styles.source, { backgroundColor: theme.surfaceOverlay }]}>
              <Pressable style={{ flex: 1 }} onPress={() => setSourceEditor({ kind: source.kind, existing: source })}>
                <Text numberOfLines={1} style={{ color: theme.textPrimary, fontSize: 15, fontWeight: '600' }}>{sourceTitle(source)}</Text>
                <Text numberOfLines={1} style={{ color: theme.textTertiary, fontSize: 13, marginTop: 2 }}>{sourceSubtitle(source)}</Text>
              </Pressable>
              <Pressable onPress={() => moveSource(index, -1)} disabled={index === 0} hitSlop={6} style={styles.sourceIcon} accessibilityLabel="Move up">
                <Ionicons name="chevron-up" size={20} color={index === 0 ? theme.textDisabled : theme.textSecondary} />
              </Pressable>
              <Pressable onPress={() => moveSource(index, 1)} disabled={index === draft.sources.length - 1} hitSlop={6} style={styles.sourceIcon} accessibilityLabel="Move down">
                <Ionicons name="chevron-down" size={20} color={index === draft.sources.length - 1 ? theme.textDisabled : theme.textSecondary} />
              </Pressable>
              <Pressable onPress={() => removeSource(source.id)} hitSlop={6} style={styles.sourceIcon} accessibilityLabel="Remove source">
                <Ionicons name="close" size={20} color={theme.danger} />
              </Pressable>
            </View>
          ))}
          <Pressable onPress={() => setPickingKind(true)} style={[styles.addSource, { borderColor: theme.separatorStrong }]}>
            <Ionicons name="add" size={20} color={theme.accentBright} />
            <Text style={{ color: theme.accentBright, fontWeight: '600', marginLeft: 6 }}>Add Source</Text>
          </Pressable>

          {draft.sources.length > 0 ? (
            <>
              {heading('Cover')}
              <View style={{ flexDirection: 'row' }}>
                <Chip label="Poster" active={activeStyle === 'poster'} onPress={() => setCoverStyle('poster')} />
                <Chip label="Backdrop" active={activeStyle === 'backdrop'} onPress={() => setCoverStyle('backdrop')} />
                {draft.cover ? <Chip label="Automatic" onPress={() => setDraft((d) => ({ ...d, cover: undefined }))} /> : null}
              </View>
              {loadingCovers ? (
                <ActivityIndicator color={theme.textPrimary} style={{ marginVertical: 16 }} />
              ) : activeUrls.length === 0 ? (
                <Text style={{ color: theme.textTertiary, fontSize: 14 }}>No artwork available from these sources.</Text>
              ) : (
                <ScrollView horizontal showsHorizontalScrollIndicator={false}>
                  {activeUrls.map((url) => {
                    const active = draft.cover?.url === url;
                    const isPoster = activeStyle === 'poster';
                    return (
                      <Pressable
                        key={url}
                        onPress={() => setDraft((d) => ({ ...d, cover: { url, style: activeStyle } }))}
                        style={[
                          styles.coverOption,
                          { width: isPoster ? 80 : 160, height: isPoster ? 120 : 90, borderColor: active ? theme.accent : 'transparent' },
                        ]}
                      >
                        <FastImage source={{ uri: url }} style={StyleSheet.absoluteFillObject} resizeMode={FastImage.resizeMode.cover} />
                      </Pressable>
                    );
                  })}
                </ScrollView>
              )}
            </>
          ) : null}
        </ScrollView>
      </KeyboardAvoidingView>

      {/* The app's toast host sits behind this modal */}
      {visible ? <ToastHost /> : null}

      <OptionSheet
        visible={pickingKind}
        title="Add Source"
        options={KIND_OPTIONS}
        onSelect={(kind) => setSourceEditor({ kind, existing: null })}
        onClose={() => setPickingKind(false)}
      />
      <SourceEditor
        kind={sourceEditor?.kind ?? null}
        existing={sourceEditor?.existing}
        onSave={upsertSource}
        onClose={() => setSourceEditor(null)}
      />
    </Modal>
  );
}

const styles = StyleSheet.create({
  bar: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16, paddingVertical: 14, borderBottomWidth: StyleSheet.hairlineWidth },
  barTitle: { fontSize: 16, fontWeight: '700' },
  heading: { fontSize: 13, fontWeight: '600', marginTop: 18, marginBottom: 8 },
  input: { borderRadius: 10, paddingHorizontal: 14, paddingVertical: 12, fontSize: 16 },
  toggle: { flexDirection: 'row', alignItems: 'center', marginTop: 16 },
  source: { flexDirection: 'row', alignItems: 'center', padding: 12, borderRadius: 10, marginBottom: 8 },
  sourceIcon: { paddingLeft: 10 },
  addSource: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', paddingVertical: 12, borderRadius: 10, borderWidth: 1, borderStyle: 'dashed' },
  coverOption: { borderRadius: 6, overflow: 'hidden', marginRight: 8, borderWidth: 2 },
});
