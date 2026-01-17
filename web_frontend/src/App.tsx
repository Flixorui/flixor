import { Outlet, useLocation, useNavigate } from 'react-router-dom';
import { useEffect } from 'react';
import TopNav from '@/components/TopNav';
import GlobalToast from '@/components/GlobalToast';
import UpdateNotification from '@/components/UpdateNotification';
import { loadSettings } from '@/state/settings';

export default function App() {
  const location = useLocation();
  const navigate = useNavigate();
  const isPlayerRoute = location.pathname.includes('/player/');
  const isDetailsRoute = location.pathname.includes('/details/');
  const isHome = location.pathname === '/';
  const isAuthRoute = location.pathname.startsWith('/login');
  const isOnboardingRoute = location.pathname === '/onboarding';

  // Check onboarding status on mount
  useEffect(() => {
    const settings = loadSettings();
    const isAuthenticated = !!(settings.plexBaseUrl && settings.plexToken) || !!settings.plexServer;

    // If authenticated but hasn't completed onboarding, redirect to onboarding
    if (isAuthenticated && !settings.hasCompletedOnboarding && !isOnboardingRoute && !isAuthRoute) {
      navigate('/onboarding');
    }
  }, [navigate, isOnboardingRoute, isAuthRoute]);

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

  return (
    <div className="min-h-screen flex flex-col">
      {/* Global fixed background layer */}
      <div className="app-bg-fixed bg-home-gradient" />
      <GlobalToast />
      {!isPlayerRoute && !isOnboardingRoute && <UpdateNotification />}
      {!isPlayerRoute && !isAuthRoute && !isOnboardingRoute && <TopNav />}
      <main className={`flex-1 ${!isPlayerRoute && !isHome && !isDetailsRoute && !isAuthRoute && !isOnboardingRoute ? 'pt-16' : ''}`}>
        <Outlet />
      </main>
    </div>
  );
}
