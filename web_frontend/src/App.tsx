import { Outlet, useLocation, useNavigate } from 'react-router-dom';
import { useEffect } from 'react';
import TopNav from '@/components/TopNav';
import GlobalToast from '@/components/GlobalToast';
import UpdateNotification from '@/components/UpdateNotification';
import NetworkStatusBanner from '@/components/NetworkStatusBanner';
import { checkTraktConnection } from '@/services/traktConnection';
import { loadSettings, useSettings } from '@/state/settings';
import { ensureAccountSynced } from '@/services/accountSync';

export default function App() {
  const location = useLocation();
  const navigate = useNavigate();
  const isPlayerRoute = location.pathname.startsWith('/player/');
  const isDetailsRoute = location.pathname.includes('/details/');
  const isHome = location.pathname === '/';
  const isAuthRoute = location.pathname.startsWith('/login');
  const isOnboardingRoute = location.pathname === '/onboarding';
  const isProfilesRoute = location.pathname === '/profiles';
  const { navigationStyle, navigationSidebarPinned } = useSettings();

  // Check onboarding status on mount. A new browser first loads the account's
  // settings, so an account that finished setup elsewhere skips it here.
  useEffect(() => {
    if (isOnboardingRoute || isAuthRoute) return;
    let cancelled = false;
    ensureAccountSynced().then(() => {
      if (cancelled) return;
      const settings = loadSettings();
      const isAuthenticated = !!(settings.plexBaseUrl && settings.plexToken) || !!settings.plexServer;
      if (isAuthenticated && !settings.hasCompletedOnboarding) navigate('/onboarding');
    });
    return () => {
      cancelled = true;
    };
  }, [navigate, isOnboardingRoute, isAuthRoute]);

  useEffect(() => {
    if (!isAuthRoute) checkTraktConnection();
    // Once per signed-in app load.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isAuthRoute]);

  // Global keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Cmd+K or Ctrl+K for search
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault();
        navigate('/search');
      }
      // ESC to go back from search
      if (e.key === 'Escape' && location.pathname === '/search') {
        e.preventDefault();
        navigate(-1);
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [navigate, location]);

  const showsNav = !isPlayerRoute && !isAuthRoute && !isOnboardingRoute && !isProfilesRoute;

  return (
    <div className="min-h-screen flex flex-col">
      {/* Global fixed background layer */}
      <div className="app-bg-fixed bg-home-gradient" />
      <GlobalToast />
      {!isPlayerRoute && <NetworkStatusBanner />}
      {!isPlayerRoute && !isOnboardingRoute && <UpdateNotification />}
      {showsNav && <TopNav />}
      <main
        data-pinned={navigationSidebarPinned}
        className={`flex-1 ${showsNav && !isHome && !isDetailsRoute ? 'pt-16' : ''} ${showsNav ? 'pb-16 md:pb-0' : ''} ${
          showsNav && navigationStyle === 'sidebar' ? 'has-nav-rail' : ''
        }`}
      >
        <Outlet />
      </main>
    </div>
  );
}
