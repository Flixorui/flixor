import React, { useEffect, useMemo, useState } from 'react';
import { View, Text, ScrollView, Switch, StyleSheet } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import { fetchCollections, CollectionItem } from '../../core/CollectionsData';
import { useAppSettings } from '../../hooks/useAppSettings';

export default function CollectionRowsSettings() {
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const headerHeight = insets.top + 52;
  const { settings, updateSetting } = useAppSettings();
  const [collections, setCollections] = useState<CollectionItem[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      setLoading(true);
      const colls = await fetchCollections();
      // Sort by childCount descending (same as home screen)
      colls.sort((a, b) => (b.childCount || 0) - (a.childCount || 0));
      setCollections(colls);
      setLoading(false);
    })();
  }, []);

  const hiddenKeys = useMemo(
    () => new Set(settings.hiddenCollectionKeys || []),
    [settings.hiddenCollectionKeys]
  );

  const toggleCollection = async (ratingKey: string, visible: boolean) => {
    const currentHidden = settings.hiddenCollectionKeys || [];
    let nextHidden: string[];

    if (visible) {
      // Remove from hidden list
      nextHidden = currentHidden.filter((k) => k !== ratingKey);
    } else {
      // Add to hidden list
      nextHidden = [...currentHidden, ratingKey];
    }

    await updateSetting('hiddenCollectionKeys', nextHidden);
  };

  return (
    <View style={styles.container}>
      <SettingsHeader title="Collection Rows" onBack={() => nav.goBack()} />
      <ScrollView
        contentContainerStyle={[
          styles.content,
          { paddingTop: headerHeight + 12, paddingBottom: insets.bottom + 100 },
        ]}
      >
        <SettingsCard title="VISIBLE COLLECTIONS">
          {loading && (
            <View style={styles.loadingRow}>
              <Ionicons name="cloud-download-outline" size={18} color="#9ca3af" />
              <Text style={styles.loadingText}>Loading collections...</Text>
            </View>
          )}
          {!loading && collections.length === 0 && (
            <View style={styles.loadingRow}>
              <Text style={styles.loadingText}>No Plex collections found.</Text>
            </View>
          )}
          {!loading &&
            collections.map((coll, index) => {
              const isVisible = !hiddenKeys.has(coll.ratingKey);
              return (
                <SettingItem
                  key={coll.ratingKey}
                  title={coll.title}
                  description={
                    coll.childCount !== undefined
                      ? `${coll.childCount} items`
                      : 'Collection'
                  }
                  icon="albums-outline"
                  renderRight={() => (
                    <Switch
                      value={isVisible}
                      onValueChange={(value) =>
                        toggleCollection(coll.ratingKey, value)
                      }
                    />
                  )}
                  isLast={index === collections.length - 1}
                />
              );
            })}
        </SettingsCard>

        <Text style={styles.note}>
          Toggle collections to show or hide them on the home screen. Only the top 5 collections are
          displayed on the home screen.
        </Text>
      </ScrollView>
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
  loadingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 14,
    paddingVertical: 14,
  },
  loadingText: {
    color: '#9ca3af',
    fontSize: 13,
  },
  note: {
    color: '#9ca3af',
    fontSize: 12,
    marginTop: 6,
  },
});
