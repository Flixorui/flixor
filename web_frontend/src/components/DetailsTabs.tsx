interface DetailsTabsProps {
  tabs: Array<{
    id: string;
    label: string;
    count?: number;
  }>;
  activeTab: string;
  onTabChange: (tabId: string) => void;
}

export default function DetailsTabs({ tabs, activeTab, onTabChange }: DetailsTabsProps) {
  return (
    <div className="sticky top-0 z-20 backdrop-blur-md border-b border-white/10">
      <div className="page-gutter-left">
        <div className="flex items-center gap-8 overflow-x-auto scrollbar-hide">
          {tabs.map(tab => (
            <button
              key={tab.id}
              onClick={() => onTabChange(tab.id)}
              className={`relative py-4 text-sm font-medium transition-colors whitespace-nowrap ${
                activeTab === tab.id
                  ? 'text-white'
                  : 'text-white/50 hover:text-white/80'
              }`}
            >
              <span className="flex items-center gap-2">
                {tab.label}
                {tab.count !== undefined && (
                  <span className="text-xs text-white/40">({tab.count})</span>
                )}
              </span>
              {activeTab === tab.id && (
                <div className="absolute bottom-0 left-0 right-0 h-0.5 bg-white" />
              )}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
