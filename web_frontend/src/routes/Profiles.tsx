import { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import PinEntryModal from '@/components/profile/PinEntryModal';
import ProfileAvatar from '@/components/profile/ProfileAvatar';
import { fetchHomeProfiles, type HomeProfile, ProfileSwitchError, switchProfile } from '@/services/profiles';

export default function Profiles() {
  const navigate = useNavigate();
  const [users, setUsers] = useState<HomeProfile[] | null>(null);
  const [activeUuid, setActiveUuid] = useState<string | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [pinFor, setPinFor] = useState<HomeProfile | null>(null);
  const [switching, setSwitching] = useState<string | null>(null);
  const [pinError, setPinError] = useState<string | null>(null);
  const [switchError, setSwitchError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoadError(null);
    setUsers(null);
    try {
      const result = await fetchHomeProfiles();
      setUsers(result.users);
      setActiveUuid(result.activeUuid);
    } catch {
      setLoadError('Could not load your Plex Home profiles.');
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  async function attempt(profile: HomeProfile, pin?: string) {
    setSwitching(profile.uuid);
    setPinError(null);
    setSwitchError(null);
    try {
      await switchProfile(profile.uuid, pin);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Could not switch profiles';
      const code = error instanceof ProfileSwitchError ? error.code : '';
      if (code === 'pin_required') {
        setPinFor(profile);
      } else if (code === 'invalid_pin' || code === 'pin_locked') {
        setPinError(message);
      } else {
        setPinFor(null);
        setSwitchError(message);
      }
      setSwitching(null);
    }
  }

  function select(profile: HomeProfile) {
    if (switching) return;
    if (profile.uuid === activeUuid) {
      navigate('/');
      return;
    }
    if (profile.protected) {
      setPinError(null);
      setPinFor(profile);
    } else {
      attempt(profile);
    }
  }

  return (
    <div className="min-h-screen flex flex-col items-center px-6 pt-20 pb-12">
      <h1 className="text-white text-3xl md:text-4xl font-bold">Who's watching?</h1>
      <p className="mt-2 text-neutral-400 text-sm">Each profile keeps its own settings and watch history</p>

      <div className="flex-1 w-full flex items-center justify-center py-10">
        {loadError ? (
          <div className="text-center">
            <p className="text-neutral-300 text-sm">{loadError}</p>
            <button onClick={load} className="btn mt-4">
              Try Again
            </button>
          </div>
        ) : users === null ? (
          <div className="flex flex-wrap justify-center gap-8" aria-label="Loading profiles">
            {[0, 1, 2].map((i) => (
              <div key={i} className="skeleton w-28 h-28 rounded-full" />
            ))}
          </div>
        ) : users.length === 0 ? (
          <p className="text-neutral-400 text-sm text-center max-w-sm">
            This account is not part of a Plex Home, so there are no other profiles to switch to.
          </p>
        ) : (
          <ul className="flex flex-wrap justify-center gap-8 max-w-3xl">
            {users.map((user) => {
              const active = user.uuid === activeUuid;
              return (
                <li key={user.uuid}>
                  <button
                    type="button"
                    onClick={() => select(user)}
                    disabled={switching !== null}
                    aria-label={`${user.title}${user.protected ? ', PIN protected' : ''}${active ? ', current profile' : ''}`}
                    className="group w-32 flex flex-col items-center gap-3 disabled:cursor-wait"
                  >
                    <span className="relative transition-transform group-hover:scale-105 motion-reduce:transform-none">
                      <ProfileAvatar name={user.title} thumb={user.thumb} size={112} ring={active} />
                      {user.protected && (
                        <span className="absolute bottom-0 right-0 w-8 h-8 rounded-full bg-neutral-800 ring-2 ring-black flex items-center justify-center">
                          <svg width="14" height="14" viewBox="0 0 24 24" fill="#e5e7eb" aria-hidden="true">
                            <path d="M17 9h-1V7a4 4 0 0 0-8 0v2H7a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-9a2 2 0 0 0-2-2Zm-7-2a2 2 0 1 1 4 0v2h-4V7Z" />
                          </svg>
                        </span>
                      )}
                    </span>
                    <span className={`text-sm font-medium truncate max-w-full ${active ? 'text-white' : 'text-neutral-300 group-hover:text-white'}`}>
                      {switching === user.uuid ? 'Switching...' : user.title}
                    </span>
                    {user.restricted && <span className="text-[11px] text-neutral-500 -mt-2">Restricted</span>}
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </div>

      {switchError && (
        <p role="alert" className="mb-4 text-sm text-red-400 text-center">
          {switchError}
        </p>
      )}
      <button onClick={() => navigate(-1)} className="btn">
        Cancel
      </button>

      {pinFor && (
        <PinEntryModal
          profile={pinFor}
          submitting={switching !== null}
          error={pinError}
          onSubmit={(pin) => attempt(pinFor, pin)}
          onCancel={() => setPinFor(null)}
        />
      )}
    </div>
  );
}
