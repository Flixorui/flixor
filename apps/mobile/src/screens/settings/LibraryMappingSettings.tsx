import React, { useEffect, useMemo, useState } from 'react';
import { View, Text, ScrollView, Pressable, StyleSheet, Modal } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import ConditionalBlurView from '../../components/ConditionalBlurView';
import { fetchAllLibraries } from '../../core/HomeData';
import { useAppSettings } from '../../hooks/useAppSettings';

type LibraryItem = { key: string; title: string; type: string };

type DropdownOption = {
  key: string | undefined;
  title: string;
  subtitle?: string;
};

export default function LibraryMappingSettings() {
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const headerHeight = insets.top + 52;
  const { settings, updateSetting } = useAppSettings();
  const [libraries, setLibraries] = useState<LibraryItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [showMoviesDropdown, setShowMoviesDropdown] = useState(false);
  const [showShowsDropdown, setShowShowsDropdown] = useState(false);

  useEffect(() => {
    (async () => {
      setLoading(true);
      const libs = await fetchAllLibraries();
      setLibraries(libs);
      setLoading(false);
    })();
  }, []);

  // Filter libraries by type
  const movieLibraries = useMemo(
    () => libraries.filter((lib) => lib.type === 'movie'),
    [libraries]
  );
  const showLibraries = useMemo(
    () => libraries.filter((lib) => lib.type === 'show'),
    [libraries]
  );

  // Build dropdown options
  const movieOptions: DropdownOption[] = useMemo(() => [
    { key: undefined, title: 'Automatic', subtitle: 'Use first available library' },
    ...movieLibraries.map((lib) => ({ key: lib.key, title: lib.title })),
  ], [movieLibraries]);

  const showOptions: DropdownOption[] = useMemo(() => [
    { key: undefined, title: 'Automatic', subtitle: 'Use first available library' },
    ...showLibraries.map((lib) => ({ key: lib.key, title: lib.title })),
  ], [showLibraries]);

  // Get selected library titles
  const selectedMovieTitle = useMemo(() => {
    if (!settings.moviesLibraryKey) return 'Automatic';
    const lib = movieLibraries.find((l) => String(l.key) === settings.moviesLibraryKey);
    return lib?.title || 'Automatic';
  }, [settings.moviesLibraryKey, movieLibraries]);

  const selectedShowTitle = useMemo(() => {
    if (!settings.showsLibraryKey) return 'Automatic';
    const lib = showLibraries.find((l) => String(l.key) === settings.showsLibraryKey);
    return lib?.title || 'Automatic';
  }, [settings.showsLibraryKey, showLibraries]);

  const handleSelectMoviesLibrary = async (key: string | undefined) => {
    await updateSetting('moviesLibraryKey', key);
    setShowMoviesDropdown(false);
  };

  const handleSelectShowsLibrary = async (key: string | undefined) => {
    await updateSetting('showsLibraryKey', key);
    setShowShowsDropdown(false);
  };

  const renderDropdownRow = (
    icon: string,
    title: string,
    value: string,
    onPress: () => void,
    disabled: boolean
  ) => (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      style={({ pressed }) => [
        styles.dropdownRow,
        pressed && styles.dropdownRowPressed,
        disabled && styles.dropdownRowDisabled,
      ]}
    >
      <View style={styles.dropdownIcon}>
        <Ionicons name={icon as any} size={22} color="#fff" />
      </View>
      <View style={styles.dropdownContent}>
        <Text style={styles.dropdownTitle}>{title}</Text>
        <Text style={[styles.dropdownValue, disabled && styles.dropdownValueDisabled]}>
          {disabled ? 'Loading...' : value}
        </Text>
      </View>
      <Ionicons name="chevron-down" size={20} color="#6b7280" />
    </Pressable>
  );

  const renderDropdownModal = (
    visible: boolean,
    onClose: () => void,
    title: string,
    options: DropdownOption[],
    selectedKey: string | undefined,
    onSelect: (key: string | undefined) => void
  ) => (
    <Modal
      visible={visible}
      transparent
      animationType="fade"
      onRequestClose={onClose}
    >
      <Pressable style={styles.modalOverlay} onPress={onClose}>
        <View style={styles.modalContent}>
          <ConditionalBlurView intensity={100} tint="dark" style={styles.modalBlur}>
            <Text style={styles.modalTitle}>{title}</Text>
            {options.map((option, index) => {
              const isSelected = option.key === selectedKey ||
                (option.key === undefined && !selectedKey);
              return (
                <Pressable
                  key={option.key ?? 'auto'}
                  onPress={() => onSelect(option.key)}
                  style={[
                    styles.modalOption,
                    isSelected && styles.modalOptionSelected,
                    index < options.length - 1 && styles.modalOptionBorder,
                  ]}
                >
                  <View style={styles.modalOptionContent}>
                    <Text style={[styles.modalOptionTitle, isSelected && styles.modalOptionTitleSelected]}>
                      {option.title}
                    </Text>
                    {option.subtitle && (
                      <Text style={styles.modalOptionSubtitle}>{option.subtitle}</Text>
                    )}
                  </View>
                  {isSelected && (
                    <Ionicons name="checkmark-circle" size={22} color="#3b82f6" />
                  )}
                </Pressable>
              );
            })}
          </ConditionalBlurView>
        </View>
      </Pressable>
    </Modal>
  );

  return (
    <View style={styles.container}>
      <SettingsHeader title="Library Mapping" onBack={() => nav.goBack()} />
      <ScrollView
        contentContainerStyle={[
          styles.content,
          { paddingTop: headerHeight + 12, paddingBottom: insets.bottom + 100 },
        ]}
      >
        <Text style={styles.sectionDescription}>
          Choose which libraries the Movies and Shows pills on the home screen will display.
        </Text>

        <SettingsCard>
          {renderDropdownRow(
            'film-outline',
            'Movies Library',
            selectedMovieTitle,
            () => setShowMoviesDropdown(true),
            loading || movieLibraries.length === 0
          )}
          <View style={styles.separator} />
          {renderDropdownRow(
            'tv-outline',
            'TV Shows Library',
            selectedShowTitle,
            () => setShowShowsDropdown(true),
            loading || showLibraries.length === 0
          )}
        </SettingsCard>

        {!loading && (movieLibraries.length === 0 || showLibraries.length === 0) && (
          <Text style={styles.warningText}>
            {movieLibraries.length === 0 && showLibraries.length === 0
              ? 'No libraries found on your server.'
              : movieLibraries.length === 0
                ? 'No movie libraries found.'
                : 'No TV show libraries found.'}
          </Text>
        )}

        <Text style={styles.note}>
          Selecting "Automatic" will use the first available library of each type.
        </Text>
      </ScrollView>

      {/* Movies Dropdown Modal */}
      {renderDropdownModal(
        showMoviesDropdown,
        () => setShowMoviesDropdown(false),
        'Select Movies Library',
        movieOptions,
        settings.moviesLibraryKey,
        handleSelectMoviesLibrary
      )}

      {/* Shows Dropdown Modal */}
      {renderDropdownModal(
        showShowsDropdown,
        () => setShowShowsDropdown(false),
        'Select TV Shows Library',
        showOptions,
        settings.showsLibraryKey,
        handleSelectShowsLibrary
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0b0b0d',
  },
  content: {
    paddingHorizontal: 16,
    paddingBottom: 40,
  },
  sectionDescription: {
    color: '#9ca3af',
    fontSize: 14,
    lineHeight: 20,
    marginBottom: 20,
  },
  dropdownRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 14,
    paddingVertical: 14,
  },
  dropdownRowPressed: {
    backgroundColor: 'rgba(255,255,255,0.05)',
  },
  dropdownRowDisabled: {
    opacity: 0.5,
  },
  dropdownIcon: {
    width: 40,
    height: 40,
    borderRadius: 10,
    backgroundColor: 'rgba(59,130,246,0.15)',
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 12,
  },
  dropdownContent: {
    flex: 1,
  },
  dropdownTitle: {
    color: '#fff',
    fontSize: 15,
    fontWeight: '500',
  },
  dropdownValue: {
    color: '#3b82f6',
    fontSize: 13,
    marginTop: 2,
  },
  dropdownValueDisabled: {
    color: '#6b7280',
  },
  separator: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: 'rgba(255,255,255,0.08)',
    marginLeft: 66,
  },
  note: {
    color: '#6b7280',
    fontSize: 12,
    marginTop: 12,
    textAlign: 'center',
  },
  warningText: {
    color: '#f59e0b',
    fontSize: 13,
    marginTop: 12,
    textAlign: 'center',
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.6)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  modalContent: {
    width: '85%',
    maxWidth: 340,
    borderRadius: 16,
    overflow: 'hidden',
  },
  modalBlur: {
    padding: 0,
  },
  modalTitle: {
    color: '#fff',
    fontSize: 17,
    fontWeight: '700',
    textAlign: 'center',
    paddingVertical: 16,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: 'rgba(255,255,255,0.1)',
  },
  modalOption: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 14,
  },
  modalOptionSelected: {
    backgroundColor: 'rgba(59,130,246,0.1)',
  },
  modalOptionBorder: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: 'rgba(255,255,255,0.08)',
  },
  modalOptionContent: {
    flex: 1,
  },
  modalOptionTitle: {
    color: '#fff',
    fontSize: 15,
    fontWeight: '500',
  },
  modalOptionTitleSelected: {
    color: '#3b82f6',
  },
  modalOptionSubtitle: {
    color: '#6b7280',
    fontSize: 12,
    marginTop: 2,
  },
});
