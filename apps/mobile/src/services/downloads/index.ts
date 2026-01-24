/**
 * Downloads Services - Barrel export
 */

export * from './DownloadStorageService';
export * from './DownloadService';
export * from './DownloadStore';
export * from './OfflineMetadataService';

// Re-export the singleton instances
export { downloadService } from './DownloadService';
export { downloadStore, useDownloadStore, useDownloads, useDownloadStatus } from './DownloadStore';
