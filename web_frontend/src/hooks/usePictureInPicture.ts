import { useCallback, useEffect, useRef, useState } from 'react';

/**
 * Picture-in-Picture helper that prefers Document Picture-in-Picture when available,
 * and falls back to the classic HTMLVideoElement PiP API.
 */
export function usePictureInPicture(videoRef: React.RefObject<HTMLVideoElement>) {
  const [active, setActive] = useState(false);
  const pipWindowRef = useRef<Window | null>(null);

  const hasElementPiP = typeof document !== 'undefined' && 'pictureInPictureEnabled' in document;
  const hasDocumentPiP = typeof window !== 'undefined' && (window as any).documentPictureInPicture;

  // Keep state in sync with element PiP events
  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    const onEnter = () => setActive(true);
    const onLeave = () => setActive(false);
    v.addEventListener('enterpictureinpicture', onEnter);
    v.addEventListener('leavepictureinpicture', onLeave);
    return () => {
      v.removeEventListener('enterpictureinpicture', onEnter);
      v.removeEventListener('leavepictureinpicture', onLeave);
    };
  }, [videoRef.current]);

  // Close document PiP window when the page unloads
  useEffect(() => {
    return () => {
      try { pipWindowRef.current?.close?.(); } catch {}
      pipWindowRef.current = null;
    };
  }, []);

  const enter = useCallback(async () => {
    const video = videoRef.current;
    if (!video) return false;
    try {
      // If in fullscreen, exit first (browsers disallow PiP + fullscreen at once)
      try { if (document.fullscreenElement) await document.exitFullscreen(); } catch {}

      // Ensure playback started so PiP works reliably
      try { await video.play(); } catch {}

      // Prefer Element Picture-in-Picture for video playback (most robust with MSE)
      if (hasElementPiP && (document as any).pictureInPictureEnabled && (video as any).requestPictureInPicture) {
        await (video as any).requestPictureInPicture();
        setActive(true);
        return true;
      }

      // Safari fallback (WKWebView): use webkitPresentationMode
      // @ts-ignore
      if ((video as any).webkitSupportsPresentationMode && typeof (video as any).webkitSetPresentationMode === 'function') {
        try {
          // @ts-ignore
          (video as any).webkitSetPresentationMode('picture-in-picture');
          setActive(true);
          return true;
        } catch {}
      }
      // As a last resort, try Document Picture-in-Picture with captureStream clone
      if (hasDocumentPiP) {
        // @ts-ignore
        const pipWindow: Window = await (window as any).documentPictureInPicture.requestWindow({ width: 480, height: 270 });
        pipWindowRef.current = pipWindow;
        pipWindow.document.body.style.margin = '0';
        pipWindow.document.body.style.background = 'black';
        const v = pipWindow.document.createElement('video');
        v.autoplay = true; v.playsInline = true; v.controls = true; v.style.width = '100%'; v.style.height = '100%'; v.style.objectFit = 'contain';
        try {
          // Prefer streaming the current playing element so playback stays in sync
          // captureStream is supported on Chromium-based browsers
          // @ts-ignore
          const stream = (video as any).captureStream ? (video as any).captureStream() : null;
          if (stream) {
            // @ts-ignore
            v.srcObject = stream;
          } else {
            v.src = video.currentSrc || video.src;
          }
        } catch {
          v.src = video.currentSrc || video.src;
        }
        try { v.muted = video.muted; v.playbackRate = video.playbackRate; } catch {}
        pipWindow.document.body.appendChild(v);
        try { await v.play(); } catch {}
        pipWindow.addEventListener('pagehide', () => { pipWindowRef.current = null; setActive(false); });
        setActive(true);
        return true;
      }
    } catch (e) {
      console.warn('PiP enter failed', e);
    }
    return false;
  }, [videoRef.current]);

  const exit = useCallback(async () => {
    try {
      const video = videoRef.current as any;
      if (video && video.webkitPresentationMode === 'picture-in-picture' && typeof video.webkitSetPresentationMode === 'function') {
        try { video.webkitSetPresentationMode('inline'); setActive(false); return true; } catch {}
      }
      if (pipWindowRef.current) {
        pipWindowRef.current.close();
        pipWindowRef.current = null;
        setActive(false);
        return true;
      }
      // Element PiP
      // @ts-ignore
      if (document.pictureInPictureElement) {
        // @ts-ignore
        await document.exitPictureInPicture();
        setActive(false);
        return true;
      }
    } catch (e) {
      console.warn('PiP exit failed', e);
    }
    return false;
  }, []);

  const toggle = useCallback(async () => {
    if (active) return exit();
    return enter();
  }, [active, enter, exit]);

  return {
    supported: Boolean(hasDocumentPiP || hasElementPiP),
    active,
    enter,
    exit,
    toggle,
  } as const;
}
