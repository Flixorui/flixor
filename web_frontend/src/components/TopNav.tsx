import { useEffect, useRef } from 'react';
import { Link } from 'react-router-dom';
import BottomTabBar from '@/components/nav/BottomTabBar';
import FloatingNav from '@/components/nav/FloatingNav';
import ServerMenu from '@/components/nav/ServerMenu';
import SidebarRail from '@/components/nav/SidebarRail';
import { useScrolled } from '@/components/nav/useScrolled';
import ProfileAvatar from '@/components/profile/ProfileAvatar';
import UserDropdown from '@/components/UserDropdown';
import { refreshPlexServers } from '@/services/plexServers';
import { useProfileSummary } from '@/services/profiles';
import { loadSettings, useSettings } from '@/state/settings';

// The logo stays Flixor red whatever accent is chosen, as on macOS.
const LOGO_CLASS = 'text-2xl font-extrabold tracking-tight text-[#E50914]';

export default function TopNav() {
  const { navigationStyle } = useSettings();
  const profile = useProfileSummary();
  const scrolled = useScrolled();
  const bandRef = useRef<HTMLDivElement>(null);
  const usesSidebar = navigationStyle === 'sidebar';

  useEffect(() => {
    if (!loadSettings().plexServers?.length) refreshPlexServers().catch(() => {});
  }, []);

  // The phone header keeps a fading band, since it has no pill to frost.
  useEffect(() => {
    const el = bandRef.current;
    if (!el) return;
    const onScroll = () => {
      const progress = Math.min(1, window.scrollY / 120);
      el.style.setProperty('--nav-bg-o', String(0.85 * progress));
      el.style.setProperty('--nav-blur', `${10 * progress}px`);
    };
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  const fadeWhenScrolled = `transition-opacity duration-300 ${scrolled ? 'opacity-0 pointer-events-none' : 'opacity-100'}`;

  return (
    <>
      {usesSidebar && <SidebarRail />}
      <header className={`fixed left-0 right-0 top-0 z-50 ${usesSidebar ? 'md:hidden' : ''}`}>
        <div ref={bandRef} className="relative h-14 md:h-16">
          <div className="nav-bg md:hidden" />
          <div className="page-gutter h-full flex items-center relative z-10">
            <Link
              to="/"
              className={`flex md:hidden lg:flex items-center transition-opacity duration-300 ${scrolled ? 'lg:opacity-0 lg:pointer-events-none' : ''} ${LOGO_CLASS}`}
            >
              FLIXOR
            </Link>

            <div className="hidden md:block absolute left-1/2 -translate-x-1/2 top-2">
              <FloatingNav />
            </div>

            <div className="ml-auto flex items-center">
              <div className={`hidden lg:block ${fadeWhenScrolled}`}>
                <ServerMenu />
              </div>
              <div className="md:hidden">
                <UserDropdown placement="below">
                  {(toggle) => (
                    <button type="button" onClick={toggle} aria-label={`Profile: ${profile.name}`} className="flex">
                      <ProfileAvatar name={profile.name} thumb={profile.thumb} size={32} />
                    </button>
                  )}
                </UserDropdown>
              </div>
            </div>
          </div>
        </div>
      </header>
      <BottomTabBar />
    </>
  );
}
