import React from 'react';
import { FlatList, View } from 'react-native';
import Poster from '../Poster';
import DetailsSectionHeading, { DetailsSectionStyle } from './DetailsSectionHeading';
import type { RowItem } from '../../core/DetailsData';

/** A row of posters under a details section heading. */
export default function DetailsPosterRow({
  title,
  items,
  onItemPress,
  onTitlePress,
  keyPrefix = '',
}: {
  title: string;
  items: RowItem[];
  onItemPress: (item: RowItem) => void;
  onTitlePress?: () => void;
  keyPrefix?: string;
}) {
  return (
    <View>
      <DetailsSectionHeading title={title} onPress={onTitlePress} />
      <FlatList
        horizontal
        data={items}
        keyExtractor={(item, index) => `${keyPrefix}${item.id || `${title}-${index}`}`}
        renderItem={({ item }) => (
          <Poster uri={item.image} title={item.title} onPress={() => onItemPress(item)} />
        )}
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={{ paddingHorizontal: DetailsSectionStyle.inset }}
        initialNumToRender={6}
        maxToRenderPerBatch={4}
        windowSize={5}
      />
    </View>
  );
}
