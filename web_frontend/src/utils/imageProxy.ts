import { apiClient } from '@/services/api';

/**
 * Configuration for image proxy
 */
const IMAGE_PROXY_CONFIG = {
  enableProxy: true, // Toggle to enable/disable proxy
  defaultQuality: 85,
  defaultFormat: 'jpeg',
};

/**
 * Get proxied image URL
 * Uses backend image proxy for caching and optimization
 */
export function getProxiedImageUrl(
  imageUrl: string | undefined,
  options?: {
    width?: number;
    height?: number;
    quality?: number;
    format?: 'jpeg' | 'png' | 'webp';
  }
): string | undefined {
  if (!imageUrl) return undefined;

  // Skip proxy for local or data URLs
  if (imageUrl.startsWith('data:') || imageUrl.startsWith('blob:')) {
    return imageUrl;
  }

  // Use proxy if enabled
  if (IMAGE_PROXY_CONFIG.enableProxy) {
    try {
      return apiClient.getImageProxyUrl(imageUrl, {
        quality: options?.quality || IMAGE_PROXY_CONFIG.defaultQuality,
        format: options?.format || IMAGE_PROXY_CONFIG.defaultFormat,
        width: options?.width,
        height: options?.height,
      });
    } catch (error) {
      console.error('Failed to generate proxy URL:', error);
      return imageUrl; // Fallback to original URL
    }
  }

  return imageUrl;
}

/**
 * Get proxied Plex image URL
 */
export function getProxiedPlexImageUrl(
  path: string | undefined,
  token: string | undefined,
  server?: string,
  options?: {
    width?: number;
    height?: number;
  }
): string | undefined {
  if (!path || !token) return undefined;

  if (IMAGE_PROXY_CONFIG.enableProxy) {
    try {
      return apiClient.getPlexImageProxyUrl(path, token, server, options);
    } catch (error) {
      console.error('Failed to generate Plex proxy URL:', error);
      // Fallback to direct Plex URL
      const baseUrl = server || '';
      return `${baseUrl}${path}${path.includes('?') ? '&' : '?'}X-Plex-Token=${token}`;
    }
  }

  // Direct Plex URL
  const baseUrl = server || '';
  return `${baseUrl}${path}${path.includes('?') ? '&' : '?'}X-Plex-Token=${token}`;
}

/**
 * Preload image through proxy
 */
export function preloadProxiedImage(
  imageUrl: string,
  options?: {
    width?: number;
    height?: number;
  }
): Promise<void> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    const proxiedUrl = getProxiedImageUrl(imageUrl, options);

    if (!proxiedUrl) {
      reject(new Error('Invalid image URL'));
      return;
    }

    img.onload = () => resolve();
    img.onerror = () => reject(new Error('Failed to load image'));
    img.src = proxiedUrl;
  });
}

/**
 * Get optimized image URL based on viewport size
 */
export function getResponsiveImageUrl(
  imageUrl: string | undefined,
  size: 'thumbnail' | 'small' | 'medium' | 'large' | 'full'
): string | undefined {
  if (!imageUrl) return undefined;

  const sizeConfig = {
    thumbnail: { width: 200, quality: 75 },
    small: { width: 400, quality: 80 },
    medium: { width: 800, quality: 85 },
    large: { width: 1280, quality: 90 },
    full: { quality: 95 }, // No resize
  };

  const config = sizeConfig[size];
  return getProxiedImageUrl(imageUrl, config);
}

/**
 * Toggle image proxy (for debugging)
 */
export function setImageProxyEnabled(enabled: boolean) {
  IMAGE_PROXY_CONFIG.enableProxy = enabled;
}

/**
 * Check if image proxy is enabled
 */
export function isImageProxyEnabled(): boolean {
  return IMAGE_PROXY_CONFIG.enableProxy;
}