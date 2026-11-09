import { type ReactNode, useEffect, useRef, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import ProfileAvatar from '@/components/profile/ProfileAvatar';
import { signOut, useProfileSummary } from '@/services/profiles';
import { showToast } from '@/services/toast';

type UserDropdownProps = {
  /** Where the menu opens from its trigger. */
  placement: 'below' | 'beside';
  onOpenChange?: (open: boolean) => void;
  children: (toggle: () => void, open: boolean) => ReactNode;
};

/** Profile menu: who is signed in, switch profile, settings, sign out. */
export default function UserDropdown({ placement, onOpenChange, children }: UserDropdownProps) {
  const navigate = useNavigate();
  const profile = useProfileSummary();
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const openChange = useRef(onOpenChange);
  openChange.current = onOpenChange;

  useEffect(() => {
    openChange.current?.(open);
    if (!open) return;
    const onPointerDown = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setOpen(false);
    };
    document.addEventListener('pointerdown', onPointerDown);
    document.addEventListener('keydown', onKeyDown);
    return () => {
      document.removeEventListener('pointerdown', onPointerDown);
      document.removeEventListener('keydown', onKeyDown);
    };
  }, [open]);

  const rowClass =
    'w-full flex items-center px-3 py-2 text-sm text-neutral-200 hover:text-white hover:bg-white/10 rounded-lg transition-colors text-left';
  const position = placement === 'below' ? 'right-0 top-full mt-3' : 'left-full bottom-0 ml-3';

  async function handleSignOut() {
    setOpen(false);
    try {
      await signOut();
    } catch {
      showToast('Could not sign out. Try again.', 'error');
    }
  }

  return (
    <div className="relative" ref={rootRef}>
      {children(() => setOpen((v) => !v), open)}
      {open && (
        <div role="menu" className={`absolute ${position} w-56 z-50 rounded-xl bg-neutral-900/95 ring-1 ring-white/10 shadow-2xl p-1.5`}>
          <div className="flex items-center gap-3 px-3 py-2">
            <ProfileAvatar name={profile.name} thumb={profile.thumb} size={32} />
            <span className="text-sm font-semibold text-white truncate">{profile.name}</span>
          </div>
          <div className="my-1 h-px bg-white/10" />
          {profile.canSwitch && (
            <>
              <button
                role="menuitem"
                className={rowClass}
                onClick={() => {
                  setOpen(false);
                  navigate('/profiles');
                }}
              >
                Switch Profile
              </button>
              <div className="my-1 h-px bg-white/10" />
            </>
          )}
          <Link role="menuitem" to="/settings" className={rowClass} onClick={() => setOpen(false)}>
            Settings
          </Link>
          <div className="my-1 h-px bg-white/10" />
          <button role="menuitem" className={`${rowClass} text-red-400 hover:text-red-300`} onClick={handleSignOut}>
            Sign Out
          </button>
        </div>
      )}
    </div>
  );
}
