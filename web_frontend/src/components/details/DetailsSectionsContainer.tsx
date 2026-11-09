import { useMemo, useState, type ReactNode } from 'react';
import DetailsTabs from '@/components/DetailsTabs';
import { useSettings, SETTINGS_DEFAULTS, type DetailsSectionKey } from '@/state/settings';

const TAB_IDS: Record<DetailsSectionKey, string> = {
  episodes: 'EPISODES',
  suggested: 'SUGGESTED',
  collection: 'COLLECTION',
  cast: 'CAST',
  trailers: 'TRAILERS',
  comments: 'COMMENTS',
  about: 'DETAILS',
};

const TAB_LABELS: Record<DetailsSectionKey, string> = {
  episodes: 'Episodes',
  suggested: 'Suggested',
  collection: 'Collection',
  cast: 'Cast & Crew',
  trailers: 'Trailers',
  comments: 'Comments',
  about: 'Details',
};

/** Enabled sections in the user's order. Keys missing from stored settings keep their default slot. */
export function orderedSectionKeys(order: Array<{ key: DetailsSectionKey; enabled: boolean }>): DetailsSectionKey[] {
  const known = new Set(order.map((section) => section.key));
  const complete = [...order, ...SETTINGS_DEFAULTS.detailsSectionOrder.filter((section) => !known.has(section.key))];
  return complete.filter((section) => section.enabled).map((section) => section.key);
}

export interface DetailsSectionDefinition {
  available: boolean;
  render: () => ReactNode;
  count?: number;
}

/** Shows the details sections in the user's order, as tabs or as one page. */
export default function DetailsSectionsContainer({
  sections,
  initialKey,
}: {
  sections: Record<DetailsSectionKey, DetailsSectionDefinition>;
  initialKey: DetailsSectionKey;
}) {
  const settings = useSettings();
  const keys = useMemo(
    () => orderedSectionKeys(settings.detailsSectionOrder).filter((key) => sections[key].available),
    [settings.detailsSectionOrder, sections],
  );
  const [activeTab, setActiveTab] = useState<string | null>(null);

  if (settings.detailsLayout === 'unified') {
    return (
      <div className="page-gutter-left space-y-12 py-8">
        {keys.map((key) => <div key={key}>{sections[key].render()}</div>)}
      </div>
    );
  }

  const tabIds = keys.map((key) => TAB_IDS[key]);
  const requested = activeTab ?? TAB_IDS[initialKey];
  const effectiveTab = tabIds.includes(requested) ? requested : tabIds[0];
  const activeKey = keys.find((key) => TAB_IDS[key] === effectiveTab);

  return (
    <>
      {keys.length > 0 && (
        <DetailsTabs
          tabs={keys.map((key) => ({ id: TAB_IDS[key], label: TAB_LABELS[key], count: sections[key].count }))}
          activeTab={effectiveTab}
          onTabChange={setActiveTab}
        />
      )}
      <div className="page-gutter-left py-8">{activeKey && sections[activeKey].render()}</div>
    </>
  );
}
