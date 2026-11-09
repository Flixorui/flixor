import { useCallback, useEffect, useState } from 'react';
import {
  catalogDisplayName,
  getCatalogItems,
  getCatalogs,
  subscribeAddons,
  type StremioCatalog,
  type StremioCatalogItem,
} from '@/stremio';
import { useSettings } from '@/state/settings';

export interface StremioCatalogRow {
  /** Stable id, used as the row key in `homeRowOrder`. */
  id: string;
  title: string;
  catalog: StremioCatalog;
  items: StremioCatalogItem[];
}

export interface StremioCatalogRowsResult {
  rows: StremioCatalogRow[];
  loading: boolean;
  error: string | null;
  reload: () => void;
}

const ROW_ITEM_LIMIT = 30;
const ROW_FETCH_CONCURRENCY = 4;

/** Home rows from installed addon catalogs. Rows appear in addon order as they load. */
export function useStremioCatalogRows(): StremioCatalogRowsResult {
  const { showStremioCatalogRows } = useSettings();
  const [rows, setRows] = useState<StremioCatalogRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [revision, setRevision] = useState(0);

  const reload = useCallback(() => setRevision((value) => value + 1), []);

  useEffect(() => subscribeAddons(reload), [reload]);

  useEffect(() => {
    setError(null);
    if (!showStremioCatalogRows) {
      setRows([]);
      setLoading(false);
      return;
    }

    const controller = new AbortController();
    let cancelled = false;
    const loaded = new Map<StremioCatalog, StremioCatalogRow>();
    let failures = 0;

    (async () => {
      setLoading(true);
      const catalogs = await getCatalogs();
      const publish = () => {
        if (cancelled) return;
        setRows(catalogs.flatMap((catalog) => loaded.get(catalog) ?? []));
      };

      let next = 0;
      const worker = async () => {
        while (next < catalogs.length) {
          const catalog = catalogs[next];
          next += 1;
          try {
            const items = await getCatalogItems(catalog, { signal: controller.signal });
            if (items.length > 0) {
              loaded.set(catalog, {
                id: `stremio-catalog-${catalog.installationId}-${catalog.type}-${catalog.id}`,
                title: catalogDisplayName(catalog),
                catalog,
                items: items.slice(0, ROW_ITEM_LIMIT),
              });
              publish();
            }
          } catch (err: any) {
            if (err?.name === 'AbortError') return;
            failures += 1;
          }
        }
      };
      await Promise.all(Array.from({ length: ROW_FETCH_CONCURRENCY }, worker));
      if (cancelled) return;
      publish();
      if (catalogs.length > 0 && failures === catalogs.length) setError('Addon catalogs could not be loaded');
      setLoading(false);
    })();

    return () => {
      cancelled = true;
      controller.abort();
    };
  }, [showStremioCatalogRows, revision]);

  return { rows, loading, error, reload };
}
