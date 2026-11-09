import React, { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '../../hooks/useTheme';
import {
  TRAKT_LIST_PRIVACY_OPTIONS,
  createTraktList,
  traktListErrorMessage,
  updateTraktList,
  type TraktListPrivacy,
  type TraktUserList,
} from '../../core/TraktListsData';

/** Create a Trakt list, or edit one's name, description and privacy. */
export default function TraktListEditorSheet({
  visible,
  list,
  onClose,
  onSaved,
}: {
  visible: boolean;
  /** The list to edit. Omit to create one. */
  list?: TraktUserList | null;
  onClose: () => void;
  onSaved: (list: TraktUserList) => void;
}) {
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [privacy, setPrivacy] = useState<TraktListPrivacy>('private');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!visible) return;
    setName(list?.name ?? '');
    setDescription(list?.description ?? '');
    setPrivacy(list?.privacy ?? 'private');
    setSaving(false);
    setError(null);
  }, [visible, list]);

  const trimmedName = name.trim();
  const canSave = trimmedName.length > 0 && !saving;

  const save = async () => {
    if (!canSave) return;
    setSaving(true);
    setError(null);
    try {
      const values = { name: trimmedName, description: description.trim(), privacy };
      const saved = list ? await updateTraktList(list.ids.trakt, values) : await createTraktList(values);
      onSaved(saved);
      onClose();
    } catch (e) {
      console.log('[TraktListEditorSheet] save error:', e);
      setError(traktListErrorMessage(e, "Couldn't save this list."));
      setSaving(false);
    }
  };

  const inputStyle = [styles.input, { color: theme.textPrimary, backgroundColor: theme.surfaceOverlay }];

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={{ flex: 1 }}>
        <Pressable style={styles.backdrop} onPress={onClose}>
          <Pressable
            style={[styles.sheet, { backgroundColor: theme.surfaceElevated, paddingBottom: insets.bottom + 16 }]}
            onPress={() => undefined}
          >
            <Text style={[styles.title, { color: theme.textPrimary }]}>{list ? 'Edit List' : 'New List'}</Text>

            <TextInput
              value={name}
              onChangeText={setName}
              placeholder="Name"
              placeholderTextColor={theme.textTertiary}
              style={inputStyle}
              autoFocus={!list}
              accessibilityLabel="List name"
            />
            <TextInput
              value={description}
              onChangeText={setDescription}
              placeholder="Description (optional)"
              placeholderTextColor={theme.textTertiary}
              style={[inputStyle, styles.description]}
              multiline
              accessibilityLabel="List description"
            />

            <Text style={[styles.section, { color: theme.textSecondary }]}>Who can see this</Text>
            {TRAKT_LIST_PRIVACY_OPTIONS.map((option) => {
              const active = privacy === option.value;
              return (
                <Pressable
                  key={option.value}
                  onPress={() => setPrivacy(option.value)}
                  style={[styles.privacy, active && { backgroundColor: theme.accentSoft }]}
                >
                  <Text style={{ color: active ? theme.accentBright : theme.textPrimary, fontSize: 15, fontWeight: '600' }}>
                    {option.label}
                  </Text>
                  <Text style={{ color: theme.textTertiary, fontSize: 13 }}>{option.detail}</Text>
                </Pressable>
              );
            })}

            {error ? <Text style={[styles.error, { color: theme.danger }]}>{error}</Text> : null}

            <View style={styles.actions}>
              <Pressable onPress={onClose} style={[styles.button, { backgroundColor: theme.surfaceOverlay }]}>
                <Text style={{ color: theme.textPrimary, fontWeight: '600' }}>Cancel</Text>
              </Pressable>
              <Pressable
                onPress={save}
                disabled={!canSave}
                style={[styles.button, { backgroundColor: theme.accent, opacity: canSave ? 1 : 0.5 }]}
              >
                {saving ? (
                  <ActivityIndicator color={theme.onAccent} />
                ) : (
                  <Text style={{ color: theme.onAccent, fontWeight: '700' }}>Save</Text>
                )}
              </Pressable>
            </View>
          </Pressable>
        </Pressable>
      </KeyboardAvoidingView>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.55)', justifyContent: 'flex-end' },
  sheet: { borderTopLeftRadius: 18, borderTopRightRadius: 18, padding: 20 },
  title: { fontSize: 18, fontWeight: '700', marginBottom: 14 },
  input: { borderRadius: 10, paddingHorizontal: 14, paddingVertical: 12, fontSize: 16, marginBottom: 10 },
  description: { minHeight: 72, textAlignVertical: 'top' },
  section: { fontSize: 13, fontWeight: '600', marginTop: 6, marginBottom: 6 },
  privacy: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 12, paddingVertical: 10, borderRadius: 10 },
  error: { fontSize: 14, marginTop: 10 },
  actions: { flexDirection: 'row', gap: 12, marginTop: 16 },
  button: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingVertical: 13, borderRadius: 10 },
});
