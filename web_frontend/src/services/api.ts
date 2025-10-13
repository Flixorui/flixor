// Backend API client
// Determine API base:
// - If VITE_API_BASE is set, use it (e.g., http://api.example.com/api or /api)
// - In dev, default to same-origin '/api' (proxied by Vite)
// - In prod, default to same-origin '/api' (reverse-proxied by Nginx/CDN)
const defaultApiBase = (() => {
  try {
    // In dev, default to same-origin '/api' (proxied to backend by Vite)
    if ((import.meta as any).env?.DEV) return '/api';
  } catch {}
  // In production, assume same-origin reverse proxy
  return '/api';
})();

const API_BASE: string = (import.meta as any).env?.VITE_API_BASE || defaultApiBase;
const BACKEND_BASE: string = API_BASE.replace(/\/?api\/?$/, '');

class ApiClient {
  private async request(path: string, options?: RequestInit) {
    const response = await fetch(`${API_BASE}${path}`, {
      ...options,
      credentials: 'include', // Include cookies for session
      headers: {
        'Content-Type': 'application/json',
        ...options?.headers,
      },
    });

    if (!response.ok && response.status !== 401) {
      throw new Error(`API Error: ${response.status}`);
    }

    return response.json();
  }

  // Auth endpoints
  async createPlexPin(clientId?: string) {
    return this.request('/auth/plex/pin', {
      method: 'POST',
      body: JSON.stringify({ clientId }),
    });
  }

  async checkPlexPin(pinId: number, clientId: string) {
    return this.request(`/auth/plex/pin/${pinId}?clientId=${clientId}`);
  }

  async getSession() {
    try {
      return await this.request('/auth/session');
    } catch {
      return { authenticated: false };
    }
  }

  async logout() {
    return this.request('/auth/logout', { method: 'POST' });
  }

  async getServers() {
    return this.request('/auth/servers');
  }

  async syncPlexServers(clientId?: string) {
    return this.request('/auth/servers/sync', {
      method: 'POST',
      body: JSON.stringify({ clientId }),
    });
  }

  async validateSession() {
    return this.request('/auth/validate');
  }

  // Plex servers (backend-managed)
  async plexServers() {
    return this.request('/plex/servers');
  }

  async plexSetCurrentServer(serverId: string) {
    return this.request('/plex/servers/current', {
      method: 'POST',
      body: JSON.stringify({ serverId })
    });
  }

  async plexServerConnections(serverId: string) {
    return this.request(`/plex/servers/${encodeURIComponent(serverId)}/connections`);
  }

  async plexSetServerEndpoint(serverId: string, uri: string, test = true) {
    return this.request(`/plex/servers/${encodeURIComponent(serverId)}/endpoint`, {
      method: 'POST',
      body: JSON.stringify({ uri, test })
    });
  }

  // Image proxy methods
  getImageProxyUrl(imageUrl: string, options?: { width?: number; height?: number; quality?: number; format?: string }): string {
    const params = new URLSearchParams({ url: imageUrl });
    if (options?.width) params.append('w', String(options.width));
    if (options?.height) params.append('h', String(options.height));
    if (options?.quality) params.append('q', String(options.quality));
    if (options?.format) params.append('f', options.format);
    return `${BACKEND_BASE}/api/image/proxy?${params.toString()}`;
  }

  getPlexImageProxyUrl(path: string, token: string, server?: string, options?: { width?: number; height?: number }): string {
    const params = new URLSearchParams({ url: path, token });
    if (server) params.append('server', server);
    if (options?.width) params.append('w', String(options.width));
    if (options?.height) params.append('h', String(options.height));
    return `${BACKEND_BASE}/api/image/plex?${params.toString()}`;
  }

  // New: no-token Plex image (backend derives server/token from session)
  getPlexImageNoToken(path: string, options?: { width?: number; height?: number; quality?: number; format?: string }) {
    const params = new URLSearchParams({ path });
    if (options?.width) params.append('w', String(options.width));
    if (options?.height) params.append('h', String(options.height));
    if (options?.quality) params.append('q', String(options.quality));
    if (options?.format) params.append('f', options.format);
    return `${BACKEND_BASE}/api/image/plex?${params.toString()}`;
  }

  // Cache management
  async getCacheStats(bucket?: string) {
    const path = bucket ? `/cache/stats?bucket=${bucket}` : '/cache/stats';
    return this.request(path);
  }

  async flushCache(bucket?: string) {
    const path = bucket ? `/cache/flush?bucket=${bucket}` : '/cache/flush';
    return this.request(path, { method: 'POST' });
  }
}

export const apiClient = new ApiClient();

// Export resolved bases for other services to consume
export const API_BASE_URL: string = API_BASE; // e.g., '/api' or 'https://api.example.com/api'
export const BACKEND_BASE_URL: string = BACKEND_BASE; // e.g., '' or 'https://api.example.com'

// Helper to check if user is authenticated
export async function checkAuth(): Promise<boolean> {
  try {
    const session = await apiClient.getSession();
    return session.authenticated === true;
  } catch {
    return false;
  }
}

// Helper to get current user
export async function getCurrentUser() {
  try {
    const session = await apiClient.getSession();
    if (session.authenticated) {
      return session.user;
    }
    return null;
  } catch {
    return null;
  }
}
