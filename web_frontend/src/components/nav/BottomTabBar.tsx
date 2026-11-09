import { Link, useLocation } from 'react-router-dom';
import { isNavItemActive, useVisibleNavItems } from '@/components/nav/navItems';

/** Tabs for phones and narrow windows, where neither the pill nor the rail fits. */
export default function BottomTabBar() {
  const { pathname } = useLocation();
  const items = useVisibleNavItems();

  return (
    <nav
      aria-label="Main"
      className="md:hidden fixed bottom-0 inset-x-0 z-50 flex bg-black/90 backdrop-blur-lg border-t border-white/10 pb-[env(safe-area-inset-bottom)]"
    >
      {items.map((item) => {
        const selected = isNavItemActive(item, pathname);
        const Icon = item.icon;
        return (
          <Link
            key={item.id}
            to={item.to}
            aria-current={selected ? 'page' : undefined}
            className={`flex-1 min-w-0 h-14 flex flex-col items-center justify-center gap-0.5 ${selected ? 'text-brand-bright' : 'text-neutral-400'}`}
          >
            <Icon size={22} filled={selected} />
            <span className="text-[10px] font-medium truncate">{item.shortLabel ?? item.label}</span>
          </Link>
        );
      })}
    </nav>
  );
}
