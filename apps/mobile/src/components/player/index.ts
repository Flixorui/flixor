/**
 * Player components index
 *
 * MPV is now the unified player for both iOS and Android:
 * - iOS: MPVKit (libmpv) with Metal/Vulkan rendering
 * - Android: Native MPV with OpenGL/Vulkan rendering
 */

// Unified MPV Player (iOS + Android)
export { default as MPVPlayerComponent } from './MPVPlayerComponent';
export type { MPVPlayerRef, MPVPlayerProps, MPVPlayerSource, MPVAudioTrack, MPVSubtitleTrack } from './MPVPlayerComponent';
