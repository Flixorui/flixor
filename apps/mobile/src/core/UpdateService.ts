/**
 * UpdateService - OTA Update Management
 *
 * Handles checking for and applying over-the-air updates
 * using expo-updates with self-hosted server at ota.flixor.xyz
 */

import * as Updates from 'expo-updates';

export interface UpdateInfo {
  isAvailable: boolean;
  manifest?: Updates.Manifest;
  releaseNotes?: string;
}

export interface UpdateState {
  isEnabled: boolean;
  updateId: string | null;
  channel: string | null;
  runtimeVersion: string | null;
  createdAt: Date | null;
  isEmbeddedLaunch: boolean;
}

class UpdateService {
  private static instance: UpdateService;
  private logs: string[] = [];
  private readonly MAX_LOGS = 100;

  static getInstance(): UpdateService {
    if (!UpdateService.instance) {
      UpdateService.instance = new UpdateService();
    }
    return UpdateService.instance;
  }

  private log(message: string): void {
    const timestamp = new Date().toISOString();
    const logEntry = `[${timestamp}] ${message}`;
    console.log(`[UpdateService] ${message}`);
    this.logs.push(logEntry);
    if (this.logs.length > this.MAX_LOGS) {
      this.logs.shift();
    }
  }

  /**
   * Check for available updates
   */
  async checkForUpdates(): Promise<UpdateInfo> {
    if (!Updates.isEnabled) {
      this.log('Updates not enabled (dev mode or disabled)');
      return { isAvailable: false };
    }

    try {
      const state = this.getUpdateState();
      this.log(`Checking for updates... (current: ${state.updateId?.substring(0, 8) || 'embedded'}, embedded: ${state.isEmbeddedLaunch})`);
      const startTime = Date.now();
      const update = await Updates.checkForUpdateAsync();
      const duration = Date.now() - startTime;

      this.log(`Check completed in ${duration}ms - available: ${update.isAvailable}`);
      this.log(`Full update response: ${JSON.stringify(update, null, 2)}`);

      if (update.isAvailable && update.manifest) {
        this.log(`New update available: ${(update.manifest as any).id}`);
        // Extract release notes from manifest metadata if available
        const releaseNotes = (update.manifest as any).metadata?.releaseNotes;
        return {
          isAvailable: true,
          manifest: update.manifest,
          releaseNotes,
        };
      }

      this.log('No update available from expo-updates');
      return { isAvailable: false };
    } catch (error) {
      this.log(`Update check failed: ${error}`);
      return { isAvailable: false };
    }
  }

  /**
   * Download and apply available update
   * App will reload after successful installation
   */
  async downloadAndApply(): Promise<boolean> {
    if (!Updates.isEnabled) {
      this.log('Cannot apply update - updates not enabled');
      return false;
    }

    try {
      this.log('Downloading update...');
      const startTime = Date.now();
      const result = await Updates.fetchUpdateAsync();
      const downloadDuration = Date.now() - startTime;

      this.log(`Download completed in ${downloadDuration}ms - isNew: ${result.isNew}`);

      if (result.isNew) {
        this.log('Reloading app with new update...');
        await Updates.reloadAsync();
        return true;
      }

      this.log('No new update to apply');
      return false;
    } catch (error) {
      this.log(`Update download/apply failed: ${error}`);
      return false;
    }
  }

  /**
   * Get current update state
   */
  getUpdateState(): UpdateState {
    return {
      isEnabled: Updates.isEnabled,
      updateId: Updates.updateId,
      channel: Updates.channel,
      runtimeVersion: Updates.runtimeVersion,
      createdAt: Updates.createdAt,
      isEmbeddedLaunch: Updates.isEmbeddedLaunch,
    };
  }

  /**
   * Force check for updates by making a direct fetch to bypass expo-updates caching
   * Returns true if server has a different update than what's currently running
   */
  async forceCheckForUpdates(): Promise<UpdateInfo> {
    try {
      const state = this.getUpdateState();
      this.log(`Force checking updates (current: ${state.updateId?.substring(0, 8) || 'embedded'})`);

      // Direct fetch to manifest endpoint with cache-busting
      const response = await fetch(
        `https://ota.flixor.xyz/api/manifest?_=${Date.now()}`,
        {
          method: 'GET',
          headers: {
            'expo-runtime-version': state.runtimeVersion || '0.1.8',
            'expo-platform': Platform.OS,
            'expo-protocol-version': '1',
            'Cache-Control': 'no-cache, no-store',
            'Pragma': 'no-cache',
          },
        }
      );

      if (!response.ok) {
        this.log(`Manifest fetch failed: ${response.status}`);
        return this.checkForUpdates();
      }

      // Parse multipart response to get manifest
      const contentType = response.headers.get('content-type') || '';
      if (contentType.includes('multipart')) {
        const text = await response.text();
        // Extract the manifest JSON - it's between the first Content-Type: application/json and the next boundary
        // Look for "id" field pattern to find the manifest object
        const idMatch = text.match(/"id"\s*:\s*"([^"]+)"/);
        if (idMatch) {
          const serverId = idMatch[1];
          const currentId = state.updateId;

          this.log(`Server update: ${serverId?.substring(0, 8)}, Current: ${currentId?.substring(0, 8) || 'embedded'}`);

          // Compare IDs - if different, update available
          if (serverId && serverId !== currentId) {
            this.log('Update available from force check, calling expo-updates');
            return this.checkForUpdates();
          } else {
            this.log('Same update ID, no update needed');
            return { isAvailable: false };
          }
        }
      }

      // Fallback to regular check
      this.log('Could not parse manifest, falling back to expo-updates');
      return this.checkForUpdates();
    } catch (error) {
      this.log(`Force check failed: ${error}`);
      // Fall back to regular check
      return this.checkForUpdates();
    }
  }

  /**
   * Test connectivity to OTA server
   */
  async testConnectivity(): Promise<{
    success: boolean;
    latency?: number;
    error?: string;
  }> {
    try {
      const state = this.getUpdateState();
      this.log(`Testing connectivity for runtime: ${state.runtimeVersion}`);

      const startTime = Date.now();
      const response = await fetch('https://ota.flixor.xyz/api/health', {
        method: 'GET',
        headers: {
          'expo-runtime-version': state.runtimeVersion || '',
          'expo-platform': Platform.OS,
        },
      });
      const latency = Date.now() - startTime;

      if (response.ok) {
        this.log(`Server reachable - latency: ${latency}ms`);
        return { success: true, latency };
      } else {
        const error = `Server returned ${response.status}`;
        this.log(`Server error: ${error}`);
        return { success: false, error };
      }
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : 'Unknown error';
      this.log(`Connectivity test failed: ${errorMsg}`);
      return { success: false, error: errorMsg };
    }
  }

  /**
   * Get service logs for debugging
   */
  getLogs(): string[] {
    return [...this.logs];
  }

  /**
   * Clear logs
   */
  clearLogs(): void {
    this.logs = [];
  }
}

// Import Platform for connectivity test
import { Platform } from 'react-native';

export default UpdateService;
