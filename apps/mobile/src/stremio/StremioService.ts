import { appLogger } from '../core/AppLogger';
import {
  normalizeManifestUrl,
  readAddonOrder,
  readInstalledAddons,
  readRemovedDefaultAddons,
  STREMIO_DEFAULT_OPEN_SUBTITLES_ID,
  STREMIO_DEFAULT_OPEN_SUBTITLES_URL,
  writeAddonOrder,
  writeInstalledAddons,
  writeRemovedDefaultAddons,
} from './StremioStorage';
import type {
  StremioAddonManifest,
  StremioAddonStreamResult,
  StremioContentIdentity,
  StremioMetaDetail,
  StremioMetaVideo,
  StremioPlayableStream,
  StremioRequestType,
  StremioResource,
  StremioResourceObject,
  StremioSourceType,
  StremioSubtitleCandidate,
} from './types';

type AddonResponse<T> = {
  data?: T;
  error?: string;
};

type StreamPayload = {
  streams?: any[];
};

type SubtitlePayload = {
  subtitles?: any[];
};

type MetaPayload = {
  meta?: any;
};

function toErrorDetails(error: unknown): { name?: string; message: string; stack?: string } {
  if (error instanceof Error) {
    return {
      name: error.name,
      message: error.message,
      stack: error.stack,
    };
  }

  return {
    message: typeof error === 'string' ? error : String(error),
  };
}

function generateInstallationId(addonId: string): string {
  return `${addonId}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

function coerceResource(resource: StremioResource): StremioResourceObject | null {
  if (typeof resource === 'string') {
    return { name: resource };
  }
  if (resource && typeof resource === 'object' && resource.name) {
    return resource;
  }
  return null;
}

function sanitizeBaseUrl(url: string): { baseUrl: string; queryString?: string } {
  const [baseUrl, queryString] = url.split('?');
  const normalized = baseUrl.replace(/manifest\.json$/i, '').replace(/\/$/, '');
  return { baseUrl: normalized, queryString };
}

function buildResourceUrl(addonUrl: string, resourcePath: string): string {
  const { baseUrl, queryString } = sanitizeBaseUrl(addonUrl);
  return queryString ? `${baseUrl}${resourcePath}?${queryString}` : `${baseUrl}${resourcePath}`;
}

function addonSupportsResource(
  addon: StremioAddonManifest,
  resourceName: string,
  requestType: StremioRequestType,
  contentId?: string
): boolean {
  const resources = addon.resources || [];
  let matchedResource: StremioResourceObject | null = null;

  for (const resource of resources) {
    const normalized = coerceResource(resource);
    if (!normalized || normalized.name !== resourceName) {
      continue;
    }

    const supportedTypes = normalized.types || addon.types || [];
    if (supportedTypes.length > 0 && !supportedTypes.includes(requestType)) {
      continue;
    }

    matchedResource = normalized;
    break;
  }

  if (!matchedResource) {
    return false;
  }

  const idPrefixes = matchedResource.idPrefixes || addon.idPrefixes || [];
  if (!contentId || idPrefixes.length === 0) {
    return true;
  }

  return idPrefixes.some((prefix) => contentId.startsWith(prefix));
}

function detectSourceType(stream: any): StremioSourceType {
  if (typeof stream?.url === 'string') return 'url';
  if (stream?.externalUrl) return 'externalUrl';
  if (stream?.ytId) return 'ytId';
  if (stream?.infoHash) return 'infoHash';
  if (stream?.nzbUrl) return 'nzbUrl';
  if (
    (Array.isArray(stream?.rarUrls) && stream.rarUrls.length > 0) ||
    (Array.isArray(stream?.zipUrls) && stream.zipUrls.length > 0) ||
    (Array.isArray(stream?.['7zipUrls']) && stream['7zipUrls'].length > 0) ||
    (Array.isArray(stream?.tgzUrls) && stream.tgzUrls.length > 0) ||
    (Array.isArray(stream?.tarUrls) && stream.tarUrls.length > 0)
  ) {
    return 'archive';
  }
  return 'unknown';
}

function getUnsupportedReason(sourceType: StremioSourceType): string | undefined {
  switch (sourceType) {
    case 'externalUrl':
      return 'Opens externally';
    case 'ytId':
      return 'YouTube playback is not supported in-app';
    case 'infoHash':
      return 'Torrent playback is not supported in-app';
    case 'nzbUrl':
      return 'NZB playback is not supported in-app';
    case 'archive':
      return 'Archive streams are not supported in-app';
    case 'unknown':
      return 'Unsupported stream type';
    default:
      return undefined;
  }
}

function normalizeStream(
  addon: StremioAddonManifest,
  stream: any,
  streamIndex: number
): StremioPlayableStream | null {
  const sourceType = detectSourceType(stream);
  const playableUrl = typeof stream?.url === 'string' ? stream.url : undefined;
  const playable = sourceType === 'url' && /^https?:\/\//i.test(playableUrl || '');

  if (!playable && sourceType === 'url' && playableUrl) {
    return {
      addonId: addon.id,
      addonName: addon.name,
      addonInstallationId: addon.installationId,
      url: playableUrl,
      name: stream.name,
      title: stream.title,
      description: stream.description,
      size: stream.behaviorHints?.videoSize || stream.size,
      quality: stream.quality,
      headers: stream.headers,
      subtitles: Array.isArray(stream.subtitles)
        ? stream.subtitles.map((subtitle: any, index: number) => ({
            id: subtitle.id || `${addon.id}-${index}`,
            url: subtitle.url,
            lang: subtitle.lang || subtitle.language || 'unknown',
            format: subtitle.format,
            addonId: addon.id,
            addonName: addon.name,
          }))
        : undefined,
      behaviorHints: stream.behaviorHints,
      streamIndex,
      sourceType,
      playable: false,
      disabledReason: 'Only HTTP(S) direct streams are supported in-app',
    };
  }

  if (sourceType === 'unknown') {
    return null;
  }

  return {
    addonId: addon.id,
    addonName: addon.name,
    addonInstallationId: addon.installationId,
    url: playableUrl,
    externalUrl: stream.externalUrl,
    ytId: stream.ytId,
    infoHash: stream.infoHash,
    nzbUrl: stream.nzbUrl,
    rarUrls: stream.rarUrls,
    zipUrls: stream.zipUrls,
    '7zipUrls': stream['7zipUrls'],
    tgzUrls: stream.tgzUrls,
    tarUrls: stream.tarUrls,
    fileIdx: stream.fileIdx,
    fileMustInclude: stream.fileMustInclude,
    servers: stream.servers,
    name: stream.name,
    title: stream.title || stream.description || stream.name,
    description: stream.description,
    size: stream.behaviorHints?.videoSize || stream.size,
    isFree: stream.isFree,
    isDebrid: Boolean(stream.behaviorHints?.cached),
    quality: stream.quality,
    headers: stream.headers,
    subtitles: Array.isArray(stream.subtitles)
      ? stream.subtitles.map((subtitle: any, index: number) => ({
          id: subtitle.id || `${addon.id}-${index}`,
          url: subtitle.url,
          lang: subtitle.lang || subtitle.language || 'unknown',
          format: subtitle.format,
          addonId: addon.id,
          addonName: addon.name,
        }))
      : undefined,
    sources: stream.sources,
    behaviorHints: stream.behaviorHints,
    streamIndex,
    sourceType,
    playable,
    disabledReason: playable ? undefined : getUnsupportedReason(sourceType),
  };
}

async function fetchJson<T>(
  url: string,
  timeoutMs: number = 10000,
  externalSignal?: AbortSignal
): Promise<AddonResponse<T>> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  const abortFromCaller = () => controller.abort();
  if (externalSignal?.aborted) {
    controller.abort();
  } else {
    externalSignal?.addEventListener('abort', abortFromCaller);
  }

  try {
    const response = await fetch(url, {
      method: 'GET',
      headers: {
        Accept: 'application/json',
      },
      signal: controller.signal,
    });

    if (!response.ok) {
      const responseText = await response.text().catch(() => '');
      const responseSummary = responseText.trim().slice(0, 240);
      return {
        error: responseSummary
          ? `HTTP ${response.status} ${response.statusText} from ${url}: ${responseSummary}`
          : `HTTP ${response.status} ${response.statusText} from ${url}`,
      };
    }

    const responseText = await response.text();
    try {
      return { data: JSON.parse(responseText) as T };
    } catch (parseError: any) {
      const responseSummary = responseText.trim().slice(0, 240);
      return {
        error: responseSummary
          ? `Invalid JSON from ${url}: ${responseSummary}`
          : `Invalid JSON from ${url}: ${parseError?.message || 'Could not parse response'}`,
      };
    }
  } catch (error: any) {
    if (error?.name === 'AbortError') {
      return { error: `Request timed out after ${Math.floor(timeoutMs / 1000)}s while fetching ${url}` };
    }
    if (error instanceof TypeError) {
      return { error: `Network request failed for ${url}: ${error.message}` };
    }
    return { error: `${error?.message || 'Request failed'} (${url})` };
  } finally {
    clearTimeout(timer);
    externalSignal?.removeEventListener('abort', abortFromCaller);
  }
}

function parseMetaVideo(raw: any): StremioMetaVideo | null {
  if (!raw || typeof raw !== 'object') {
    return null;
  }
  const season = Number(raw.season);
  const episode = Number(raw.episode ?? raw.number);
  return {
    id: raw.id,
    title: raw.name || raw.title,
    season: Number.isFinite(season) ? season : undefined,
    episode: Number.isFinite(episode) ? episode : undefined,
    released: raw.released || raw.firstAired,
    overview: raw.overview || raw.description,
    thumbnail: raw.thumbnail,
  };
}

class StremioService {
  private addons = new Map<string, StremioAddonManifest>();
  private order: string[] = [];
  private initialized = false;
  private initPromise: Promise<void> | null = null;

  private async initialize(installDefaults: boolean): Promise<void> {
    const [storedAddons, storedOrder] = await Promise.all([readInstalledAddons(), readAddonOrder()]);

    this.addons = new Map(storedAddons.map((addon) => [addon.installationId, addon]));
    this.order = storedOrder.filter((installationId) => this.addons.has(installationId));

    for (const addon of storedAddons) {
      if (!this.order.includes(addon.installationId)) {
        this.order.push(addon.installationId);
      }
    }

    if (installDefaults) {
      await this.ensureDefaultAddons();
    } else {
      await this.persist();
    }

    this.initialized = true;
  }

  private async ensureReady(installDefaults: boolean = false): Promise<void> {
    if (!this.initialized) {
      if (!this.initPromise) {
        this.initPromise = this.initialize(installDefaults).finally(() => {
          this.initPromise = null;
        });
      }
      await this.initPromise;
      return;
    }

    if (installDefaults) {
      await this.ensureDefaultAddons();
    }
  }

  async ensureInitialized(options?: { installDefaults?: boolean }): Promise<void> {
    await this.ensureReady(Boolean(options?.installDefaults));
  }

  private async ensureDefaultAddons(): Promise<void> {
    const removedDefaults = await readRemovedDefaultAddons();
    if (removedDefaults.includes(STREMIO_DEFAULT_OPEN_SUBTITLES_ID)) {
      await this.persist();
      return;
    }

    const hasOpenSubtitles = Array.from(this.addons.values()).some(
      (addon) => addon.id === STREMIO_DEFAULT_OPEN_SUBTITLES_ID
    );
    if (hasOpenSubtitles) {
      await this.persist();
      return;
    }

    try {
      await this.installAddon(STREMIO_DEFAULT_OPEN_SUBTITLES_URL, { suppressRemovedDefaultCleanup: true });
    } catch (error) {
      appLogger.warn('[Stremio] Failed to install default OpenSubtitles addon', {
        manifestUrl: STREMIO_DEFAULT_OPEN_SUBTITLES_URL,
        ...toErrorDetails(error),
      });
    }
  }

  private async persist(): Promise<void> {
    const ordered = this.order
      .map((installationId) => this.addons.get(installationId))
      .filter(Boolean) as StremioAddonManifest[];

    const trailing = Array.from(this.addons.values()).filter(
      (addon) => !this.order.includes(addon.installationId)
    );

    const nextAddons = [...ordered, ...trailing];
    const nextOrder = nextAddons.map((addon) => addon.installationId);
    this.order = nextOrder;

    await Promise.all([writeInstalledAddons(nextAddons), writeAddonOrder(nextOrder)]);
  }

  async getManifest(url: string): Promise<StremioAddonManifest> {
    const manifestUrl = normalizeManifestUrl(url);
    if (!manifestUrl) {
      throw new Error('Manifest URL is required');
    }

    const response = await fetchJson<any>(manifestUrl, 60000);
    if (!response.data) {
      throw new Error(response.error || 'Failed to fetch addon manifest');
    }

    const manifest = response.data;
    return {
      ...manifest,
      id: manifest.id || manifestUrl.replace(/[^a-z0-9]+/gi, '-').toLowerCase(),
      installationId: generateInstallationId(manifest.id || 'addon'),
      url: manifestUrl.replace(/\/manifest\.json$/i, ''),
      originalUrl: manifestUrl,
      transportUrl: manifestUrl,
    };
  }

  async getInstalledAddons(): Promise<StremioAddonManifest[]> {
    await this.ensureReady();
    return this.order
      .map((installationId) => this.addons.get(installationId))
      .filter(Boolean) as StremioAddonManifest[];
  }

  private addonProvidesStreams(addon: StremioAddonManifest): boolean {
    return addonSupportsResource(addon, 'stream', 'movie') || addonSupportsResource(addon, 'stream', 'series');
  }

  private addonProvidesSubtitles(addon: StremioAddonManifest): boolean {
    return addonSupportsResource(addon, 'subtitles', 'movie') || addonSupportsResource(addon, 'subtitles', 'series');
  }

  async hasStreamProviders(requestType?: StremioRequestType): Promise<boolean> {
    const addons = await this.getInstalledAddons();
    return addons.some((addon) =>
      requestType
        ? addonSupportsResource(addon, 'stream', requestType)
        : this.addonProvidesStreams(addon)
    );
  }

  async installAddon(
    url: string,
    options?: { suppressRemovedDefaultCleanup?: boolean }
  ): Promise<StremioAddonManifest> {
    await this.ensureReady();

    const manifestUrl = normalizeManifestUrl(url);

    try {
      const manifest = await this.getManifest(url);
      const existingInstallations = Array.from(this.addons.values()).filter((addon) => addon.id === manifest.id);

      if (existingInstallations.length > 0 && !this.addonProvidesStreams(manifest)) {
        throw new Error('This addon is already installed. Multiple installs are only allowed for stream providers.');
      }

      this.addons.set(manifest.installationId, manifest);
      if (!this.order.includes(manifest.installationId)) {
        this.order.push(manifest.installationId);
      }

      if (!options?.suppressRemovedDefaultCleanup) {
        const removedDefaults = await readRemovedDefaultAddons();
        if (removedDefaults.includes(manifest.id)) {
          await writeRemovedDefaultAddons(removedDefaults.filter((addonId) => addonId !== manifest.id));
        }
      }

      await this.persist();
      appLogger.info('[Stremio] Installed addon', {
        id: manifest.id,
        installationId: manifest.installationId,
        name: manifest.name,
        manifestUrl: manifest.originalUrl,
      });
      return manifest;
    } catch (error) {
      const errorDetails = toErrorDetails(error);
      appLogger.error('[Stremio] Failed to install addon', {
        manifestUrl: manifestUrl || url,
        ...errorDetails,
      });
      throw new Error(errorDetails.message);
    }
  }

  async removeAddon(installationId: string): Promise<void> {
    await this.ensureReady();
    const addon = this.addons.get(installationId);
    if (!addon) {
      return;
    }

    this.addons.delete(installationId);
    this.order = this.order.filter((id) => id !== installationId);

    const sameAddonRemaining = Array.from(this.addons.values()).some((item) => item.id === addon.id);
    if (!sameAddonRemaining && addon.id === STREMIO_DEFAULT_OPEN_SUBTITLES_ID) {
      const removedDefaults = await readRemovedDefaultAddons();
      if (!removedDefaults.includes(addon.id)) {
        removedDefaults.push(addon.id);
        await writeRemovedDefaultAddons(removedDefaults);
      }
    }

    await this.persist();
    appLogger.info('[Stremio] Removed addon', {
      id: addon.id,
      installationId,
      name: addon.name,
    });
  }

  async moveAddonUp(installationId: string): Promise<boolean> {
    await this.ensureReady();
    const index = this.order.indexOf(installationId);
    if (index <= 0) {
      return false;
    }
    [this.order[index - 1], this.order[index]] = [this.order[index], this.order[index - 1]];
    await this.persist();
    return true;
  }

  async moveAddonDown(installationId: string): Promise<boolean> {
    await this.ensureReady();
    const index = this.order.indexOf(installationId);
    if (index < 0 || index >= this.order.length - 1) {
      return false;
    }
    [this.order[index], this.order[index + 1]] = [this.order[index + 1], this.order[index]];
    await this.persist();
    return true;
  }

  getAddonConfigureUrl(addon: StremioAddonManifest): string | null {
    if (addon.behaviorHints?.configurationURL) {
      return addon.behaviorHints.configurationURL;
    }

    const sourceUrl = addon.transportUrl || addon.originalUrl || addon.url;
    if (!sourceUrl) {
      return null;
    }

    const normalized = normalizeManifestUrl(sourceUrl);
    if (!normalized) {
      return null;
    }

    return normalized.replace(/manifest\.json$/i, 'configure');
  }

  async canResolveId(requestType: StremioRequestType, contentId: string): Promise<boolean> {
    const addons = await this.getInstalledAddons();
    const streamAddons = addons.filter((addon) =>
      addonSupportsResource(addon, 'stream', requestType, contentId)
    );
    if (streamAddons.length > 0) {
      return true;
    }

    const unconstrainedStreamAddons = addons.filter((addon) => {
      if (!addonSupportsResource(addon, 'stream', requestType)) {
        return false;
      }

      const resources = addon.resources || [];
      return resources.some((resource) => {
        const normalized = coerceResource(resource);
        if (!normalized || normalized.name !== 'stream') {
          return false;
        }
        const supportedTypes = normalized.types || addon.types || [];
        if (supportedTypes.length > 0 && !supportedTypes.includes(requestType)) {
          return false;
        }
        const idPrefixes = normalized.idPrefixes || addon.idPrefixes || [];
        return idPrefixes.length === 0;
      });
    });

    return unconstrainedStreamAddons.length > 0;
  }

  private streamAddonsFor(
    addons: StremioAddonManifest[],
    identity: StremioContentIdentity
  ): StremioAddonManifest[] {
    return addons.filter((addon) =>
      addonSupportsResource(addon, 'stream', identity.requestType, identity.requestId)
    );
  }

  private async fetchAddonStreams(
    addon: StremioAddonManifest,
    identity: StremioContentIdentity,
    signal?: AbortSignal
  ): Promise<StremioAddonStreamResult> {
    if (!addon.url) {
      return {
        addonId: addon.id,
        addonName: addon.name,
        installationId: addon.installationId,
        streams: [],
        error: 'Addon has no transport URL',
      };
    }

    const resourcePath = `/stream/${identity.requestType}/${encodeURIComponent(identity.requestId)}.json`;
    const requestUrl = buildResourceUrl(addon.url, resourcePath);
    appLogger.info('[Stremio] Fetching streams', {
      addonId: addon.id,
      installationId: addon.installationId,
      requestType: identity.requestType,
      requestId: identity.requestId,
    });

    const response = await fetchJson<StreamPayload>(requestUrl, 60000, signal);
    if (!response.data) {
      appLogger.warn('[Stremio] Stream request failed', {
        addonId: addon.id,
        installationId: addon.installationId,
        error: response.error,
      });
      return {
        addonId: addon.id,
        addonName: addon.name,
        installationId: addon.installationId,
        streams: [],
        error: response.error || 'Request failed',
      };
    }

    const processed = Array.isArray(response.data.streams)
      ? (response.data.streams
          .map((stream, index) => normalizeStream(addon, stream, index))
          .filter(Boolean) as StremioPlayableStream[])
      : [];

    return {
      addonId: addon.id,
      addonName: addon.name,
      installationId: addon.installationId,
      streams: processed,
    };
  }

  async getStreams(identity: StremioContentIdentity): Promise<StremioAddonStreamResult[]> {
    await this.ensureReady();
    const streamAddons = this.streamAddonsFor(await this.getInstalledAddons(), identity);
    if (streamAddons.length === 0) {
      return [];
    }
    return Promise.all(streamAddons.map((addon) => this.fetchAddonStreams(addon, identity)));
  }

  /**
   * Like `getStreams`, but stops as soon as `shouldStop` says so or the time limit
   * passes; addons that have not answered are left out and their requests aborted.
   * `shouldStop` gets the results so far in addon order and the installation ids still pending.
   */
  async getStreamsWithin(
    identity: StremioContentIdentity,
    options: {
      timeLimitMs: number;
      shouldStop?: (
        results: StremioAddonStreamResult[],
        pending: ReadonlySet<string>
      ) => boolean;
      /** Aborts the lookup early, resolving with what has arrived. */
      signal?: AbortSignal;
    }
  ): Promise<{ results: StremioAddonStreamResult[]; timedOut: boolean }> {
    await this.ensureReady();
    const addons = await this.getInstalledAddons();
    const streamAddons = this.streamAddonsFor(addons, identity);
    if (streamAddons.length === 0) {
      return { results: [], timedOut: false };
    }

    const order = addons.map((addon) => addon.installationId);
    const sorted = (items: StremioAddonStreamResult[]) =>
      [...items].sort(
        (left, right) => order.indexOf(left.installationId) - order.indexOf(right.installationId)
      );

    return new Promise((resolve) => {
      const controller = new AbortController();
      const results: StremioAddonStreamResult[] = [];
      const pending = new Set(streamAddons.map((addon) => addon.installationId));
      let settled = false;
      const onCallerAbort = () => finish(false);

      const finish = (timedOut: boolean) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        options.signal?.removeEventListener('abort', onCallerAbort);
        controller.abort();
        resolve({ results: sorted(results), timedOut });
      };

      const timer = setTimeout(() => finish(true), options.timeLimitMs);
      if (options.signal?.aborted) {
        finish(false);
        return;
      }
      options.signal?.addEventListener('abort', onCallerAbort);

      for (const addon of streamAddons) {
        this.fetchAddonStreams(addon, identity, controller.signal).then((result) => {
          if (settled) return;
          results.push(result);
          pending.delete(addon.installationId);
          if (pending.size === 0) {
            finish(false);
            return;
          }
          let stop = false;
          try {
            stop = options.shouldStop?.(sorted(results), pending) ?? false;
          } catch (error) {
            appLogger.warn('[Stremio] Early-stop check failed', toErrorDetails(error));
          }
          if (stop) {
            finish(false);
          }
        });
      }
    });
  }

  /** Full metadata for one title, from the first meta-capable addon that has it. */
  async getMeta(type: StremioRequestType, id: string): Promise<StremioMetaDetail | null> {
    const addons = await this.getInstalledAddons();
    for (const addon of addons) {
      if (!addon.url || !addonSupportsResource(addon, 'meta', type, id)) {
        continue;
      }
      const resourcePath = `/meta/${type}/${encodeURIComponent(id)}.json`;
      const response = await fetchJson<MetaPayload>(buildResourceUrl(addon.url, resourcePath), 20000);
      const meta = response.data?.meta;
      if (meta && typeof meta === 'object') {
        return {
          id: meta.id || id,
          name: meta.name,
          videos: Array.isArray(meta.videos)
            ? (meta.videos.map(parseMetaVideo).filter(Boolean) as StremioMetaVideo[])
            : undefined,
        };
      }
    }
    return null;
  }

  /**
   * @param options.deadlineMs Stop waiting on subtitle addons after this long and
   * return what has arrived, so a slow addon can't delay switching episodes.
   */
  async getSubtitles(
    identity: StremioContentIdentity,
    options?: { deadlineMs?: number }
  ): Promise<StremioSubtitleCandidate[]> {
    await this.ensureReady();
    const addons = await this.getInstalledAddons();
    const subtitleAddons = addons.filter((addon) =>
      addonSupportsResource(addon, 'subtitles', identity.requestType, identity.requestId)
    );

    if (subtitleAddons.length === 0) {
      return [];
    }

    const requestId =
      identity.requestType === 'series' && identity.seasonNumber && identity.episodeNumber
        ? `${identity.baseId}:${identity.seasonNumber}:${identity.episodeNumber}`
        : identity.requestId;

    const deduped = new Map<string, StremioSubtitleCandidate>();
    const controller = new AbortController();

    const lookups = Promise.all(
      subtitleAddons.map(async (addon) => {
        if (!addon.url) {
          return;
        }

        const resourcePath = `/subtitles/${identity.requestType}/${encodeURIComponent(requestId)}.json`;
        const response = await fetchJson<SubtitlePayload>(
          buildResourceUrl(addon.url, resourcePath),
          10000,
          controller.signal
        );
        if (!response.data?.subtitles || !Array.isArray(response.data.subtitles)) {
          return;
        }

        response.data.subtitles.forEach((subtitle: any, index: number) => {
          if (subtitle?.url && !deduped.has(subtitle.url)) {
            deduped.set(subtitle.url, {
              id: subtitle.id || `${addon.id}-${index}`,
              url: subtitle.url,
              lang: subtitle.lang || subtitle.language || 'unknown',
              format: subtitle.format,
              addonId: addon.id,
              addonName: addon.name,
            });
          }
        });
      })
    );

    if (options?.deadlineMs === undefined) {
      await lookups;
    } else {
      let timer: ReturnType<typeof setTimeout> | undefined;
      await Promise.race([
        lookups,
        new Promise<void>((resolve) => {
          timer = setTimeout(resolve, options.deadlineMs);
        }),
      ]);
      clearTimeout(timer);
      controller.abort();
    }
    return Array.from(deduped.values());
  }

  async getAddonSummary() {
    const addons = await this.getInstalledAddons();
    return addons.map((addon) => ({
      ...addon,
      streamCapable: this.addonProvidesStreams(addon),
      subtitleCapable: this.addonProvidesSubtitles(addon),
      configureUrl: this.getAddonConfigureUrl(addon),
    }));
  }
}

export const stremioService = new StremioService();

export const stremioUtils = {
  addonSupportsResource,
};
