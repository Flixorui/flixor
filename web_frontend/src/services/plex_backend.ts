// Backend-backed Plex service (reads only for now)
import { API_BASE_URL } from './api';
const API_BASE = `${API_BASE_URL.replace(/\/$/, '')}/plex`;

async function backendFetch<T = any>(path: string, params?: Record<string, any>): Promise<T> {
  const base = API_BASE.replace(/\/$/, '');
  let url = `${base}${path}`;
  if (params) {
    const qs = new URLSearchParams();
    Object.entries(params).forEach(([k, v]) => {
      if (v !== undefined && v !== null) qs.append(k, String(v));
    });
    const q = qs.toString();
    if (q) url += (url.includes('?') ? '&' : '?') + q;
  }
  const res = await fetch(url, { credentials: 'include' });
  if (!res.ok) throw new Error(`Plex backend error ${res.status}`);
  return res.json();
}

// Wrap helpers to match legacy shapes used by UI (MediaContainer.*)

export async function plexBackendLibraries() {
  const libs = await backendFetch<any[]>('/libraries');
  return { MediaContainer: { Directory: libs || [] } };
}

export async function plexBackendOnDeckGlobal() {
  const items = await backendFetch<any[]>('/ondeck');
  return { MediaContainer: { Metadata: items || [] } };
}

export async function plexBackendContinue() {
  const items = await backendFetch<any[]>('/continue');
  return { MediaContainer: { Metadata: items || [] } };
}

export async function plexBackendRecentlyAdded(libraryKey?: string) {
  const items = await backendFetch<any[]>('/recent', libraryKey ? { library: libraryKey } : undefined);
  return { MediaContainer: { Metadata: items || [] } };
}

export async function plexBackendLibraryAll(sectionKey: string, params?: Record<string, any>) {
  const mc = await backendFetch<any>(`/library/${encodeURIComponent(sectionKey)}/all`, params);
  return { MediaContainer: mc?.MediaContainer || mc };
}

export async function plexBackendMetadata(ratingKey: string) {
  const meta = await backendFetch<any>(`/metadata/${encodeURIComponent(ratingKey)}`);
  return { MediaContainer: { Metadata: [meta] } };
}

export async function plexBackendMetadataWithExtras(ratingKey: string) {
  const meta = await backendFetch<any>(`/metadata/${encodeURIComponent(ratingKey)}`, {
    includeExtras: 1,
    includeExternalMedia: 1,
    includeChildren: 1,
  });
  return { MediaContainer: { Metadata: [meta] } };
}

export async function plexBackendLibrarySecondary(sectionKey: string, directory: string) {
  const mc = await backendFetch<any>(`/library/${encodeURIComponent(sectionKey)}/${encodeURIComponent(directory)}`);
  return { MediaContainer: mc };
}

export async function plexBackendDir(path: string, params?: Record<string, any>) {
  const p = path.startsWith('/') ? path.slice(1) : path;
  try {
    const mc = await backendFetch<any>(`/dir/${p}`, params);
    return { MediaContainer: mc };
  } catch (e: any) {
    // Graceful fallback for 404/500 so Details page doesn’t crash
    console.warn('[plexBackendDir] request failed', { path, error: String(e?.message || e) });
    return { MediaContainer: { Metadata: [], Directory: [] } } as any;
  }
}

export async function plexBackendSearch(query: string, type?: 1 | 2) {
  const items = await backendFetch<any[]>(`/search`, type ? { query, type } : { query });
  return { MediaContainer: { Metadata: items || [] } };
}

export async function plexBackendCollections(sectionKey: string) {
  const mc = await backendFetch<any>(`/library/${encodeURIComponent(sectionKey)}/collections`);
  return { MediaContainer: mc };
}

export async function plexBackendFindByGuid(guid: string, type?: 1 | 2) {
  const mc = await backendFetch<any>('/findByGuid', type ? { guid, type } : { guid });
  return { MediaContainer: mc };
}
