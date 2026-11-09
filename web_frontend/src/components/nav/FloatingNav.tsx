import { useEffect, useState } from 'react';
import { useLocation } from 'react-router-dom';
import FloatingNavTrack from '@/components/nav/FloatingNavTrack';
import { isNavItemActive, useVisibleNavItems } from '@/components/nav/navItems';
import { useScrolled } from '@/components/nav/useScrolled';
import ProfileAvatar from '@/components/profile/ProfileAvatar';
import UserDropdown from '@/components/UserDropdown';
import { useProfileSummary } from '@/services/profiles';
import { useSettings } from '@/state/settings';

const LABELS_FIT_QUERY = '(min-width: 1024px)';

/** Between the phone and desktop layouts the pill has no room for tab labels. */
function useLabelsFit() {
  const [fits, setFits] = useState(() => window.matchMedia(LABELS_FIT_QUERY).matches);
  useEffect(() => {
    const query = window.matchMedia(LABELS_FIT_QUERY);
    const onChange = () => setFits(query.matches);
    query.addEventListener('change', onChange);
    return () => query.removeEventListener('change', onChange);
  }, []);
  return fits;
}

/** The main tabs as a floating pill. Labels collapse per the bar style and return on hover. */
export default function FloatingNav() {
  const { pathname } = useLocation();
  const settings = useSettings();
  const items = useVisibleNavItems();
  const scrolled = useScrolled();
  const profile = useProfileSummary();
  const [hovered, setHovered] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const labelsFit = useLabelsFit();

  const selected = items.find((item) => isNavItemActive(item, pathname)) ?? null;
  const carouselHeroOn = settings.showHeroSection !== false && (settings.heroLayout || 'carousel') === 'carousel';

  let showsLabels: boolean;
  if (settings.navigationBarStyle === 'expanded') showsLabels = true;
  else if (settings.navigationBarStyle === 'compact') showsLabels = false;
  else showsLabels = hovered || menuOpen || !(selected?.id === 'home' && (scrolled || carouselHeroOn));
  if (!labelsFit) showsLabels = false;

  return (
    <nav
      aria-label="Main"
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      onFocus={() => setHovered(true)}
      onBlur={(e) => {
        if (!e.currentTarget.contains(e.relatedTarget)) setHovered(false);
      }}
    >
      <FloatingNavTrack
        items={items}
        selectedId={selected?.id ?? null}
        showsLabels={showsLabels}
        isFrosted={hovered || menuOpen || scrolled}
        glowEnabled={settings.navigationBarGlow}
        trailing={
          <UserDropdown placement="below" onOpenChange={setMenuOpen}>
            {(toggle) => (
              <button
                type="button"
                onClick={toggle}
                aria-label={`Profile: ${profile.name}`}
                className={`flex items-center h-10 rounded-full text-neutral-300 hover:text-white transition-[padding] duration-300 motion-reduce:transition-none ${
                  showsLabels ? 'pl-2.5 pr-3.5' : 'px-1.5'
                }`}
              >
                <ProfileAvatar name={profile.name} thumb={profile.thumb} size={28} ring />
                <span className="nav-label" data-open={showsLabels}>
                  <span className="text-[13px] font-medium">
                    <span className="pl-2">Settings</span>
                  </span>
                </span>
              </button>
            )}
          </UserDropdown>
        }
      />
    </nav>
  );
}
