import { useCallback, useEffect, useState } from 'react';
import { useFocusEffect } from '@react-navigation/native';
import {
  getBrowsableCatalogs,
  MAX_HOME_CATALOG_ROWS,
  type InstalledCatalog,
} from '../../stremio/StremioCatalogService';

const NONE: InstalledCatalog[] = [];

/** Catalog rows for Home. Re-read on focus so addon changes in Settings show up. */
export function useStremioCatalogs(enabled: boolean): InstalledCatalog[] {
  const [catalogs, setCatalogs] = useState<InstalledCatalog[]>(NONE);

  const load = useCallback(async () => {
    if (!enabled) {
      setCatalogs(NONE);
      return;
    }
    try {
      const next = (await getBrowsableCatalogs()).slice(0, MAX_HOME_CATALOG_ROWS);
      // Keeps the same objects when nothing changed, so rows don't reload.
      setCatalogs((prev) =>
        prev.length === next.length && prev.every((catalog, index) => catalog.rowId === next[index].rowId) ? prev : next
      );
    } catch (e) {
      console.log('[Home] Could not read addon catalogs:', e);
    }
  }, [enabled]);

  useEffect(() => {
    load();
  }, [load]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  return catalogs;
}
