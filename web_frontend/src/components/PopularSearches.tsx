import Row from './Row';

interface SearchItem {
  id: string;
  title: string;
  type: 'movie' | 'tv' | 'person' | 'collection';
  image?: string;
  year?: string;
}

interface PopularSearchesProps {
  items: SearchItem[];
  onItemClick: (item: SearchItem) => void;
}

export default function PopularSearches({ items, onItemClick }: PopularSearchesProps) {
  // Map to Row's landscape card items; use provided image (prefer backdrops upstream)
  const rowItems = (items || []).map((it) => ({ id: it.id, title: it.title, image: it.image || '', badge: it.year }));
  return (
    <Row
      title="Popular Searches"
      items={rowItems}
      gutter="edge"
      onItemClick={(id) => {
        const found = items.find((x) => x.id === id);
        if (found) onItemClick(found);
      }}
    />
  );
}
