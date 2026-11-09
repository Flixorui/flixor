import { useCallback, useMemo } from 'react';
import { useLocation, useNavigate, useParams } from 'react-router-dom';
import type { PlexConfig } from '@/services/plex';
import { useSettings } from '@/state/settings';
import type { StreamPlayerState, StremioContentIdentity } from '@/stremio';
import PlayerErrorScreen from '@/player/PlayerErrorScreen';
import PlayerShell, { usePlayerClock } from '@/player/PlayerShell';
import { detailsPath, parsePlayerId, playerPath, streamPlayerId } from '@/player/playerId';
import { usePlexSession } from '@/player/sessions/usePlexSession';
import { useStreamSession } from '@/player/sessions/useStreamSession';

function PlexPlayer({ plexConfig, ratingKey }: { plexConfig: PlexConfig; ratingKey: string }) {
  const nav = useNavigate();
  const clock = usePlayerClock();
  const onPlayItem = useCallback((next: string) => nav(playerPath(`plex:${next}`)), [nav]);
  const onNavigate = useCallback((path: string) => nav(path), [nav]);
  const onBack = useCallback(() => nav(-1), [nav]);
  const session = usePlexSession({ plexConfig, itemId: ratingKey, clock, onPlayItem, onNavigate, onBack });
  return <PlayerShell session={session} clock={clock} />;
}

function StreamPlayer({ identity, state }: { identity: StremioContentIdentity; state: StreamPlayerState | null }) {
  const nav = useNavigate();
  const clock = usePlayerClock();
  const onPlayStream = useCallback((next: StreamPlayerState) => {
    nav(playerPath(streamPlayerId(next.identity)), { state: next, replace: true });
  }, [nav]);
  const onBack = useCallback(() => nav(-1), [nav]);
  const session = useStreamSession({ identity, initialState: state, clock, onPlayStream, onBack });
  return <PlayerShell session={session} clock={clock} />;
}

function streamStateFrom(value: unknown): StreamPlayerState | null {
  const state = value as Partial<StreamPlayerState> | null;
  return state?.stream && state.identity ? (state as StreamPlayerState) : null;
}

export default function Player() {
  const { id = '' } = useParams();
  const location = useLocation();
  const { plexBaseUrl, plexToken } = useSettings();
  const target = useMemo(() => parsePlayerId(id), [id]);
  const plexConfig = useMemo<PlexConfig | null>(
    () => (plexBaseUrl && plexToken ? { baseUrl: plexBaseUrl, token: plexToken } : null),
    [plexBaseUrl, plexToken],
  );

  if (target.kind === 'plex') {
    if (!plexConfig) {
      return (
        <PlayerErrorScreen
          message="Connect a Plex server to play this title."
          action={{ label: 'Open Settings', to: '/settings' }}
        />
      );
    }
    return <PlexPlayer key={target.ratingKey} plexConfig={plexConfig} ratingKey={target.ratingKey} />;
  }

  if (target.kind === 'stream') {
    const state = streamStateFrom(location.state);
    return <StreamPlayer key={target.requestId} identity={state?.identity ?? target.identity} state={state} />;
  }

  return (
    <PlayerErrorScreen
      message="This title isn't in your Plex library, so there's nothing to play yet. Open its details to find a way to watch it."
      action={{ label: 'View details', to: detailsPath(target.id) }}
    />
  );
}
