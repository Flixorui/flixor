import { useEffect, useRef, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { PlexUserProfile, PlexUser, loadSettings, saveSettings } from '@/state/settings';
import { apiClient, getCurrentUser } from '@/services/api';
import { forget } from '@/services/cache';

export default function UserDropdown() {
  const nav = useNavigate();
  const [isOpen, setIsOpen] = useState(false);
  const [profile, setProfile] = useState<PlexUserProfile | null>(null);
  const [users, setUsers] = useState<PlexUser[]>([]);
  const [loading, setLoading] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);
  const timeoutRef = useRef<NodeJS.Timeout | null>(null);

  useEffect(() => {
    loadUserProfile();
  }, []);

  async function loadUserProfile() {
    try {
      setLoading(true);
      // Get user from backend session
      const user = await getCurrentUser();

      if (user) {
        const profileData: PlexUserProfile = {
          id: user.id,
          username: user.username || 'User',
          email: user.email || '',
          thumb: user.thumb,
          title: user.username,
          hasPassword: true,
          subscription: user.subscription
        };
        setProfile(profileData);
      }
    } catch (err) {
      console.error('Failed to load user profile:', err);
    } finally {
      setLoading(false);
    }
  }

  function handleMouseEnter() {
    if (timeoutRef.current) clearTimeout(timeoutRef.current);
    setIsOpen(true);
  }

  function handleMouseLeave() {
    timeoutRef.current = setTimeout(() => {
      setIsOpen(false);
    }, 300);
  }

  async function handleSignOut() {
    try {
      // Logout from backend
      await apiClient.logout();

      // Clear local storage
      saveSettings({
        plexAccountToken: undefined,
        plexTvToken: undefined,
        plexToken: undefined,
        plexBaseUrl: undefined,
        plexUserProfile: undefined,
        plexUsers: undefined,
        plexServer: undefined,
        plexServers: undefined
      });

      // Clear cache
      forget('plex:');

      // Navigate to login
      nav('/login');
    } catch (err) {
      console.error('Failed to logout:', err);
      // Navigate to login anyway
      nav('/login');
    }
  }

  function switchUser(user: PlexUser) {
    // For now, just update the current user ID
    // Full user switching would require additional auth flow
    saveSettings({ plexCurrentUserId: user.id });
    setIsOpen(false);
    window.location.reload();
  }

  const avatarUrl = profile?.thumb || '';
  const displayName = profile?.username || profile?.title || 'User';
  const displayInitial = displayName.charAt(0).toUpperCase();

  return (
    <div
      className="relative"
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
      ref={dropdownRef}
    >
      {/* Avatar trigger */}
      <button className="relative group">
        {avatarUrl ? (
          <img
            src={avatarUrl}
            alt={displayName}
            className="w-8 h-8 rounded-md object-cover"
            onError={(e) => {
              // Fallback to initials on error
              e.currentTarget.style.display = 'none';
              e.currentTarget.nextElementSibling?.classList.remove('hidden');
            }}
          />
        ) : null}
        <div
          className={`w-8 h-8 rounded-md bg-gradient-to-br from-red-500 to-orange-400 flex items-center justify-center text-white font-semibold text-sm ${avatarUrl ? 'hidden' : ''}`}
        >
          {displayInitial}
        </div>

        {/* Dropdown caret */}
        <svg
          className={`absolute -bottom-1 left-1/2 -translate-x-1/2 w-0 h-0 transition-opacity duration-200 ${isOpen ? 'opacity-100' : 'opacity-0'}`}
          style={{
            borderLeft: '5px solid transparent',
            borderRight: '5px solid transparent',
            borderTop: '5px solid white',
            filter: 'drop-shadow(0 2px 4px rgba(0,0,0,0.5))'
          }}
        />
      </button>

      {/* Dropdown menu */}
      <div
        className={`absolute right-0 mt-3 w-64 bg-black/95 backdrop-blur-sm rounded-md shadow-xl transition-all duration-200 ${
          isOpen ? 'opacity-100 translate-y-0 visible' : 'opacity-0 -translate-y-2 invisible'
        }`}
        style={{
          border: '1px solid rgba(255,255,255,0.1)',
          boxShadow: '0 10px 40px rgba(0,0,0,0.8)'
        }}
      >
        {/* Profile Section */}
        <div className="p-4 border-b border-white/10">
          {loading ? (
            <div className="animate-pulse">
              <div className="h-4 bg-white/10 rounded w-24 mb-2"></div>
              <div className="h-3 bg-white/10 rounded w-32"></div>
            </div>
          ) : (
            <div className="flex items-center gap-3">
              {avatarUrl ? (
                <img
                  src={avatarUrl}
                  alt={displayName}
                  className="w-12 h-12 rounded-md object-cover"
                />
              ) : (
                <div className="w-12 h-12 rounded-md bg-gradient-to-br from-red-500 to-orange-400 flex items-center justify-center text-white font-bold text-lg">
                  {displayInitial}
                </div>
              )}
              <div>
                <div className="text-white font-medium">{displayName}</div>
                {profile?.email && (
                  <div className="text-xs text-gray-400">{profile.email}</div>
                )}
              </div>
            </div>
          )}
        </div>

        {/* User profiles */}
        {users.length > 0 && (
          <div className="p-2 border-b border-white/10">
            {users.slice(0, 4).map((user) => (
              <button
                key={user.id}
                onClick={() => switchUser(user)}
                className="w-full flex items-center gap-3 px-2 py-2 rounded hover:bg-white/10 transition-colors"
              >
                {user.thumb ? (
                  <img
                    src={user.thumb}
                    alt={user.username}
                    className="w-8 h-8 rounded object-cover"
                  />
                ) : (
                  <div className="w-8 h-8 rounded bg-gradient-to-br from-blue-500 to-purple-500 flex items-center justify-center text-white text-xs font-semibold">
                    {user.username.charAt(0).toUpperCase()}
                  </div>
                )}
                <span className="text-sm text-gray-300">{user.username}</span>
              </button>
            ))}

            {/* Add Profile */}
            <button
              onClick={() => nav('/settings')}
              className="w-full flex items-center gap-3 px-2 py-2 rounded hover:bg-white/10 transition-colors"
            >
              <div className="w-8 h-8 rounded bg-gray-700 flex items-center justify-center">
                <svg className="w-4 h-4 text-gray-400" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M12 4a1 1 0 011 1v6h6a1 1 0 110 2h-6v6a1 1 0 11-2 0v-6H5a1 1 0 110-2h6V5a1 1 0 011-1z"/>
                </svg>
              </div>
              <span className="text-sm text-gray-300">Add Profile</span>
            </button>
          </div>
        )}

        {/* Menu items */}
        <div className="p-2">
          <Link
            to="/settings"
            className="block px-3 py-2 text-sm text-gray-300 hover:text-white hover:bg-white/10 rounded transition-colors"
            onClick={() => setIsOpen(false)}
          >
            Edit Profiles
          </Link>

          <Link
            to="/settings"
            className="block px-3 py-2 text-sm text-gray-300 hover:text-white hover:bg-white/10 rounded transition-colors"
            onClick={() => setIsOpen(false)}
          >
            App Settings
          </Link>

          <a
            href="https://app.plex.tv/desktop/#!/settings/account"
            target="_blank"
            rel="noopener noreferrer"
            className="block px-3 py-2 text-sm text-gray-300 hover:text-white hover:bg-white/10 rounded transition-colors"
          >
            Account
          </a>

          <a
            href="https://support.plex.tv"
            target="_blank"
            rel="noopener noreferrer"
            className="block px-3 py-2 text-sm text-gray-300 hover:text-white hover:bg-white/10 rounded transition-colors"
          >
            Help
          </a>
        </div>

        {/* Sign out */}
        <div className="p-2 border-t border-white/10">
          <button
            onClick={handleSignOut}
            className="w-full text-left px-3 py-2 text-sm text-gray-300 hover:text-white hover:bg-white/10 rounded transition-colors"
          >
            Sign Out
          </button>
        </div>
      </div>
    </div>
  );
}