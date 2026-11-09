import { useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { NavGearIcon, NavPinIcon } from '@/components/nav/NavIcons';
import { isNavItemActive, useVisibleNavItems } from '@/components/nav/navItems';
import ProfileAvatar from '@/components/profile/ProfileAvatar';
import UserDropdown from '@/components/UserDropdown';
import { useProfileSummary } from '@/services/profiles';
import { saveSettings, useSettings } from '@/state/settings';

function RowLabel({ expanded, active, children }: { expanded: boolean; active?: boolean; children: React.ReactNode }) {
  return (
    <span className={`text-sm whitespace-nowrap transition-opacity duration-200 ${active ? 'font-semibold' : 'font-medium'} ${expanded ? 'opacity-100' : 'opacity-0'}`}>
      {children}
    </span>
  );
}

const ROW_CLASS = 'flex items-center gap-3 h-[46px] pl-[7px] mx-2 rounded-xl transition-colors hover:bg-white/[0.06]';

/** Left navigation rail. Icons only, expanding over the page on hover or staying open when pinned. */
export default function SidebarRail() {
  const { pathname } = useLocation();
  const { navigationSidebarPinned: pinned } = useSettings();
  const items = useVisibleNavItems();
  const profile = useProfileSummary();
  const [hovered, setHovered] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);

  const expanded = pinned || hovered || menuOpen;
  const floating = expanded && !pinned;

  return (
    <nav
      aria-label="Main"
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      onFocus={() => setHovered(true)}
      onBlur={(e) => {
        if (!e.currentTarget.contains(e.relatedTarget)) setHovered(false);
      }}
      style={{ width: expanded ? 200 : 68 }}
      className={`hidden md:flex fixed inset-y-0 left-0 z-50 flex-col py-3 gap-1 bg-[#141414] border-r border-white/[0.08] transition-[width] duration-200 motion-reduce:transition-none ${
        floating ? 'shadow-[0_16px_48px_rgba(0,0,0,0.7)]' : ''
      }`}
    >
      {items.map((item) => {
        const selected = isNavItemActive(item, pathname);
        const Icon = item.icon;
        return (
          <Link
            key={item.id}
            to={item.to}
            title={expanded ? undefined : item.label}
            aria-current={selected ? 'page' : undefined}
            className={`${ROW_CLASS} ${selected ? 'text-white' : 'text-neutral-400 hover:text-white'}`}
          >
            <span className={`w-[38px] h-[38px] flex-shrink-0 flex items-center justify-center rounded-lg ${selected ? 'bg-brand text-white' : ''}`}>
              <Icon size={20} filled={selected} />
            </span>
            <RowLabel expanded={expanded} active={selected}>{item.label}</RowLabel>
          </Link>
        );
      })}

      <div className="flex-1 min-h-4" />
      <div className="mx-3 mb-1 h-px bg-white/[0.08]" />

      <button
        type="button"
        onClick={() => saveSettings({ navigationSidebarPinned: !pinned })}
        title={expanded ? undefined : pinned ? 'Collapse Sidebar' : 'Keep Expanded'}
        className={`${ROW_CLASS} text-left text-neutral-400 hover:text-white`}
      >
        <span className={`w-[38px] h-[38px] flex-shrink-0 flex items-center justify-center ${pinned ? 'text-brand-bright' : ''}`}>
          <NavPinIcon size={18} filled={pinned} />
        </span>
        <RowLabel expanded={expanded}>{pinned ? 'Collapse Sidebar' : 'Keep Expanded'}</RowLabel>
      </button>

      <Link to="/settings" title={expanded ? undefined : 'Settings'} className={`${ROW_CLASS} text-neutral-400 hover:text-white`}>
        <span className="w-[38px] h-[38px] flex-shrink-0 flex items-center justify-center">
          <NavGearIcon size={20} />
        </span>
        <RowLabel expanded={expanded}>Settings</RowLabel>
      </Link>

      <UserDropdown placement="beside" onOpenChange={setMenuOpen}>
        {(toggle) => (
          <button
            type="button"
            onClick={toggle}
            aria-label={`Profile: ${profile.name}`}
            title={expanded ? undefined : profile.name}
            className={`${ROW_CLASS} w-[calc(100%-1rem)] text-left text-neutral-300 hover:text-white`}
          >
            <span className="w-[38px] h-[38px] flex-shrink-0 flex items-center justify-center">
              <ProfileAvatar name={profile.name} thumb={profile.thumb} size={28} />
            </span>
            <RowLabel expanded={expanded}>
              <span className="block max-w-[120px] truncate">{profile.name}</span>
            </RowLabel>
          </button>
        )}
      </UserDropdown>
    </nav>
  );
}
