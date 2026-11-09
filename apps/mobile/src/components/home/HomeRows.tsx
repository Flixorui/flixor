import React, { useCallback } from 'react';
import { View } from 'react-native';
import type { Ionicons } from '@expo/vector-icons';
import ContinueWatchingLandscapeRow from '../ContinueWatchingLandscapeRow';
import ContinueWatchingPosterRow from '../ContinueWatchingPosterRow';
import LazyRow from '../LazyRow';
import Row, { type RowBadge } from '../Row';
import type { RowItem } from '../../core/HomeData';
import type { RowLayout } from '../../core/SettingsData';
import type { ContinueWatchingEntry } from '../../core/TraktContinueWatching';
import { fetchUserCollectionPreview, userCollectionContentKey, type UserCollection } from '../../core/UserCollectionsStore';
import type { InstalledCatalog } from '../../stremio/StremioCatalogService';
import type { ContinueWatchingMenuAction } from './continueWatchingMenu';
import { fetchCatalogRowItems, type HomeDisplayRow } from './homeRowModels';
import type { HomeViewport } from './homeViewport';
import { preheatArtwork } from './preheat';

const getPoster = (item: RowItem) => item.image;
const getBackdrop = (item: RowItem) => item.backdrop || item.image;
const getTitle = (item: RowItem) => item.title;
const getSubtitle = (item: RowItem) => item.subtitle;

function preheatItems(items: RowItem[], layout: RowLayout): void {
  preheatArtwork(items.map(layout === 'landscape' ? getBackdrop : getPoster));
}

interface SharedRowProps {
  rowId: string;
  title: string;
  caption?: string;
  layout: RowLayout;
  onItemPress: (item: RowItem) => void;
  onBrowseRow: (rowId: string) => void;
}

const ItemsRow = React.memo(function ItemsRow({
  rowId,
  title,
  items,
  titleIcon,
  badge,
  eager,
  layout,
  onItemPress,
  onBrowseRow,
}: SharedRowProps & {
  items: RowItem[];
  titleIcon?: keyof typeof Ionicons.glyphMap;
  badge?: RowBadge;
  eager?: boolean;
}) {
  const browse = useCallback(() => onBrowseRow(rowId), [onBrowseRow, rowId]);
  const RowComponent: any = eager ? Row : LazyRow;
  return (
    <RowComponent
      title={title}
      titleIcon={titleIcon}
      badge={badge}
      items={items}
      layout={layout}
      getImageUri={layout === 'landscape' ? getBackdrop : getPoster}
      getTitle={getTitle}
      getSubtitle={getSubtitle}
      onItemPress={onItemPress}
      onBrowsePress={browse}
      keyPrefix={`${rowId}-`}
    />
  );
});

const CatalogRow = React.memo(function CatalogRow({
  rowId,
  title,
  caption,
  catalog,
  layout,
  viewport,
  onItemPress,
  onBrowseRow,
}: SharedRowProps & { catalog: InstalledCatalog; viewport: HomeViewport }) {
  const fetchData = useCallback(async () => {
    const items = await fetchCatalogRowItems(catalog);
    preheatItems(items, layout);
    return items;
  }, [catalog, layout]);
  const browse = useCallback(() => onBrowseRow(rowId), [onBrowseRow, rowId]);

  return (
    <LazyRow
      title={title}
      caption={caption}
      titleIcon="extension-puzzle-outline"
      fetchData={fetchData}
      viewport={viewport}
      errorSource={catalog.addonName}
      layout={layout}
      getImageUri={layout === 'landscape' ? getBackdrop : getPoster}
      getTitle={getTitle}
      getSubtitle={getSubtitle}
      onItemPress={onItemPress}
      onBrowsePress={browse}
      keyPrefix={`${rowId}-`}
    />
  );
});

const UserCollectionRow = React.memo(function UserCollectionRow({
  rowId,
  title,
  collection,
  layout,
  viewport,
  onItemPress,
  onBrowseRow,
}: SharedRowProps & { collection: UserCollection; viewport: HomeViewport }) {
  const fetchData = useCallback(async () => {
    const preview = await fetchUserCollectionPreview(collection);
    if (preview.items.length === 0 && preview.failures.length > 0) {
      throw new Error(preview.failures[0].message);
    }
    const items: RowItem[] = preview.items.map((item) => ({
      id: item.id,
      title: item.title,
      image: item.image,
      backdrop: item.backdrop,
      mediaType: item.type === 'movie' ? 'movie' : 'tv',
      subtitle: item.year,
    }));
    preheatItems(items, layout);
    return items;
  }, [collection, layout]);
  const browse = useCallback(() => onBrowseRow(rowId), [onBrowseRow, rowId]);

  return (
    <LazyRow
      title={title}
      titleIcon="albums-outline"
      fetchData={fetchData}
      viewport={viewport}
      errorSource={collection.name}
      layout={layout}
      getImageUri={layout === 'landscape' ? getBackdrop : getPoster}
      getTitle={getTitle}
      getSubtitle={getSubtitle}
      onItemPress={onItemPress}
      onBrowsePress={browse}
      keyPrefix={`${rowId}-`}
    />
  );
});

interface HomeRowsProps {
  rows: HomeDisplayRow[];
  layout: RowLayout;
  viewport: HomeViewport;
  /** Changes on pull-to-refresh, so self-loading rows fetch again. */
  reloadToken: number;
  showContinueWatching: boolean;
  continueLayout: 'poster' | 'landscape';
  continueEntries: ContinueWatchingEntry[];
  blurNextUp: boolean;
  onContinuePress: (entry: ContinueWatchingEntry) => void;
  onContinueAction: (action: ContinueWatchingMenuAction, entry: ContinueWatchingEntry) => void;
  onContinueBrowse: () => void;
  onItemPress: (item: RowItem) => void;
  onBrowseRow: (rowId: string) => void;
}

/**
 * The row list. Rows are memoized on their own data, so Home re-rendering (the hero
 * rotating, one row loading) does not re-render the others.
 */
function HomeRows({
  rows,
  layout,
  viewport,
  reloadToken,
  showContinueWatching,
  continueLayout,
  continueEntries,
  blurNextUp,
  onContinuePress,
  onContinueAction,
  onContinueBrowse,
  onItemPress,
  onBrowseRow,
}: HomeRowsProps) {
  return (
    <View style={{ marginTop: 16 }} onLayout={(event) => viewport.setContentY(event.nativeEvent.layout.y)}>
      {rows.map(({ model, title, caption }) => {
        const shared = { rowId: model.id, title, caption, layout, onItemPress, onBrowseRow };
        switch (model.type) {
          case 'continueWatching': {
            if (!showContinueWatching || continueEntries.length === 0) return null;
            const ContinueRow = continueLayout === 'landscape' ? ContinueWatchingLandscapeRow : ContinueWatchingPosterRow;
            return (
              <ContinueRow
                key={model.id}
                title={title}
                entries={continueEntries}
                blurNextUp={blurNextUp}
                onItemPress={onContinuePress}
                onAction={onContinueAction}
                onBrowsePress={onContinueBrowse}
              />
            );
          }
          case 'items':
            return (
              <ItemsRow
                key={model.id}
                {...shared}
                items={model.items}
                titleIcon={model.titleIcon}
                badge={model.badge}
                eager={model.eager}
              />
            );
          case 'catalog':
            return <CatalogRow key={`${model.id}-${reloadToken}`} {...shared} catalog={model.catalog} viewport={viewport} />;
          case 'userCollection':
            return (
              <UserCollectionRow
                key={`${model.id}-${reloadToken}-${userCollectionContentKey(model.collection)}`}
                {...shared}
                collection={model.collection}
                viewport={viewport}
              />
            );
        }
      })}
    </View>
  );
}

export default React.memo(HomeRows);
