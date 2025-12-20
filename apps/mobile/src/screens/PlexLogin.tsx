import React, { useEffect, useRef, useState } from 'react';
import {
  View,
  Text,
  Pressable,
  ActivityIndicator,
  Linking as RNLinking,
  Alert,
  AppState,
  AppStateStatus,
} from 'react-native';
import { getFlixorCore } from '../core';

// The URL where users enter their PIN code
const PLEX_LINK_URL = 'https://plex.tv/link';

interface PlexLoginProps {
  onAuthenticated: () => void;
}

export default function PlexLogin({ onAuthenticated }: PlexLoginProps) {
  const [pin, setPin] = useState<{ id: number; code: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [polling, setPolling] = useState(false);
  const abortRef = useRef(false);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      abortRef.current = true;
    };
  }, []);

  // When app returns to foreground, log it
  useEffect(() => {
    const subscription = AppState.addEventListener('change', async (state: AppStateStatus) => {
      if (state === 'active' && pin && polling) {
        console.log('[PlexLogin] App foreground, polling continues...');
      }
    });
    return () => subscription.remove();
  }, [pin, polling]);

  const startAuth = async () => {
    try {
      console.log('[PlexLogin] Starting PIN auth flow');
      setBusy(true);
      abortRef.current = false;

      const core = getFlixorCore();
      const pinData = await core.createPlexPin();
      setPin(pinData);

      console.log('[PlexLogin] PIN created:', pinData.code, 'ID:', pinData.id);

      // Open plex.tv/link where user enters the code
      try {
        const WebBrowser = await import('expo-web-browser');
        await WebBrowser.openBrowserAsync(PLEX_LINK_URL);
        console.log('[PlexLogin] Browser closed');
      } catch {
        await RNLinking.openURL(PLEX_LINK_URL);
        console.log('[PlexLogin] Opened external browser');
      }

      // Start polling for authorization
      setPolling(true);
      setBusy(false);

      // Poll using the core's waitForPlexPin
      try {
        console.log('[PlexLogin] Waiting for PIN authorization...');
        await core.waitForPlexPin(pinData.id, {
          onPoll: () => {
            if (abortRef.current) {
              throw new Error('Aborted');
            }
            console.log('[PlexLogin] Polling PIN', pinData.id, '...');
          },
        });

        setPolling(false);
        console.log('[PlexLogin] Authentication successful!');
        onAuthenticated();
      } catch (e: any) {
        setPolling(false);
        if (e.message !== 'Aborted') {
          console.log('[PlexLogin] Auth error:', e?.message);
          Alert.alert('Timeout', 'Authentication timed out. Please try again.');
        }
      }

    } catch (e: any) {
      console.log('[PlexLogin] Error:', e?.message || e);
      Alert.alert('Login Error', e?.message || 'Failed to start authentication');
      setBusy(false);
      setPolling(false);
    }
  };

  const openPlexLink = () => {
    RNLinking.openURL(PLEX_LINK_URL);
  };

  return (
    <View style={{ flex: 1, backgroundColor: '#000', alignItems: 'center', justifyContent: 'center', padding: 24 }}>
      <Text style={{ color: '#fff', fontSize: 28, fontWeight: '800', marginBottom: 12 }}>
        Sign in with Plex
      </Text>

      <Text style={{ color: '#999', fontSize: 14, textAlign: 'center', marginBottom: 24, maxWidth: 300 }}>
        Connect your Plex account to access your media libraries
      </Text>

      {pin && (
        <View style={{ marginBottom: 24, alignItems: 'center' }}>
          <Text style={{ color: '#bbb', fontSize: 14, marginBottom: 4 }}>
            Go to plex.tv/link and enter:
          </Text>
          <Text style={{ color: '#fff', fontSize: 36, fontWeight: '800', letterSpacing: 6, marginVertical: 12 }}>
            {pin.code.toUpperCase()}
          </Text>
          {polling && (
            <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 8 }}>
              <ActivityIndicator color="#e50914" size="small" />
              <Text style={{ color: '#999', marginLeft: 8, fontSize: 12 }}>
                Waiting for authorization...
              </Text>
            </View>
          )}
        </View>
      )}

      <Pressable
        onPress={startAuth}
        disabled={busy || polling}
        style={{
          backgroundColor: busy || polling ? '#666' : '#e50914',
          paddingHorizontal: 24,
          paddingVertical: 14,
          borderRadius: 8,
          minWidth: 200,
          alignItems: 'center',
        }}
      >
        {busy ? (
          <ActivityIndicator color="#fff" />
        ) : (
          <Text style={{ color: '#fff', fontWeight: '700', fontSize: 16 }}>
            {pin ? 'Get New Code' : 'Continue with Plex'}
          </Text>
        )}
      </Pressable>

      {pin && (
        <Pressable onPress={openPlexLink} style={{ marginTop: 16 }}>
          <Text style={{ color: '#e50914', textDecorationLine: 'underline', fontWeight: '600' }}>
            Open plex.tv/link
          </Text>
        </Pressable>
      )}

      {!pin && (
        <Text style={{ color: '#666', fontSize: 12, marginTop: 24, textAlign: 'center', maxWidth: 280 }}>
          You'll be asked to enter a code at plex.tv/link to authorize this app.
        </Text>
      )}
    </View>
  );
}
