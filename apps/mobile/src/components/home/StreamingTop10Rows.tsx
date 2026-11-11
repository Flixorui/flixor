/**
 * Top 10 rows per streaming service (FlixPatrol first, then Streaming Availability) and the
 * optional "New on" rows. Saved lists show straight away; due lists refresh in the
 * background within the call budget. With no source set up, the TMDB "Top 10 This Week" row
 * stands in.
 */

import React, { useEffect, useRef, useState } from 'react';
import Top10Row, { type RankedItem } from './Top10Row';
import Row from '../Row';
import {
  cachedSections, initTop10, isActive, onTop10Update, top10Sections, useTop10Version, type Top10Section,
} from '../../core/top10/Top10Store';

export default function StreamingTop10Rows({ onItemPress }: { onItemPress: (item: RankedItem) => void }) {
  const version = useTop10Version();
  const [sections, setSections] = useState<Top10Section[] | null>(null);
  const [active, setActive] = useState(false);
  const loadId = useRef(0);

  const load = React.useCallback(async (refresh: boolean) => {
    const id = ++loadId.current;
    await initTop10();
    if (id !== loadId.current) return;
    setActive(isActive());
    if (!isActive()) {
      setSections([]);
      return;
    }
    const saved = await cachedSections();
    if (id === loadId.current) setSections(saved);
    if (!refresh) return;
    const fresh = await top10Sections();
    if (id === loadId.current) setSections(fresh);
  }, []);

  useEffect(() => {
    load(true);
    return onTop10Update(() => load(false));
  }, [load]);

  // Settings changes (services, split, region) rebuild from the saved lists
  useEffect(() => {
    if (version > 0) setActive(isActive());
  }, [version]);

  if (!active) return <Top10Row onItemPress={onItemPress} />;
  if (!sections) return null;

  return (
    <>
      {sections.map((section) =>
        section.kind === 'top' ? (
          <Top10Row key={section.id} title={section.title} items={section.items} onItemPress={onItemPress} />
        ) : (
          <Row
            key={section.id}
            title={section.title}
            items={section.items}
            layout="poster"
            getImageUri={(item: RankedItem) => item.image}
            getTitle={(item: RankedItem) => item.title}
            onItemPress={onItemPress}
            keyPrefix={`${section.id}-`}
          />
        )
      )}
    </>
  );
}
