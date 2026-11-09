import { useEffect, useRef, useState } from 'react';
import ProfileAvatar from '@/components/profile/ProfileAvatar';
import type { HomeProfile } from '@/services/profiles';

const PIN_LENGTH = 4;
const KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9'];

type PinEntryModalProps = {
  profile: HomeProfile;
  submitting: boolean;
  error: string | null;
  onSubmit: (pin: string) => void;
  onCancel: () => void;
};

export default function PinEntryModal({ profile, submitting, error, onSubmit, onCancel }: PinEntryModalProps) {
  const [pin, setPin] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  // A wrong PIN clears the dots so the next attempt starts fresh.
  useEffect(() => {
    if (error) {
      setPin('');
      inputRef.current?.focus();
    }
  }, [error]);

  function update(next: string) {
    if (submitting) return;
    const digits = next.replace(/\D/g, '').slice(0, PIN_LENGTH);
    setPin(digits);
    if (digits.length === PIN_LENGTH) onSubmit(digits);
  }

  const keyClass =
    'h-14 rounded-full bg-white/10 hover:bg-white/20 active:bg-white/25 text-white text-xl font-semibold transition-colors disabled:opacity-40';

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={`Enter PIN for ${profile.title}`}
      className="fixed inset-0 z-[120] flex items-center justify-center bg-black/80 backdrop-blur-sm p-4"
      onKeyDown={(e) => {
        if (e.key === 'Escape') onCancel();
      }}
    >
      <div className="w-full max-w-xs rounded-3xl bg-neutral-900 ring-1 ring-white/10 p-6 flex flex-col items-center">
        <ProfileAvatar name={profile.title} thumb={profile.thumb} size={72} />
        <h2 className="mt-4 text-white text-lg font-semibold text-center">Enter PIN for {profile.title}</h2>
        <p className="mt-1 text-[13px] text-neutral-400">This profile is protected with a PIN</p>

        <input
          ref={inputRef}
          value={pin}
          onChange={(e) => update(e.target.value)}
          type="password"
          inputMode="numeric"
          autoComplete="off"
          aria-label="PIN"
          className="sr-only"
        />

        <div className="flex gap-4 my-6" aria-hidden="true" onClick={() => inputRef.current?.focus()}>
          {Array.from({ length: PIN_LENGTH }, (_, i) => (
            <span
              key={i}
              className={`w-3.5 h-3.5 rounded-full transition-colors ${i < pin.length ? 'bg-white' : 'bg-white/20'}`}
            />
          ))}
        </div>

        <p role="alert" className="min-h-5 mb-3 text-[13px] text-red-400 text-center">
          {error}
        </p>

        <div className="grid grid-cols-3 gap-3 w-full">
          {KEYS.map((key) => (
            <button key={key} type="button" className={keyClass} disabled={submitting} onClick={() => update(pin + key)}>
              {key}
            </button>
          ))}
          <span />
          <button type="button" className={keyClass} disabled={submitting} onClick={() => update(pin + '0')}>
            0
          </button>
          <button
            type="button"
            aria-label="Delete"
            className={keyClass}
            disabled={submitting || pin.length === 0}
            onClick={() => update(pin.slice(0, -1))}
          >
            &#9003;
          </button>
        </div>

        <button
          type="button"
          onClick={onCancel}
          className="mt-5 text-sm text-neutral-400 hover:text-white transition-colors"
        >
          Cancel
        </button>
      </div>
    </div>
  );
}
