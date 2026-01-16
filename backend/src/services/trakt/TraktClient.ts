import axios, { AxiosInstance } from 'axios';
import { AppDataSource } from '../../db/data-source';
import { UserSettings } from '../../db/entities';
import { encryptForUser, decryptForUser, isEncrypted } from '../../utils/crypto';

type TraktTokens = {
  access_token: string;
  token_type: string;
  expires_in: number;
  refresh_token: string;
  scope: string;
  created_at: number;
};

export class TraktClient {
  private axios: AxiosInstance;
  private clientId: string;
  private clientSecret: string;
  private userId?: string;

  constructor(userId?: string) {
    // Fallback to known client id/secret used by the frontend (for dev), if env not set
    this.clientId = process.env.TRAKT_CLIENT_ID || '4ab0ead6d5510bf39180a5e1dd7b452f5ad700b7794564befdd6bca56e0f7ce4';
    this.clientSecret = process.env.TRAKT_CLIENT_SECRET || '64d24f12e4628dcf0dda74a61f2235c086daaf8146384016b6a86c196e419c26';
    this.userId = userId;
    this.axios = axios.create({
      baseURL: 'https://api.trakt.tv',
      timeout: 15000,
      headers: {
        'trakt-api-version': '2',
        'trakt-api-key': this.clientId,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      }
    });
  }

  private async getUserTokens(): Promise<TraktTokens | null> {
    if (!this.userId) return null;
    const repo = AppDataSource.getRepository(UserSettings);
    // traktTokens column has select: false; explicitly addSelect via query builder
    const settings = await repo.createQueryBuilder('s')
      .addSelect('s.traktTokens')
      .where('s.userId = :userId', { userId: this.userId })
      .getOne();
    const raw = (settings as any)?.traktTokens;
    if (!raw) return null;
    try {
      if (typeof raw === 'string') {
        // legacy plaintext JSON
        return JSON.parse(raw);
      }
      if (raw.enc && typeof raw.enc === 'string') {
        const json = decryptForUser(this.userId!, raw.enc);
        return JSON.parse(json);
      }
      return raw as TraktTokens;
    } catch { return null; }
  }

  private async setUserTokens(tokens: TraktTokens) {
    if (!this.userId) return;
    const repo = AppDataSource.getRepository(UserSettings);
    let settings = await repo.findOne({ where: { userId: this.userId } });
    if (!settings) settings = repo.create({ userId: this.userId });
    (settings as any).traktTokens = { enc: encryptForUser(this.userId!, JSON.stringify(tokens)) };
    await repo.save(settings);
  }

  async clearTokens() {
    if (!this.userId) return;
    const repo = AppDataSource.getRepository(UserSettings);
    const settings = await repo.findOne({ where: { userId: this.userId } });
    if (settings) {
      (settings as any).traktTokens = null;
      await repo.save(settings);
    }
  }

  private async authHeaders(): Promise<Record<string, string>> {
    const tokens = await this.getUserTokens();
    const headers: Record<string, string> = {
      'trakt-api-version': '2',
      'trakt-api-key': this.clientId,
    };
    if (tokens?.access_token) {
      // Best-effort refresh if close to expiry
      try {
        const expiresAt = (tokens.created_at + tokens.expires_in) * 1000;
        if (Date.now() >= (expiresAt - 60 * 1000) && tokens.refresh_token) {
          const refreshed = await this.refreshToken(tokens.refresh_token);
          headers['Authorization'] = `Bearer ${refreshed.access_token}`;
          return headers;
        }
      } catch {}
      headers['Authorization'] = `Bearer ${tokens.access_token}`;
    }
    return headers;
  }

  // Device Code
  async deviceCode() {
    const res = await this.axios.post('/oauth/device/code', { client_id: this.clientId });
    return res.data;
  }

  async deviceToken(code: string) {
    const res = await this.axios.post('/oauth/device/token', {
      code,
      client_id: this.clientId,
      client_secret: this.clientSecret,
    });
    const tokens = res.data as TraktTokens;
    await this.setUserTokens(tokens);
    return tokens;
  }

  async refreshToken(refreshToken: string) {
    const res = await this.axios.post('/oauth/token', {
      refresh_token: refreshToken,
      client_id: this.clientId,
      client_secret: this.clientSecret,
      grant_type: 'refresh_token',
    });
    const tokens = res.data as TraktTokens;
    await this.setUserTokens(tokens);
    return tokens;
  }

  // Public endpoints
  async trending(type: 'movies'|'shows', limit?: number) {
    const url = `/${type}/trending${limit ? `?limit=${limit}` : ''}`;
    const res = await this.axios.get(url);
    return res.data;
  }

  async popular(type: 'movies'|'shows', limit?: number) {
    const url = `/${type}/popular${limit ? `?limit=${limit}` : ''}`;
    const res = await this.axios.get(url);
    return res.data;
  }

  // Charts: Most Watched over a period (public)
  async mostWatched(type: 'movies'|'shows', period: 'daily'|'weekly'|'monthly'|'yearly'|'all' = 'weekly', limit?: number) {
    const url = `/${type}/watched/${period}${limit ? `?limit=${limit}` : ''}`;
    const res = await this.axios.get(url);
    return res.data;
  }

  // Anticipated (public)
  async anticipated(type: 'movies'|'shows', limit?: number) {
    const url = `/${type}/anticipated${limit ? `?limit=${limit}` : ''}`;
    const res = await this.axios.get(url);
    return res.data;
  }

  // Authenticated endpoints
  async recommendations(type: 'movies'|'shows', limit?: number) {
    const url = `/recommendations/${type}${limit ? `?limit=${limit}` : ''}`;
    const res = await this.axios.get(url, { headers: await this.authHeaders() });
    return res.data;
  }

  async watchlist(type?: 'movies'|'shows') {
    const url = `/users/me/watchlist${type ? `/${type}` : ''}`;
    const res = await this.axios.get(url, { headers: await this.authHeaders() });
    return res.data;
  }

  async history(type?: 'movies'|'shows', limit?: number) {
    let url = `/users/me/history`;
    if (type) url += `/${type}`;
    if (limit) url += `?limit=${limit}`;
    const res = await this.axios.get(url, { headers: await this.authHeaders() });
    return res.data;
  }

  async userProfile() {
    const res = await this.axios.get('/users/me', { headers: await this.authHeaders() });
    return res.data;
  }

  async watchlistAdd(items: any) {
    const res = await this.axios.post('/sync/watchlist', items, { headers: await this.authHeaders() });
    return res.data;
  }

  async watchlistRemove(items: any) {
    const res = await this.axios.post('/sync/watchlist/remove', items, { headers: await this.authHeaders() });
    return res.data;
  }

  // Scrobbling
  async scrobbleStart(item: any) {
    const res = await this.axios.post('/scrobble/start', item, { headers: await this.authHeaders() });
    return res.data;
  }

  async scrobblePause(item: any) {
    const res = await this.axios.post('/scrobble/pause', item, { headers: await this.authHeaders() });
    return res.data;
  }

  async scrobbleStop(item: any) {
    const res = await this.axios.post('/scrobble/stop', item, { headers: await this.authHeaders() });
    return res.data;
  }
}
