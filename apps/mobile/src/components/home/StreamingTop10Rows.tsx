/**
 * Top 10 rows per streaming service (FlixPatrol first, then Streaming Availability) and the
 * optional "New on" rows. Saved lists show straight away; due lists refresh in the
 * background within the call budget. With no source set up, the TMDB "Top 10 This Week" row
 * stands in.
 *
 * Home spreads these rows out (see HomeRows), so this file gives the sections as data
 * (useStreamingTop10Sections) and renders one section at a time (StreamingTop10Section).
 */

import React, { useEffect, useRef, useState } from 'react';
import Top10Row, { type RankedItem } from './Top10Row';
import Row from '../Row';
import {
  cachedSections, initTop10, isActive, onTop10Update, top10Sections, useTop10Version, type Top10Section,
} from '../../core/top10/Top10Store';

export type { Top10Section };

/**
 * The sections to show. `active` is false when no Top 10 source is set up (Home then shows
 * TMDB's weekly Top 10 instead); `sections` is null until the saved lists are read.
 */
export function useStreamingTop10Sections(): { active: boolean; sections: Top10Section[] | null } {
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

  return { active, sections };
}

/** One Top 10 (ranked) or "New on" row. */
export const StreamingTop10Section = React.memo(function StreamingTop10Section({
  section,
  onItemPress,
}: {
  section: Top10Section;
  onItemPress: (item: RankedItem) => void;
}) {
  if (section.kind === 'top') {
    return <Top10Row title={section.title} items={section.items} onItemPress={onItemPress} />;
  }
  return (
    <Row
      title={section.title}
      items={section.items}
      layout="poster"
      getImageUri={(item: RankedItem) => item.image}
      getTitle={(item: RankedItem) => item.title}
      onItemPress={onItemPress}
      keyPrefix={`${section.id}-`}
    />
  );
});

/** TMDB's weekly Top 10, when no FlixPatrol / Streaming Availability source is set up. */
export function FallbackTop10Row({ onItemPress }: { onItemPress: (item: RankedItem) => void }) {
  return <Top10Row onItemPress={onItemPress} />;
}
