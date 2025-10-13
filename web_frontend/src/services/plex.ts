export type PlexConfig = { baseUrl: string; token: string };
import { cached } from './cache';
import { plexBackendFindByGuid } from './plex_backend';
import { loadSettings } from '@/state/settings';
import { plexBackendLibraries, plexBackendLibraryAll } from './plex_backend';

export async function plexLibs(cfg: PlexConfig) {
  const url = `${cfg.baseUrl}/library/sections?X-Plex-Token=${cfg.token}`;
  return cached(`plex:${encodeURIComponent(cfg.baseUrl)}:libs`, 15 * 60 * 1000, async () => {
    const res = await fetch(url, { headers: { Accept: 'application/json' } });
    if (!res.ok) throw new Error(`Plex error ${res.status}`);
    const json = await res.json();
    try {
      if (json && json.MediaContainer && Array.isArray(json.MediaContainer.Directory)) {
        json.MediaContainer.Directory = json.MediaContainer.Directory.filter((d: any) => d.type === 'movie' || d.type === 'show');
      }
    } catch {}
    return json;
  });
}

export async function plexOnDeck(cfg: PlexConfig, libKey: string) {
  const url = `${cfg.baseUrl}/library/sections/${libKey}/onDeck?X-Plex-Token=${cfg.token}`;
  return cached(`plex:${encodeURIComponent(cfg.baseUrl)}:onDeck:${libKey}`, 5 * 60 * 1000, async () => {
    const res = await fetch(url, { headers: { Accept: 'application/json' } });
    if (!res.ok) throw new Error(`Plex error ${res.status}`);
    return res.json();
  });
}

export async function plexOnDeckGlobal(cfg: PlexConfig) {
  const url = `${cfg.baseUrl}/library/onDeck?X-Plex-Token=${cfg.token}`;
  return cached(`plex:${encodeURIComponent(cfg.baseUrl)}:onDeckGlobal`, 2 * 60 * 1000, async () => {
    const res = await fetch(url, { headers: { Accept: 'application/json' } });
    if (!res.ok) throw new Error(`Plex error ${res.status}`);
    return res.json();
  });
}

export function plexImage(baseUrl: string, token: string, path?: string) {
  if (!path) return undefined;
  if (/^https?:\/\//i.test(path)) return path;
  const sep = path.includes('?') ? '&' : '?';
  return `${baseUrl.replace(/\/$/, '')}${path}${sep}X-Plex-Token=${token}`;
}

export async function plexSectionAll(cfg: PlexConfig, sectionKey: string, params?: string) {
  const qs = params?.startsWith('?') ? params : `?${params ?? 'type=1&sort=addedAt:desc'}`;
  if (!sectionKey) throw new Error('Missing section key');
  const url = `${cfg.baseUrl}/library/sections/${sectionKey}/all${qs}${qs.includes('X-Plex-Token') ? '' : (qs.includes('?') ? '&' : '?') + 'X-Plex-Token=' + cfg.token}`;
  return cached(`plex:${encodeURIComponent(cfg.baseUrl)}:all:${sectionKey}:${qs}`, 10 * 60 * 1000, async () => {
    const res = await fetch(url, { headers: { Accept: 'application/json' } });
    if (!res.ok) throw new Error(`Plex error ${res.status}`);
    return res.json();
  });
}

export function withContainer(qs: string, start: number, size: number) {
  const sep = qs.includes('?') ? '&' : '?';
  return `${qs}${sep}X-Plex-Container-Start=${start}&X-Plex-Container-Size=${size}`;
}

// Fetch secondary directories for a library section, e.g., genre, year, etc.
export async function plexLibrarySecondary(cfg: PlexConfig, sectionKey: string, directory: string) {
  const url = `${cfg.baseUrl}/library/sections/${sectionKey}/${directory}?X-Plex-Token=${cfg.token}`;
  return cached(`plex:${encodeURIComponent(cfg.baseUrl)}:secondary:${sectionKey}:${directory}`, 60 * 60 * 1000, async () => {
    const res = await fetch(url, { headers: { Accept: 'application/json' } });
    if (!res.ok) throw new Error(`Plex error ${res.status}`);
    return res.json();
  });
}

// Generic directory fetch: GET a Plex path under /library (or /library/metadata/.../similar etc.)
export async function plexDir(cfg: PlexConfig, path: string, qs?: string) {
  const p = path.startsWith('/') ? path : `/${path}`;
  const url = `${cfg.baseUrl}${p}${p.includes('?') ? '&' : (qs ? (qs.startsWith('?') ? '' : '?') : '?')}X-Plex-Token=${cfg.token}${qs ? `${p.includes('?')?'&':''}${qs.replace(/^\?/, '')}` : ''}`;
  return cached(`plex:${encodeURIComponent(cfg.baseUrl)}:dir:${p}:${qs || ''}`, 10 * 60 * 1000, async () => {
    const res = await fetch(url, { headers: { Accept: 'application/json' } });
    if (!res.ok) throw new Error(`Plex error ${res.status}`);
    return res.json();
  });
}

export async function plexMetadata(cfg: PlexConfig, ratingKey: string) {
  const url = `${cfg.baseUrl}/library/metadata/${ratingKey}?X-Plex-Token=${cfg.token}`;
  return cached(`plex:${encodeURIComponent(cfg.baseUrl)}:meta:${ratingKey}`, 24 * 60 * 60 * 1000, async () => {
    const res = await fetch(url, { headers: { Accept: 'application/json' } });
    if (!res.ok) throw new Error(`Plex error ${res.status}`);
    return res.json();
  });
}

// Fetch metadata with extras/external media included to access trailers
export async function plexMetadataWithExtras(cfg: PlexConfig, ratingKey: string) {
  const url = `${cfg.baseUrl}/library/metadata/${ratingKey}?includeExtras=1&includeExternalMedia=1&includeChildren=1&X-Plex-Token=${cfg.token}`;
  return cached(`plex:${encodeURIComponent(cfg.baseUrl)}:meta_extras:${ratingKey}`, 6 * 60 * 60 * 1000, async () => {
    const res = await fetch(url, { headers: { Accept: 'application/json' } });
    if (!res.ok) throw new Error(`Plex error ${res.status}`);
    return res.json();
  });
}

// Build a full URL to a Plex part key (e.g., Extras Media Part key)
export function plexPartUrl(baseUrl: string, token: string, partKey: string) {
  // partKey may already have query params; append token accordingly
  const sep = partKey.includes('?') ? '&' : '?';
  const base = baseUrl.replace(/\/$/, '');
  // Ensure partKey begins with '/'
  const key = partKey.startsWith('/') ? partKey : `/${partKey}`;
  return `${base}${key}${sep}X-Plex-Token=${token}`;
}

export async function plexCollections(cfg: PlexConfig, libraryKey: string) {
  const url = `${cfg.baseUrl}/library/sections/${libraryKey}/collections?X-Plex-Token=${cfg.token}`;
  return cached(`plex:${encodeURIComponent(cfg.baseUrl)}:collections:${libraryKey}`, 30 * 60 * 1000, async () => {
    const res = await fetch(url, { headers: { Accept: 'application/json' } });
    if (!res.ok) throw new Error(`Plex error ${res.status}`);
    return res.json();
  });
}

export async function plexSearch(cfg: PlexConfig, query: string, typeNum: 1|2 = 1) {
  const url = `${cfg.baseUrl}/search?type=${typeNum}&query=${encodeURIComponent(query)}&X-Plex-Token=${cfg.token}`;
  return cached(`plex:${encodeURIComponent(cfg.baseUrl)}:search:${typeNum}:${query}`, 10 * 60 * 1000, async () => {
    const res = await fetch(url, { headers: { Accept: 'application/json' } });
    if (!res.ok) throw new Error(`Plex error ${res.status}`);
    return res.json();
  });
}

export async function plexChildren(cfg: PlexConfig, ratingKey: string) {
  const url = `${cfg.baseUrl}/library/metadata/${ratingKey}/children?X-Plex-Token=${cfg.token}`;
  return cached(`plex:${encodeURIComponent(cfg.baseUrl)}:children:${ratingKey}`, 10 * 60 * 1000, async () => {
    const res = await fetch(url, { headers: { Accept: 'application/json' } });
    if (!res.ok) throw new Error(`Plex error ${res.status}`);
    return res.json();
  });
}

// Comprehensive search that searches by multiple GUIDs
export async function plexComprehensiveGuidSearch(cfg: PlexConfig, guids: string[], typeNum?: 1|2) {
  return cached(`plex:${encodeURIComponent(cfg.baseUrl)}:guidsearch:${guids.join(',')}:${typeNum ?? 0}`, 30 * 60 * 1000, async () => {
    const allMatches: any[] = [];
    const seenKeys = new Set<string>();

    // Try each GUID
    for (const guid of guids) {
      try {
        const result = await plexFindByGuid({ baseUrl: cfg.baseUrl, token: cfg.token }, guid, typeNum);
        const items = result?.MediaContainer?.Metadata || [];

        // Add unique items only
        for (const item of items) {
          if (!seenKeys.has(item.ratingKey)) {
            seenKeys.add(item.ratingKey);
            allMatches.push(item);
          }
        }
      } catch {}
    }

    return { MediaContainer: { Metadata: allMatches } };
  });
}

export async function plexFindByGuid(cfg: PlexConfig, guid: string, typeNum?: 1|2) {
  return plexBackendFindByGuid(guid, typeNum);
}

// Player-specific Plex API methods
// ---- Begin exact player helpers (from 147b572) ----

function getClientId(): string {
  try {
    let clientId = localStorage.getItem('plex_client_id');
    if (!clientId) {
      clientId = Math.random().toString(36).substring(2, 15) + Math.random().toString(36).substring(2, 15);
      localStorage.setItem('plex_client_id', clientId);
    }
    return clientId;
  } catch {
    return Math.random().toString(36).substring(2, 15);
  }
}

function getSessionId(): string {
  try {
    let sessionId = sessionStorage.getItem('plex_session_id');
    if (!sessionId) {
      sessionId = Math.random().toString(36).substring(2, 15);
      sessionStorage.setItem('plex_session_id', sessionId);
    }
    return sessionId;
  } catch {
    return Math.random().toString(36).substring(2, 15);
  }
}

function getBrowserName(): string {
  const userAgent = navigator.userAgent;
  if (userAgent.includes('Chrome')) return 'Chrome';
  if (userAgent.includes('Safari')) return 'Safari';
  if (userAgent.includes('Firefox')) return 'Firefox';
  if (userAgent.includes('Opera')) return 'Opera';
  return 'Unknown';
}

function getClientProfile(): string {
  const profiles = [] as string[];
  profiles.push('add-limitation(scope=videoCodec&scopeName=hevc&type=upperBound&name=video.width&value=4096&replace=true)');
  profiles.push('add-limitation(scope=videoCodec&scopeName=hevc&type=upperBound&name=video.height&value=2160&replace=true)');
  profiles.push('add-limitation(scope=videoCodec&scopeName=hevc&type=upperBound&name=video.bitDepth&value=10&replace=true)');
  profiles.push('append-transcode-target-codec(type=videoProfile&context=streaming&protocol=dash&videoCodec=h264)');
  profiles.push('append-transcode-target-codec(type=videoProfile&context=streaming&protocol=hls&videoCodec=h264)');
  profiles.push('append-transcode-target-codec(type=videoProfile&context=streaming&videoCodec=h264,hevc&audioCodec=aac&protocol=dash)');
  profiles.push('add-limitation(scope=videoTranscodeTarget&scopeName=hevc&scopeType=videoCodec&context=streaming&protocol=dash&type=match&name=video.colorTrc&list=bt709|bt470m|bt470bg|smpte170m|smpte240m|bt2020-10|smpte2084&isRequired=false)');
  return profiles.join('+');
}

export function getXPlexHeaders(token: string) {
  return {
    'X-Plex-Product': 'Flixor',
    'X-Plex-Version': '1.0.0',
    'X-Plex-Client-Identifier': getClientId(),
    'X-Plex-Platform': 'Web',
    'X-Plex-Platform-Version': getBrowserName(),
    'X-Plex-Features': 'external-media,indirect-media,hub-style-list',
    'X-Plex-Model': 'bundled',
    'X-Plex-Device': getBrowserName(),
    'X-Plex-Device-Name': 'Plex MPV Web',
    'X-Plex-Device-Screen-Resolution': `${window.screen.width}x${window.screen.height}`,
    'X-Plex-Token': token,
    'X-Plex-Language': 'en',
    'X-Plex-Session-Id': getSessionId(),
    'X-Plex-Session-Identifier': getSessionId(),
    'X-Plex-Client-Profile-Extra': getClientProfile(),
  } as Record<string, string>;
}

export function getStreamProps(itemId: string, options?: {
  maxVideoBitrate?: number;
  autoAdjustQuality?: boolean;
  protocol?: 'dash' | 'hls';
  directPlay?: boolean;
  directStream?: boolean;
  audioStreamID?: string;
  subtitleStreamID?: string;
  subtitleMode?: 'burn' | 'embed' | 'none';
}) {
  const sessionId = getSessionId();
  const props: any = {
    hasMDE: 1,
    path: `/library/metadata/${itemId}`,
    mediaIndex: 0,
    partIndex: 0,
    protocol: options?.protocol || 'hls',
    fastSeek: 1,
    directPlay: options?.directPlay === true ? 1 : 0,
    directStream: options?.directStream === true ? 1 : 0,
    directStreamAudio: 0,
    subtitleSize: 100,
    audioBoost: 100,
    location: 'lan',
    addDebugOverlay: 0,
    autoAdjustQuality: options?.autoAdjustQuality ? 1 : 0,
    mediaBufferSize: 102400,
    'Accept-Language': 'en',
    session: sessionId,
    'X-Plex-Incomplete-Segments': 1,
  };
  if (options?.subtitleStreamID !== undefined) {
    if (options.subtitleStreamID === '0' || options.subtitleStreamID === '-1') {
      props.subtitles = 'none';
    } else {
      props.subtitleStreamID = options.subtitleStreamID;
      props.subtitles = options.subtitleMode || 'burn';
    }
  } else {
    props.subtitles = 'burn';
  }
  if (options?.audioStreamID) props.audioStreamID = options.audioStreamID;
  if (options?.maxVideoBitrate !== undefined && options.maxVideoBitrate > 0) {
    props.maxVideoBitrate = options.maxVideoBitrate;
  }
  return props;
}

export async function plexUniversalDecision(cfg: PlexConfig, itemId: string, options?: {
  maxVideoBitrate?: number;
  autoAdjustQuality?: boolean;
  protocol?: 'dash' | 'hls';
  directPlay?: boolean;
  directStream?: boolean;
  audioStreamID?: string;
  subtitleStreamID?: string;
}) {
  const props = getStreamProps(itemId, { ...options, protocol: options?.protocol || 'hls' });
  const headers = getXPlexHeaders(cfg.token);
  const params = new URLSearchParams();
  Object.entries(props).forEach(([k, v]) => params.set(k, String(v)));
  Object.entries(headers).forEach(([k, v]) => params.set(k, String(v)));
  const url = `${cfg.baseUrl}/video/:/transcode/universal/decision?${params}`;
  try {
    const response = await fetch(url, { method: 'GET', headers: { 'Accept': 'application/json', 'X-Plex-Token': cfg.token } });
    const data = await response.json();
    const c = data.MediaContainer;
    const decision = {
      directPlayDecisionCode: c.directPlayDecisionCode,
      directPlayDecisionText: c.directPlayDecisionText,
      transcodeDecisionCode: c.transcodeDecisionCode,
      transcodeDecisionText: c.transcodeDecisionText,
      generalDecisionCode: c.generalDecisionCode,
      generalDecisionText: c.generalDecisionText,
      videoDecision: c.Metadata?.[0]?.Media?.[0]?.Part?.[0]?.Stream?.[0]?.decision,
      audioDecision: c.Metadata?.[0]?.Media?.[0]?.Part?.[0]?.Stream?.[1]?.decision,
    } as any;
    decision.canDirectPlay = decision.directPlayDecisionCode === 1000;
    decision.willTranscode = decision.videoDecision === 'transcode';
    decision.willDirectStream = decision.videoDecision === 'copy';
    decision.streamUrl = c.Metadata?.[0]?.Media?.[0]?.Part?.[0]?.key;
    return decision;
  } catch (e) {
    console.error('Failed to get Plex decision:', e);
    return { canDirectPlay: false, willTranscode: true, willDirectStream: false } as any;
  }
}

export function plexStreamUrl(cfg: PlexConfig, itemId: string, options?: { maxVideoBitrate?: number; protocol?: 'dash'|'hls'; autoAdjustQuality?: boolean; directPlay?: boolean; directStream?: boolean; audioStreamID?: string; subtitleStreamID?: string; forceReload?: boolean; }) {
  const props = getStreamProps(itemId, { ...options, protocol: options?.protocol || 'hls' });
  const headers = getXPlexHeaders(cfg.token);
  const params = new URLSearchParams();
  Object.entries(props).forEach(([k, v]) => params.set(k, String(v)));
  Object.entries(headers).forEach(([k, v]) => params.set(k, String(v)));
  if (options?.forceReload) params.set('_t', Date.now().toString());
  const ext = options?.protocol === 'hls' ? 'm3u8' : 'mpd';
  return `${cfg.baseUrl}/video/:/transcode/universal/start.${ext}?${params}`;
}

export async function plexTimelineUpdate(cfg: PlexConfig, itemId: string, time: number, duration: number, state: 'playing'|'paused'|'stopped'|'buffering') {
  const headers = getXPlexHeaders(cfg.token);
  const params = new URLSearchParams({
    ratingKey: itemId,
    key: `/library/metadata/${itemId}`,
    playbackTime: Math.floor(time).toString(),
    time: Math.floor(time).toString(),
    duration: Math.floor(duration).toString(),
    state,
    context: 'library',
    ...headers,
  });
  const url = `${cfg.baseUrl}/:/timeline?${params}`;
  const res = await fetch(url, { headers: { 'Accept': 'application/json' } });
  if (!res.ok) console.warn('Timeline update failed:', res.status);
  return res;
}

// Utilities moved from plex_player to consolidate
export function plexTranscodeImageUrl(cfg: PlexConfig, path: string, width: number, height: number) {
  const params = new URLSearchParams({
    width: String(width),
    height: String(height),
    minSize: '1',
    upscale: '1',
    'X-Plex-Token': cfg.token,
  });
  return `${cfg.baseUrl}/photo/:/transcode?${params}&url=${encodeURIComponent(path)}`;
}

function getPlexSessionId(): string {
  try {
    let sid = sessionStorage.getItem('plex_session_id');
    if (!sid) { sid = Math.random().toString(36).substring(2, 15); sessionStorage.setItem('plex_session_id', sid); }
    return sid;
  } catch {
    return Math.random().toString(36).substring(2, 15);
  }
}

export async function plexStopTranscodeSession(cfg: PlexConfig, sessionKey?: string) {
  const params = new URLSearchParams({
    session: sessionKey || getPlexSessionId(),
    'X-Plex-Token': cfg.token,
  });
  const url = `${cfg.baseUrl}/video/:/transcode/universal/stop?${params}`;
  try {
    const res = await fetch(url, { method: 'GET', headers: { 'Accept': 'application/json' } });
    if (!res.ok) console.warn('Failed to stop transcode session:', res.status);
    return res;
  } catch (e) {
    console.error('Error stopping transcode session:', e);
  }
}

export async function plexKillAllTranscodeSessions(cfg: PlexConfig) {
  try { await plexStopTranscodeSession(cfg); } catch (e) { console.error('Error killing transcodes:', e); }
}

export async function plexPing(cfg: PlexConfig) {
  const url = `${cfg.baseUrl}/:/ping?X-Plex-Token=${cfg.token}`;
  const res = await fetch(url);
  return res.ok;
}

export async function plexUpdateAudioStream(cfg: PlexConfig, partId: string, streamId: string) {
  const params = new URLSearchParams({
    audioStreamID: streamId,
    allParts: '1',
    'X-Plex-Token': cfg.token,
  });

  const url = `${cfg.baseUrl}/library/parts/${partId}?${params}`;
  const res = await fetch(url, { method: 'PUT' });
  if (!res.ok) throw new Error(`Failed to update audio stream: ${res.status}`);
  return res;
}

export async function plexUpdateSubtitleStream(cfg: PlexConfig, partId: string, streamId: string) {
  const params = new URLSearchParams({
    subtitleStreamID: streamId,
    allParts: '1',
    'X-Plex-Token': cfg.token,
  });

  const url = `${cfg.baseUrl}/library/parts/${partId}?${params}`;
  const res = await fetch(url, { method: 'PUT' });
  if (!res.ok) throw new Error(`Failed to update subtitle stream: ${res.status}`);
  return res;
}

export async function plexPlayQueue(cfg: PlexConfig, itemId: string) {
  const params = new URLSearchParams({
    type: 'video',
    uri: `server://*/com.plexapp.plugins.library/library/metadata/${itemId}`,
    includeChapters: '1',
    includeMarkers: '1',
    includeRelated: '1',
    'X-Plex-Token': cfg.token,
  });

  const url = `${cfg.baseUrl}/playQueues?${params}`;
  const res = await fetch(url, { method: 'POST', headers: { Accept: 'application/json' } });
  if (!res.ok) throw new Error(`Failed to create play queue: ${res.status}`);
  return res.json();
}

// Recently added across libraries (web convenience)
export async function plexRecentlyAdded(days: number = 7, limitPerLib: number = 50): Promise<any[]> {
  try {
    const s = loadSettings();
    if (!s.plexBaseUrl || !s.plexToken) return [];
    const cfg = { baseUrl: s.plexBaseUrl!, token: s.plexToken! };
    const libs: any = await plexBackendLibraries();
    const dirs = libs?.MediaContainer?.Directory || [];
    const since = Date.now() - days * 24 * 60 * 60 * 1000;
    const all: any[] = [];
    for (const d of dirs) {
      if (d.type !== 'movie' && d.type !== 'show') continue;
      try {
        const res: any = await plexBackendLibraryAll(String(d.key), { type: d.type === 'movie' ? 1 : 2, sort: 'addedAt:desc', offset: 0, limit: limitPerLib });
        const meta: any[] = res?.MediaContainer?.Metadata || [];
        for (const m of meta) {
          const added = (m.addedAt ? (Number(m.addedAt) * 1000) : 0);
          if (!added || added >= since) all.push(m);
        }
      } catch {}
    }
    // Sort globally by addedAt desc and cap
    all.sort((a:any,b:any)=> (b.addedAt||0) - (a.addedAt||0));
    return all.slice(0, 100);
  } catch {
    return [];
  }
}

// Popular on Plex across libraries
export async function plexPopular(limitPerLib: number = 50): Promise<any[]> {
  try {
    const s = loadSettings();
    if (!s.plexBaseUrl || !s.plexToken) return [];
    const cfg = { baseUrl: s.plexBaseUrl!, token: s.plexToken! };
    const libs: any = await plexBackendLibraries();
    const dirs = libs?.MediaContainer?.Directory || [];
    const all: any[] = [];
    for (const d of dirs) {
      if (d.type !== 'movie' && d.type !== 'show') continue;
      let res: any = null;
      // Try lastViewedAt first, then viewCount
      try {
        res = await plexBackendLibraryAll(String(d.key), { type: d.type === 'movie' ? 1 : 2, sort: 'lastViewedAt:desc', offset: 0, limit: limitPerLib });
      } catch {}
      if (!res) {
        try {
          res = await plexBackendLibraryAll(String(d.key), { type: d.type === 'movie' ? 1 : 2, sort: 'viewCount:desc', offset: 0, limit: limitPerLib });
        } catch {}
      }
      const meta: any[] = res?.MediaContainer?.Metadata || [];
      all.push(...meta);
    }
    // Prefer items with lastViewedAt/viewCount and recent activity
    const score = (m:any) => {
      const lv = (m.lastViewedAt||0);
      const vc = (m.viewCount||0);
      return (lv * 10) + vc;
    };
    all.sort((a:any,b:any)=> score(b) - score(a));
    return all.slice(0, 100);
  } catch {
    return [];
  }
}
