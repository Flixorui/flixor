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
import { useTheme } from '../hooks/useTheme';

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
  const theme = useTheme();
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
          <ActivityIndicator color={theme.textPrimary} size="large" />
          <Text style={{ color: '#999', marginTop: 12, fontSize: 14 }}>
            Waiting for authorization…
          </Text>
          <Text style={{ color: '#666', marginTop: 4, fontSize: 12 }}>
            Complete sign-in in your browser
          </Text>
          {/* A way out if the browser was closed before signing in */}
          <View style={{ flexDirection: 'row', gap: 10, marginTop: 24 }}>
            <Pressable
              onPress={() => {
                if (!pin) return;
                const url = buildPlexAuthUrl(getFlixorCore().getClientId(), pin.code);
                RNLinking.openURL(url).catch(() => undefined);
              }}
              accessibilityRole="button"
              style={{ backgroundColor: 'rgba(255,255,255,0.12)', paddingHorizontal: 18, height: 44, borderRadius: 12, justifyContent: 'center' }}
            >
              <Text style={{ color: '#fff', fontWeight: '600', fontSize: 15 }}>Open Browser Again</Text>
            </Pressable>
            <Pressable
              onPress={() => {
                abortRef.current = true;
                setPolling(false);
                setPin(null);
              }}
              accessibilityRole="button"
              style={{ backgroundColor: 'rgba(255,255,255,0.12)', paddingHorizontal: 18, height: 44, borderRadius: 12, justifyContent: 'center' }}
            >
              <Text style={{ color: '#fff', fontWeight: '600', fontSize: 15 }}>Cancel</Text>
            </Pressable>
          </View>
        </View>
      )}

      {!polling && (
        <Pressable
          onPress={startAuth}
          disabled={busy}
          style={{
            // White primary button (macOS rule: red is only for switches and progress)
            backgroundColor: busy ? 'rgba(255,255,255,0.6)' : '#fff',
            paddingHorizontal: 24,
            height: 50,
            justifyContent: 'center',
            borderRadius: 12,
            minWidth: 200,
            alignItems: 'center',
          }}
        >
          {busy ? (
            <ActivityIndicator color="#000" />
          ) : (
            <Text style={{ color: '#000', fontWeight: '600', fontSize: 17 }}>
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
