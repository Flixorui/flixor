/**
 * Muted trailer playing over artwork (Details hero, New & Hot cards).
 * macOS reference: Views/Details/DetailsHeroTrailer.swift
 *
 * A web view with YouTube's player set to start muted and autoplay from the first load, so
 * playback doesn't depend on a "play" message arriving at the right moment (iOS ignores
 * unmuted autoplay, and the library player sent play before mute, so nothing started).
 * The artwork shows until playback actually starts, and returns when it ends or fails.
 *
 * Fast start (under ~2 s):
 * - The player is taller than the visible area, so YouTube draws its title bar and logo in
 *   black bands above and below the video, outside the clip. No need to wait for them to fade.
 * - YouTube also shows a pause icon in the middle for the first ~4.5 s of playback, which no
 *   crop can hide. So the video is shown only once that has passed. A preloaded player
 *   (`active` true, `visible` false) plays hidden ahead of time, so by the time it's shown the
 *   icon has already gone and it appears at once.
 */

import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Animated, StyleSheet, View } from 'react-native';
import { WebView } from 'react-native-webview';

// YouTube wants to know which site embeds it; the app's own domain
const ORIGIN = 'https://flixor.xyz';
// Shown once the first frames have played. YouTube draws a pause icon over the middle of the
// video for its first ~4.5 s (no crop can hide it); a cold trailer shows with it rather than
// wait. Players that may be shown soon (the next card) play hidden ahead of time, so by the
// time they show the icon has gone.
const OVERLAY_MS = 400;
const FADE_MS = 250;
// Extra player height above and below the video, as a share of the video height. YouTube's
// title bar and logo sit in this band, outside the visible area.
const OVERLAY_BAND = 0.32;
// If autoplay hasn't started a player that should be playing, nudge it
const NUDGE_AFTER_MS = 1000;

function playerHtml(videoKey: string, autoplay: boolean) {
  return `<!DOCTYPE html><html><head>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<style>html,body{margin:0;padding:0;background:#000;overflow:hidden;height:100%}#p{position:absolute;inset:0;width:100%;height:100%}</style>
</head><body><div id="p"></div>
<script>
var tag=document.createElement('script');tag.src='https://www.youtube.com/iframe_api';document.head.appendChild(tag);
var player;
function send(m){window.ReactNativeWebView&&window.ReactNativeWebView.postMessage(JSON.stringify(m));}
function onYouTubeIframeAPIReady(){
  player=new YT.Player('p',{width:'100%',height:'100%',videoId:'${videoKey}',
    playerVars:{autoplay:${autoplay ? 1 : 0},mute:1,cc_load_policy:0,playsinline:1,controls:0,rel:0,modestbranding:1,iv_load_policy:3,fs:0,disablekb:1,origin:'${ORIGIN}'},
    events:{
      onReady:function(e){e.target.mute();send({t:'ready'});},
      onStateChange:function(e){
        // No captions: YouTube may turn them on by default, so drop the captions module
        if(e.data===1||e.data===3){try{e.target.unloadModule('captions');e.target.unloadModule('cc');}catch(x){}}
        send({t:'state',s:e.data});},
      onError:function(e){send({t:'error',c:e.data});}
    }});
}
window.flixor={mute:function(m){if(!player)return;m?player.mute():player.unMute();},
  play:function(p){if(!player)return;p?player.playVideo():player.pauseVideo();}};
</script></body></html>`;
}

export default function DetailsHeroTrailer({
  videoKey,
  width,
  height,
  muted,
  active,
  visible = true,
  warmup = false,
  onPlayingChange,
  onFinished,
}: {
  videoKey: string;
  width: number;
  height: number;
  muted: boolean;
  /** False pauses playback, for example when the hero is scrolled away. */
  active: boolean;
  /** False plays hidden (preloading); the video shows only when this is true. Defaults to true. */
  visible?: boolean;
  /**
   * Warm up while not active: play hidden just until YouTube's start overlay has passed, then
   * pause. When the player becomes active it resumes and shows at once.
   */
  warmup?: boolean;
  onPlayingChange: (playing: boolean) => void;
  onFinished: () => void;
}) {
  const [started, setStarted] = useState(false);
  const web = useRef<WebView>(null);
  const reveal = useRef(new Animated.Value(0.01)).current;
  const revealTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => () => {
    if (revealTimer.current) clearTimeout(revealTimer.current);
  }, []);
  useEffect(() => {
    Animated.timing(reveal, { toValue: started ? 1 : 0.01, duration: FADE_MS, useNativeDriver: true }).start();
  }, [started, reveal]);
  // Autoplay is decided at load; a preloaded (inactive) player waits for "play"
  const autoplayAtLoad = useRef(active || warmup).current;
  const html = useMemo(() => playerHtml(videoKey, autoplayAtLoad), [videoKey, autoplayAtLoad]);
  const playing = useRef(false);
  const ready = useRef(false);
  const firstPlayAt = useRef<number | null>(null);
  const [hasPlayed, setHasPlayed] = useState(false);
  const [warmedUp, setWarmedUp] = useState(false);
  // Plays when active, or hidden while warming up
  const shouldPlay = active || (warmup && !warmedUp);

  useEffect(() => {
    if (!hasPlayed || warmedUp || firstPlayAt.current === null) return;
    const t = setTimeout(() => setWarmedUp(true), Math.max(0, OVERLAY_MS - (Date.now() - firstPlayAt.current)));
    return () => clearTimeout(t);
  }, [hasPlayed, warmedUp]);

  // Show the video once it may be shown and YouTube's start overlay has passed
  useEffect(() => {
    if (revealTimer.current) clearTimeout(revealTimer.current);
    revealTimer.current = null;
    if (!visible || !active) {
      setStarted(false);
      return;
    }
    if (!hasPlayed || firstPlayAt.current === null) return;
    const wait = Math.max(0, OVERLAY_MS - (Date.now() - firstPlayAt.current));
    revealTimer.current = setTimeout(() => {
      revealTimer.current = null;
      setStarted(true);
      onPlayingChange(true);
    }, wait);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible, active, hasPlayed]);

  // Autoplay normally starts it. If it hasn't (it loaded in a hidden tab, where iOS won't
  // start video, or autoplay was refused), keep asking every second while it should play.
  useEffect(() => {
    if (!shouldPlay) return;
    const t = setInterval(() => {
      if (ready.current && !playing.current) web.current?.injectJavaScript('window.flixor&&window.flixor.play(true);true;');
    }, NUDGE_AFTER_MS);
    return () => clearInterval(t);
  }, [shouldPlay]);

  // Smallest 16:9 box covering the area, so the video never letterboxes
  const coverHeight = Math.max(height, (width * 9) / 16);
  const coverWidth = Math.max(width, (coverHeight * 16) / 9);

  useEffect(() => {
    web.current?.injectJavaScript(`window.flixor&&window.flixor.mute(${muted});true;`);
  }, [muted]);
  useEffect(() => {
    web.current?.injectJavaScript(`window.flixor&&window.flixor.play(${shouldPlay});true;`);
  }, [shouldPlay]);
  const band = coverHeight * OVERLAY_BAND;

  return (
    <Animated.View
      pointerEvents="none"
      // Never fully 0 before it starts: WebKit won't start media in a fully transparent view
      style={[StyleSheet.absoluteFill, styles.clip, { opacity: reveal }]}
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
    >
      <View
        style={{
          width: coverWidth,
          height: coverHeight + band * 2,
          marginLeft: (width - coverWidth) / 2,
          marginTop: (height - coverHeight) / 2 - band,
        }}
      >
        <WebView
          ref={web}
          source={{ html, baseUrl: ORIGIN }}
          style={{ flex: 1, backgroundColor: '#000' }}
          allowsInlineMediaPlayback
          mediaPlaybackRequiresUserAction={false}
          allowsFullscreenVideo={false}
          scrollEnabled={false}
          bounces={false}
          javaScriptEnabled
          originWhitelist={['*']}
          onMessage={(e) => {
            let m: any;
            try {
              m = JSON.parse(e.nativeEvent.data);
            } catch {
              return;
            }
            if (m.t === 'ready') {
              ready.current = true;
              // A preloaded player that became active before it was ready
              if (shouldPlay && !autoplayAtLoad) web.current?.injectJavaScript('window.flixor&&window.flixor.play(true);true;');
            } else if (m.t === 'state') {
              playing.current = m.s === 1;
              if (m.s === 1) {
                if (firstPlayAt.current === null) {
                  firstPlayAt.current = Date.now();
                  setHasPlayed(true);
                }
              } else if (m.s === 0) {
                if (revealTimer.current) clearTimeout(revealTimer.current);
                revealTimer.current = null;
                setStarted(false);
                onPlayingChange(false);
                onFinished();
              }
            } else if (m.t === 'error') {
              if (revealTimer.current) clearTimeout(revealTimer.current);
              revealTimer.current = null;
              setStarted(false);
              onPlayingChange(false);
              onFinished();
            }
          }}
        />
      </View>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  clip: {
    overflow: 'hidden',
  },
});
