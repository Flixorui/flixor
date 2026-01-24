/**
 * DownloadStorageService - Handles file system operations for downloads
 *
 * Directory Structure (matching Plezy pattern):
 * Documents/
 * ├── Downloads/
 * │   ├── Movies/
 * │   │   └── {Title} ({Year})/
 * │   │       ├── {Title}.{ext}
 * │   │       └── subtitles/
 * │   └── TV Shows/
 * │       └── {Show} ({Year})/
 * │           ├── Season {NN}/
 * │           │   └── S{NN}E{NN} - {Episode}.{ext}
 * │           └── poster.jpg
 * └── artwork/
 *     └── {hash}.jpg  (centralized, deduplicated artwork)
 */

import { File, Directory, Paths } from 'expo-file-system';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { DownloadedMedia, DownloadedMetadata, DownloadProgress, DownloadStatus, DownloadQueueItem, ChapterMarker } from '../../types/downloads';

// Storage keys
const STORAGE_PREFIX = 'flixor:downloads:';
const DOWNLOAD_LIST_KEY = `${STORAGE_PREFIX}list`;
const DOWNLOAD_QUEUE_KEY = `${STORAGE_PREFIX}queue`;

// Helper to get storage key for a specific download
const getMediaKey = (globalKey: string) => `${STORAGE_PREFIX}media:${globalKey}`;
const getMetadataKey = (globalKey: string) => `${STORAGE_PREFIX}metadata:${globalKey}`;
const getProgressKey = (globalKey: string) => `${STORAGE_PREFIX}progress:${globalKey}`;
const getMarkersKey = (globalKey: string) => `${STORAGE_PREFIX}markers:${globalKey}`;

// Base path (without file:// scheme)
let basePath: string = '';

/**
 * Strip file:// scheme from URI if present
 */
function stripFileScheme(uri: string | undefined | null): string {
  if (!uri) return '';
  if (uri.startsWith('file://')) {
    return uri.slice(7);
  }
  return uri;
}

/**
 * Get base document path (strips file:// scheme for clean path operations)
 */
function getBasePath(): string {
  if (!basePath) {
    // Paths.document is a Directory object in expo-file-system, use .uri to get path
    const documentUri = typeof Paths.document === 'string'
      ? Paths.document
      : Paths.document?.uri;
    basePath = stripFileScheme(documentUri);
    // Remove trailing slash if present to avoid double slashes
    if (basePath.endsWith('/')) {
      basePath = basePath.slice(0, -1);
    }
    console.log('[DownloadStorage] Base path initialized:', basePath);
  }
  return basePath;
}

/**
 * Create a directory reference safely
 */
function createDir(path: string | undefined | null): Directory | null {
  if (!path) return null;
  // Ensure we have a clean path without double file:// prefixes
  const cleanPath = stripFileScheme(path);
  if (!cleanPath) return null;
  return new Directory(`file://${cleanPath}`);
}

/**
 * Build a path from segments (always returns clean path without file:// prefix)
 */
function buildPath(...segments: (string | undefined | null)[]): string {
  const result = segments
    .map(s => stripFileScheme(s))
    .filter(Boolean)
    .join('/');

  // Validate that we have a proper path
  if (!result || result === '/') {
    console.warn('[DownloadStorage] Invalid path built from segments:', segments);
    return '';
  }
  return result;
}

/**
 * Convert path to file:// URI for expo-file-system API
 */
function toFileUri(path: string): string {
  const cleanPath = stripFileScheme(path);
  if (!cleanPath) {
    console.warn('[DownloadStorage] toFileUri called with empty path');
    return '';
  }
  return `file://${cleanPath}`;
}

/**
 * Sanitize a filename by removing invalid characters
 */
function sanitizeFilename(name: string): string {
  return name
    .replace(/[/\\?%*:|"<>]/g, '') // Remove invalid characters
    .replace(/\s+/g, ' ')          // Normalize whitespace
    .trim()
    .slice(0, 200);                // Limit length
}

/**
 * Simple hash function for artwork deduplication (like Plezy's MD5 approach)
 */
function hashString(str: string): string {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash; // Convert to 32bit integer
  }
  return Math.abs(hash).toString(16);
}

/**
 * Get the base downloads directory path (returns file:// URI)
 */
export function getDownloadsDirectory(): string {
  return toFileUri(buildPath(getBasePath(), 'Downloads'));
}

/**
 * Get the movies directory path (returns file:// URI)
 */
export function getMoviesDirectory(): string {
  return toFileUri(buildPath(getBasePath(), 'Downloads', 'Movies'));
}

/**
 * Get the TV shows directory path (returns file:// URI)
 */
export function getTVShowsDirectory(): string {
  return toFileUri(buildPath(getBasePath(), 'Downloads', 'TV Shows'));
}

/**
 * Get the artwork directory path (returns file:// URI)
 */
export function getArtworkDirectory(): string {
  return toFileUri(buildPath(getBasePath(), 'artwork'));
}

/**
 * Get the directory path for a specific movie (returns file:// URI)
 */
export function getMovieDirectory(title: string, year?: number): string {
  const folderName = year ? `${sanitizeFilename(title)} (${year})` : sanitizeFilename(title);
  return toFileUri(buildPath(getBasePath(), 'Downloads', 'Movies', folderName));
}

/**
 * Get the file path for a movie video file (returns file:// URI)
 */
export function getMoviePath(title: string, year: number | undefined, ext: string): string {
  const folderName = year ? `${sanitizeFilename(title)} (${year})` : sanitizeFilename(title);
  return toFileUri(buildPath(getBasePath(), 'Downloads', 'Movies', folderName, `${sanitizeFilename(title)}.${ext}`));
}

/**
 * Get the directory path for a specific TV show (returns file:// URI)
 */
export function getShowDirectory(showTitle: string, year?: number): string {
  const folderName = year ? `${sanitizeFilename(showTitle)} (${year})` : sanitizeFilename(showTitle);
  return toFileUri(buildPath(getBasePath(), 'Downloads', 'TV Shows', folderName));
}

/**
 * Get the season directory path for a show (returns file:// URI)
 */
export function getSeasonDirectory(showTitle: string, year: number | undefined, seasonNumber: number): string {
  const showFolderName = year ? `${sanitizeFilename(showTitle)} (${year})` : sanitizeFilename(showTitle);
  const seasonFolder = `Season ${seasonNumber.toString().padStart(2, '0')}`;
  return toFileUri(buildPath(getBasePath(), 'Downloads', 'TV Shows', showFolderName, seasonFolder));
}

/**
 * Get the file path for an episode video file (returns file:// URI)
 */
export function getEpisodePath(
  showTitle: string,
  year: number | undefined,
  seasonNumber: number,
  episodeNumber: number,
  episodeTitle: string,
  ext: string
): string {
  const showFolderName = year ? `${sanitizeFilename(showTitle)} (${year})` : sanitizeFilename(showTitle);
  const seasonFolder = `Season ${seasonNumber.toString().padStart(2, '0')}`;
  const sNum = seasonNumber.toString().padStart(2, '0');
  const eNum = episodeNumber.toString().padStart(2, '0');
  const filename = `S${sNum}E${eNum} - ${sanitizeFilename(episodeTitle)}.${ext}`;
  return toFileUri(buildPath(getBasePath(), 'Downloads', 'TV Shows', showFolderName, seasonFolder, filename));
}

/**
 * Get the artwork path using hash-based deduplication (like Plezy)
 */
export function getArtworkPath(serverId: string, thumbPath: string): string {
  const hash = hashString(`${serverId}:${thumbPath}`);
  return toFileUri(buildPath(getBasePath(), 'artwork', `${hash}.jpg`));
}

/**
 * Get the artwork path for a directory (legacy compatibility)
 */
export function getArtworkPathForDirectory(directory: string): string {
  const cleanDir = stripFileScheme(directory);
  return toFileUri(buildPath(cleanDir, 'poster.jpg'));
}

/**
 * Ensure a directory exists, creating it and all parent directories if necessary
 */
export async function ensureDirectoryExists(path: string | undefined | null): Promise<void> {
  try {
    if (!path) {
      console.log('[DownloadStorage] ensureDirectoryExists: empty path');
      return;
    }

    const cleanPath = stripFileScheme(path);
    if (!cleanPath) {
      console.log('[DownloadStorage] ensureDirectoryExists: empty clean path');
      return;
    }

    console.log('[DownloadStorage] Creating directory:', cleanPath);

    // Split path into segments and create each directory level
    const base = getBasePath();
    if (!base) {
      console.log('[DownloadStorage] ensureDirectoryExists: empty base path');
      return;
    }

    const relativePath = cleanPath.startsWith(base) ? cleanPath.slice(base.length) : cleanPath;
    // Remove leading slash if present
    const normalizedRelativePath = relativePath.startsWith('/') ? relativePath.slice(1) : relativePath;
    const segments = normalizedRelativePath.split('/').filter(Boolean);

    console.log('[DownloadStorage] Creating segments:', segments.length, 'from base:', base);

    let currentPath = base;
    for (let i = 0; i < segments.length; i++) {
      const segment = segments[i];
      currentPath = `${currentPath}/${segment}`;

      try {
        const dirUri = `file://${currentPath}`;
        const dir = new Directory(dirUri);
        if (!dir.exists) {
          console.log('[DownloadStorage] Creating:', segment);
          dir.create();
        }
      } catch (segmentError) {
        console.log('[DownloadStorage] Error creating segment', segment, ':', segmentError);
        // Continue trying to create other directories
      }
    }

    console.log('[DownloadStorage] Directory created:', currentPath);
  } catch (error) {
    console.log('[DownloadStorage] ensureDirectoryExists failed:', error);
  }
}

/**
 * Get available storage space in bytes
 */
export async function getAvailableSpace(): Promise<number> {
  try {
    // The new API doesn't have getFreeDiskStorageAsync directly
    // Return a large default value for now - in production you'd use native module
    return 10 * 1024 * 1024 * 1024; // 10GB default
  } catch (error) {
    console.log('[DownloadStorage] Error getting available space:', error);
    return 0;
  }
}

/**
 * Create a file reference safely
 */
function createFile(path: string | undefined | null): File | null {
  if (!path) return null;
  const cleanPath = stripFileScheme(path);
  if (!cleanPath) return null;
  return new File(`file://${cleanPath}`);
}

/**
 * Check if a file exists
 */
export function fileExists(path: string | undefined | null): boolean {
  try {
    const file = createFile(path);
    if (!file) return false;
    return file.exists;
  } catch {
    return false;
  }
}

/**
 * Get file size in bytes
 */
export function getFileSize(path: string | undefined | null): number {
  try {
    const file = createFile(path);
    if (!file) return 0;
    return file.exists ? (file.size || 0) : 0;
  } catch {
    return 0;
  }
}

/**
 * Delete a file
 */
export async function deleteFile(path: string | undefined | null): Promise<void> {
  if (!path) return;
  try {
    const file = createFile(path);
    if (file && file.exists) {
      file.delete();
    }
  } catch (error) {
    console.log('[DownloadStorage] Error deleting file:', error);
  }
}

/**
 * Delete a directory and its contents
 */
export async function deleteDirectory(path: string | undefined | null): Promise<void> {
  if (!path) return;
  try {
    const dir = createDir(path);
    if (dir && dir.exists) {
      dir.delete();
    }
  } catch (error) {
    console.log('[DownloadStorage] Error deleting directory:', error);
  }
}

/**
 * Delete all files for a download
 */
export async function deleteDownloadFiles(media: DownloadedMedia, metadata?: DownloadedMetadata): Promise<void> {
  try {
    if (media.videoFilePath) {
      await deleteFile(media.videoFilePath);
    }

    if (media.thumbPath) {
      await deleteFile(media.thumbPath);
    }

    // For movies, try to clean up the directory if empty
    if (media.type === 'movie' && metadata) {
      const movieDir = getMovieDirectory(metadata.title, metadata.year);
      try {
        const dir = createDir(movieDir);
        if (dir && dir.exists) {
          const contents = dir.list();
          if (contents.length === 0) {
            dir.delete();
          }
        }
      } catch (e) {
        // Ignore errors cleaning up directories
      }
    }

    // For episodes, try to clean up season and show directories if empty
    if (media.type === 'episode' && metadata) {
      const showTitle = metadata.grandparentTitle || 'Unknown Show';
      const seasonNum = metadata.parentIndex || 1;

      // Try to clean up season directory
      const seasonDir = getSeasonDirectory(showTitle, metadata.year, seasonNum);
      try {
        const dir = createDir(seasonDir);
        if (dir && dir.exists) {
          const contents = dir.list();
          if (contents.length === 0) {
            dir.delete();
          }
        }
      } catch (e) {
        // Ignore errors
      }

      // Try to clean up show directory
      const showDir = getShowDirectory(showTitle, metadata.year);
      try {
        const dir = createDir(showDir);
        if (dir && dir.exists) {
          const contents = dir.list();
          if (contents.length === 0) {
            dir.delete();
          }
        }
      } catch (e) {
        // Ignore errors
      }
    }
  } catch (error) {
    console.log('[DownloadStorage] Error deleting files:', error);
  }
}

// ============================================
// AsyncStorage Operations for Metadata
// ============================================

/**
 * Save the list of downloaded globalKeys
 */
export async function saveDownloadList(globalKeys: string[]): Promise<void> {
  try {
    await AsyncStorage.setItem(DOWNLOAD_LIST_KEY, JSON.stringify(globalKeys));
  } catch (error) {
    console.log('[DownloadStorage] Error saving download list:', error);
  }
}

/**
 * Load the list of downloaded globalKeys
 */
export async function loadDownloadList(): Promise<string[]> {
  try {
    const stored = await AsyncStorage.getItem(DOWNLOAD_LIST_KEY);
    return stored ? JSON.parse(stored) : [];
  } catch (error) {
    console.log('[DownloadStorage] Error loading download list:', error);
    return [];
  }
}

/**
 * Save download media info
 */
export async function saveDownloadMedia(globalKey: string, media: DownloadedMedia): Promise<void> {
  try {
    await AsyncStorage.setItem(getMediaKey(globalKey), JSON.stringify(media));
  } catch (error) {
    console.log('[DownloadStorage] Error saving download media:', error);
  }
}

/**
 * Load download media info
 */
export async function loadDownloadMedia(globalKey: string): Promise<DownloadedMedia | null> {
  try {
    const stored = await AsyncStorage.getItem(getMediaKey(globalKey));
    return stored ? JSON.parse(stored) : null;
  } catch (error) {
    console.log('[DownloadStorage] Error loading download media:', error);
    return null;
  }
}

/**
 * Delete download media info
 */
export async function deleteDownloadMedia(globalKey: string): Promise<void> {
  try {
    await AsyncStorage.removeItem(getMediaKey(globalKey));
  } catch (error) {
    console.log('[DownloadStorage] Error deleting download media:', error);
  }
}

/**
 * Save download metadata
 */
export async function saveDownloadMetadata(globalKey: string, metadata: DownloadedMetadata): Promise<void> {
  try {
    await AsyncStorage.setItem(getMetadataKey(globalKey), JSON.stringify(metadata));
  } catch (error) {
    console.log('[DownloadStorage] Error saving download metadata:', error);
  }
}

/**
 * Load download metadata
 */
export async function loadDownloadMetadata(globalKey: string): Promise<DownloadedMetadata | null> {
  try {
    const stored = await AsyncStorage.getItem(getMetadataKey(globalKey));
    return stored ? JSON.parse(stored) : null;
  } catch (error) {
    console.log('[DownloadStorage] Error loading download metadata:', error);
    return null;
  }
}

/**
 * Delete download metadata
 */
export async function deleteDownloadMetadata(globalKey: string): Promise<void> {
  try {
    await AsyncStorage.removeItem(getMetadataKey(globalKey));
  } catch (error) {
    console.log('[DownloadStorage] Error deleting download metadata:', error);
  }
}

/**
 * Save download progress
 */
export async function saveDownloadProgress(globalKey: string, progress: DownloadProgress): Promise<void> {
  try {
    await AsyncStorage.setItem(getProgressKey(globalKey), JSON.stringify(progress));
  } catch (error) {
    console.log('[DownloadStorage] Error saving download progress:', error);
  }
}

/**
 * Load download progress
 */
export async function loadDownloadProgress(globalKey: string): Promise<DownloadProgress | null> {
  try {
    const stored = await AsyncStorage.getItem(getProgressKey(globalKey));
    return stored ? JSON.parse(stored) : null;
  } catch (error) {
    console.log('[DownloadStorage] Error loading download progress:', error);
    return null;
  }
}

/**
 * Delete download progress
 */
export async function deleteDownloadProgress(globalKey: string): Promise<void> {
  try {
    await AsyncStorage.removeItem(getProgressKey(globalKey));
  } catch (error) {
    console.log('[DownloadStorage] Error deleting download progress:', error);
  }
}

/**
 * Save chapter markers for offline playback
 */
export async function saveMarkers(globalKey: string, markers: ChapterMarker[]): Promise<void> {
  try {
    await AsyncStorage.setItem(getMarkersKey(globalKey), JSON.stringify(markers));
  } catch (error) {
    console.log('[DownloadStorage] Error saving markers:', error);
  }
}

/**
 * Load chapter markers for offline playback
 */
export async function loadMarkers(globalKey: string): Promise<ChapterMarker[]> {
  try {
    const stored = await AsyncStorage.getItem(getMarkersKey(globalKey));
    return stored ? JSON.parse(stored) : [];
  } catch (error) {
    console.log('[DownloadStorage] Error loading markers:', error);
    return [];
  }
}

/**
 * Delete chapter markers
 */
export async function deleteMarkers(globalKey: string): Promise<void> {
  try {
    await AsyncStorage.removeItem(getMarkersKey(globalKey));
  } catch (error) {
    console.log('[DownloadStorage] Error deleting markers:', error);
  }
}

/**
 * Save download queue
 */
export async function saveDownloadQueue(queue: DownloadQueueItem[]): Promise<void> {
  try {
    await AsyncStorage.setItem(DOWNLOAD_QUEUE_KEY, JSON.stringify(queue));
  } catch (error) {
    console.log('[DownloadStorage] Error saving download queue:', error);
  }
}

/**
 * Load download queue
 */
export async function loadDownloadQueue(): Promise<DownloadQueueItem[]> {
  try {
    const stored = await AsyncStorage.getItem(DOWNLOAD_QUEUE_KEY);
    return stored ? JSON.parse(stored) : [];
  } catch (error) {
    console.log('[DownloadStorage] Error loading download queue:', error);
    return [];
  }
}

/**
 * Completely remove a download (files + all metadata)
 */
export async function removeDownloadCompletely(globalKey: string): Promise<void> {
  try {
    const media = await loadDownloadMedia(globalKey);
    const metadata = await loadDownloadMetadata(globalKey);

    // Delete files
    if (media) {
      await deleteDownloadFiles(media, metadata || undefined);
    }

    // Delete metadata
    await deleteDownloadMedia(globalKey);
    await deleteDownloadMetadata(globalKey);
    await deleteDownloadProgress(globalKey);
    await deleteMarkers(globalKey);

    // Update download list
    const list = await loadDownloadList();
    const newList = list.filter(k => k !== globalKey);
    await saveDownloadList(newList);
  } catch (error) {
    console.log('[DownloadStorage] Error removing download:', error);
  }
}

/**
 * Get total size of all downloads in bytes
 */
export async function getTotalDownloadsSize(): Promise<number> {
  try {
    const list = await loadDownloadList();
    let totalSize = 0;

    for (const globalKey of list) {
      const media = await loadDownloadMedia(globalKey);
      if (media?.downloadedBytes) {
        totalSize += media.downloadedBytes;
      }
    }

    return totalSize;
  } catch (error) {
    console.log('[DownloadStorage] Error getting total size:', error);
    return 0;
  }
}

/**
 * Load all downloads with their metadata
 */
export async function loadAllDownloads(): Promise<{
  media: Map<string, DownloadedMedia>;
  metadata: Map<string, DownloadedMetadata>;
  progress: Map<string, DownloadProgress>;
}> {
  const media = new Map<string, DownloadedMedia>();
  const metadata = new Map<string, DownloadedMetadata>();
  const progress = new Map<string, DownloadProgress>();

  try {
    const list = await loadDownloadList();

    for (const globalKey of list) {
      const mediaData = await loadDownloadMedia(globalKey);
      const metaData = await loadDownloadMetadata(globalKey);
      const progressData = await loadDownloadProgress(globalKey);

      if (mediaData) media.set(globalKey, mediaData);
      if (metaData) metadata.set(globalKey, metaData);
      if (progressData) progress.set(globalKey, progressData);
    }
  } catch (error) {
    console.log('[DownloadStorage] Error loading all downloads:', error);
  }

  return { media, metadata, progress };
}

/**
 * Initialize downloads directory structure
 */
export async function initializeDownloadsDirectory(): Promise<void> {
  try {
    // Reset cached base path to ensure fresh initialization
    basePath = '';

    // Create base directories using ensureDirectoryExists for recursive creation
    await ensureDirectoryExists(getDownloadsDirectory());
    await ensureDirectoryExists(getMoviesDirectory());
    await ensureDirectoryExists(getTVShowsDirectory());
    await ensureDirectoryExists(getArtworkDirectory());

    console.log('[DownloadStorage] Initialized directories at:', getBasePath());
  } catch (error) {
    console.log('[DownloadStorage] Error initializing directories:', error);
  }
}
