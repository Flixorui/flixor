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

/**
 * Build the Plex auth URL with clientId and PIN code pre-filled
 * This opens directly to the auth page without requiring manual PIN entry
 */
function buildPlexAuthUrl(clientId: string, pinCode: string): string {
  return `https://app.plex.tv/auth#?clientID=${clientId}&code=${pinCode}&context%5Bdevice%5D%5Bproduct%5D=Flixor`;
}

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
      const clientId = core.getClientId();
      setPin(pinData);

      console.log('[PlexLogin] PIN created:', pinData.code, 'ID:', pinData.id);

      // Build auth URL with clientId and PIN pre-filled (no manual entry needed)
      const authUrl = buildPlexAuthUrl(clientId, pinData.code);
      console.log('[PlexLogin] Opening auth URL:', authUrl);

      // Open Plex auth page with code pre-filled
      try {
        const WebBrowser = await import('expo-web-browser');
        await WebBrowser.openBrowserAsync(authUrl);
        console.log('[PlexLogin] Browser closed');
      } catch {
        await RNLinking.openURL(authUrl);
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

  return (
    <View style={{ flex: 1, backgroundColor: '#000', alignItems: 'center', justifyContent: 'center', padding: 24 }}>
      <Text style={{ color: '#fff', fontSize: 28, fontWeight: '800', marginBottom: 12 }}>
        Sign in with Plex
      </Text>

      <Text style={{ color: '#999', fontSize: 14, textAlign: 'center', marginBottom: 24, maxWidth: 300 }}>
        Connect your Plex account to access your media libraries
      </Text>

      {polling && (
        <View style={{ marginBottom: 24, alignItems: 'center' }}>
          <ActivityIndicator color="#e50914" size="large" />
          <Text style={{ color: '#999', marginTop: 12, fontSize: 14 }}>
            Waiting for authorization...
          </Text>
          <Text style={{ color: '#666', marginTop: 4, fontSize: 12 }}>
            Complete sign-in in your browser
          </Text>
        </View>
      )}

      {!polling && (
        <Pressable
          onPress={startAuth}
          disabled={busy}
          style={{
            backgroundColor: busy ? '#666' : '#e50914',
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
              Sign in with Plex
            </Text>
          )}
        </Pressable>
      )}

      {!polling && (
        <Text style={{ color: '#666', fontSize: 12, marginTop: 24, textAlign: 'center', maxWidth: 280 }}>
          You'll be redirected to Plex to authorize this app.
        </Text>
      )}
    </View>
  );
}
