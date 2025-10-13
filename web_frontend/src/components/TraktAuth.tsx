import { useState, useEffect, useRef } from 'react';
import {
  traktRequestDeviceCode,
  traktPollForToken,
  saveTraktTokens,
  getTraktTokens,
  traktGetUserProfile,
  traktRevokeToken,
  ensureValidToken,
  TraktUser
} from '@/services/trakt';

interface TraktAuthProps {
  onAuthComplete?: () => void;
  onAuthError?: (error: string) => void;
}

export function TraktAuth({ onAuthComplete, onAuthError }: TraktAuthProps) {
  const [isAuthenticating, setIsAuthenticating] = useState(false);
  const [deviceCode, setDeviceCode] = useState<{
    user_code: string;
    verification_url: string;
    expires_in: number;
    interval: number;
    device_code: string;
  } | null>(null);
  const [userProfile, setUserProfile] = useState<TraktUser | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [pollCountdown, setPollCountdown] = useState(0);
  const pollIntervalRef = useRef<NodeJS.Timeout | null>(null);
  const countdownRef = useRef<NodeJS.Timeout | null>(null);

  useEffect(() => {
    checkExistingAuth();
    return () => {
      if (pollIntervalRef.current) clearInterval(pollIntervalRef.current);
      if (countdownRef.current) clearInterval(countdownRef.current);
    };
  }, []);

  const checkExistingAuth = async () => {
    try {
      const token = await ensureValidToken();
      if (token) {
        const profile = await traktGetUserProfile(token);
        setUserProfile(profile);
      }
    } catch (err) {
      console.error('Failed to check existing auth:', err);
    } finally {
      setIsLoading(false);
    }
  };

  const startAuth = async () => {
    try {
      setIsAuthenticating(true);
      setError(null);

      const code = await traktRequestDeviceCode();
      setDeviceCode(code);
      setPollCountdown(code.expires_in);

      // Start countdown
      countdownRef.current = setInterval(() => {
        setPollCountdown((prev) => {
          if (prev <= 1) {
            if (countdownRef.current) clearInterval(countdownRef.current);
            return 0;
          }
          return prev - 1;
        });
      }, 1000);

      // Start polling for token
      pollIntervalRef.current = setInterval(async () => {
        try {
          const tokens = await traktPollForToken(code.device_code);
          if (tokens) {
            // Success! Persist locally; backend already stored tokens server-side.
            saveTraktTokens(tokens);
            if (pollIntervalRef.current) clearInterval(pollIntervalRef.current);
            if (countdownRef.current) clearInterval(countdownRef.current);

            try {
              const profile = await traktGetUserProfile(tokens.access_token);
              setUserProfile(profile);
            } catch (e) {
              // Don’t block completion if profile fetch races token persistence
              console.warn('Trakt profile fetch after auth failed; will rely on subsequent checks.', e);
            } finally {
              setIsAuthenticating(false);
              setDeviceCode(null);
              if (onAuthComplete) onAuthComplete();
            }
          }
        } catch (err: any) {
          console.error('Poll error:', err);
          if (err.message?.includes('expired')) {
            if (pollIntervalRef.current) clearInterval(pollIntervalRef.current);
            if (countdownRef.current) clearInterval(countdownRef.current);
            setError('Device code expired. Please try again.');
            setIsAuthenticating(false);
            setDeviceCode(null);
          }
        }
      }, code.interval * 1000);

      // Auto-cancel after expiry
      setTimeout(() => {
        if (pollIntervalRef.current) {
          clearInterval(pollIntervalRef.current);
          clearInterval(countdownRef.current!);
          setError('Authentication timed out. Please try again.');
          setIsAuthenticating(false);
          setDeviceCode(null);
        }
      }, code.expires_in * 1000);
    } catch (err: any) {
      setError(err.message || 'Failed to start authentication');
      setIsAuthenticating(false);
      if (onAuthError) onAuthError(err.message);
    }
  };

  const cancelAuth = () => {
    if (pollIntervalRef.current) clearInterval(pollIntervalRef.current);
    if (countdownRef.current) clearInterval(countdownRef.current);
    setIsAuthenticating(false);
    setDeviceCode(null);
    setError(null);
  };

  const logout = async () => {
    try {
      const token = await ensureValidToken();
      if (token) {
        await traktRevokeToken(token);
      }
    } catch (err) {
      console.error('Failed to revoke token:', err);
    } finally {
      saveTraktTokens(null);
      setUserProfile(null);
    }
  };

  const copyCode = () => {
    if (deviceCode) {
      navigator.clipboard.writeText(deviceCode.user_code);
    }
  };

  const openVerificationUrl = () => {
    if (deviceCode) {
      window.open(deviceCode.verification_url, '_blank');
    }
  };

  if (isLoading) {
    return (
      <div className="bg-gray-800 rounded-lg p-6 animate-pulse">
        <div className="h-8 bg-gray-700 rounded w-1/3 mb-4"></div>
        <div className="h-4 bg-gray-700 rounded w-2/3"></div>
      </div>
    );
  }

  if (userProfile) {
    return (
      <div className="bg-gray-800 rounded-lg p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-xl font-semibold">Trakt Connected</h3>
          <button
            onClick={logout}
            className="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700 transition"
          >
            Disconnect
          </button>
        </div>
        <div className="flex items-center space-x-4">
          {userProfile.images?.avatar?.full && (
            <img
              src={userProfile.images.avatar.full}
              alt={userProfile.username}
              className="w-16 h-16 rounded-full"
            />
          )}
          <div>
            <p className="text-lg font-medium">{userProfile.name || userProfile.username}</p>
            <p className="text-gray-400">@{userProfile.username}</p>
            {userProfile.vip && (
              <span className="inline-block mt-1 px-2 py-1 bg-yellow-600 text-xs rounded">
                VIP Member
              </span>
            )}
          </div>
        </div>
      </div>
    );
  }

  if (isAuthenticating && deviceCode) {
    return (
      <div className="bg-gray-800 rounded-lg p-6">
        <h3 className="text-xl font-semibold mb-4">Connect to Trakt</h3>

        <div className="space-y-4">
          <div>
            <p className="text-gray-300 mb-2">1. Visit this URL:</p>
            <button
              onClick={openVerificationUrl}
              className="w-full px-4 py-3 bg-blue-600 text-white rounded hover:bg-blue-700 transition text-center font-medium"
            >
              {deviceCode.verification_url}
            </button>
          </div>

          <div>
            <p className="text-gray-300 mb-2">2. Enter this code:</p>
            <div className="flex space-x-2">
              <div className="flex-1 px-4 py-3 bg-gray-900 rounded text-center text-2xl font-mono font-bold tracking-widest">
                {deviceCode.user_code}
              </div>
              <button
                onClick={copyCode}
                className="px-4 py-3 bg-gray-700 text-white rounded hover:bg-gray-600 transition"
              >
                Copy
              </button>
            </div>
          </div>

          <div className="text-center">
            <p className="text-gray-400">
              Waiting for authorization... ({pollCountdown}s remaining)
            </p>
            <div className="w-full bg-gray-700 rounded-full h-2 mt-2">
              <div
                className="bg-blue-600 h-2 rounded-full transition-all duration-1000"
                style={{
                  width: `${(pollCountdown / (deviceCode.expires_in || 600)) * 100}%`
                }}
              ></div>
            </div>
          </div>

          <button
            onClick={cancelAuth}
            className="w-full px-4 py-2 bg-gray-700 text-white rounded hover:bg-gray-600 transition"
          >
            Cancel
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-gray-800 rounded-lg p-6">
      <h3 className="text-xl font-semibold mb-4">Connect to Trakt</h3>
      {error && (
        <div className="mb-4 p-3 bg-red-900/50 border border-red-700 rounded text-red-300">
          {error}
        </div>
      )}
      <p className="text-gray-300 mb-4">
        Connect your Trakt account to sync your watch history, track progress, and get personalized recommendations.
      </p>
      <button
        onClick={startAuth}
        disabled={isAuthenticating}
        className="px-6 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 transition disabled:opacity-50"
      >
        Connect Trakt Account
      </button>
    </div>
  );
}
