import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { loadSettings, saveSettings, setDiscoveryDisabled } from '@/state/settings';

interface OnboardingSlide {
  id: string;
  title: string;
  subtitle: string;
  description: string;
  isConfig?: boolean;
}

const onboardingData: OnboardingSlide[] = [
  {
    id: '1',
    title: 'Welcome to\nFlixor',
    subtitle: 'Your Personal Media Hub',
    description: 'Stream your entire Plex library with a beautiful, Netflix-inspired experience on any device.',
  },
  {
    id: '2',
    title: 'Powerful\nIntegrations',
    subtitle: 'Connect Your Services',
    description: 'Sync with Trakt to track your watch history, get personalized recommendations, and discover new content.',
  },
  {
    id: '3',
    title: 'Smart\nDiscovery',
    subtitle: 'Find What You Love',
    description: 'Browse trending content, search across your library and TMDB, and get recommendations tailored to you.',
  },
  {
    id: '4',
    title: 'Your\nLibrary',
    subtitle: 'Beautifully Organized',
    description: 'Continue watching across devices, manage your watchlist, and enjoy stunning artwork from TMDB.',
  },
  {
    id: '5',
    title: 'Customize\nYour Experience',
    subtitle: 'Discovery Settings',
    description: 'Choose how you want to discover content.',
    isConfig: true,
  },
];

// Setting Row Component
function SettingRow({
  icon,
  title,
  description,
  checked,
  onChange,
  disabled = false,
}: {
  icon: string;
  title: string;
  description: string;
  checked: boolean;
  onChange: (value: boolean) => void;
  disabled?: boolean;
}) {
  return (
    <div className="flex items-center gap-3 px-4 py-3.5 border-b border-white/[0.08] last:border-b-0">
      <div className={`w-9 h-9 rounded-lg flex items-center justify-center ${disabled ? 'bg-white/5' : 'bg-white/10'}`}>
        <span className={`text-lg ${disabled ? 'opacity-30' : 'opacity-60'}`}>{icon}</span>
      </div>
      <div className="flex-1 min-w-0">
        <div className={`text-sm font-semibold ${disabled ? 'text-white/40' : 'text-white'}`}>{title}</div>
        <div className="text-xs text-white/40">{description}</div>
      </div>
      <label className="relative inline-flex items-center cursor-pointer">
        <input
          type="checkbox"
          checked={checked}
          onChange={(e) => onChange(e.target.checked)}
          disabled={disabled}
          className="sr-only peer"
        />
        <div className={`
          w-11 h-6 rounded-full peer transition-colors
          ${disabled ? 'bg-white/10 cursor-not-allowed' : 'bg-white/20'}
          peer-checked:bg-green-500
          after:content-[''] after:absolute after:top-[2px] after:left-[2px]
          after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all
          peer-checked:after:translate-x-5
        `} />
      </label>
    </div>
  );
}

// Config Slide Component
function ConfigSlide({
  discoveryOff,
  setDiscoveryOff,
  showIndividual,
  setShowIndividual,
  trendingOn,
  setTrendingOn,
  traktOn,
  setTraktOn,
  plexPopularOn,
  setPlexPopularOn,
  newHotOn,
  setNewHotOn,
  tmdbSearchOn,
  setTmdbSearchOn,
}: {
  discoveryOff: boolean;
  setDiscoveryOff: (v: boolean) => void;
  showIndividual: boolean;
  setShowIndividual: (v: boolean) => void;
  trendingOn: boolean;
  setTrendingOn: (v: boolean) => void;
  traktOn: boolean;
  setTraktOn: (v: boolean) => void;
  plexPopularOn: boolean;
  setPlexPopularOn: (v: boolean) => void;
  newHotOn: boolean;
  setNewHotOn: (v: boolean) => void;
  tmdbSearchOn: boolean;
  setTmdbSearchOn: (v: boolean) => void;
}) {
  return (
    <div className="w-full max-w-lg mx-auto px-8">
      <h2 className="text-3xl font-extrabold text-white mb-2">Customize Your Experience</h2>
      <p className="text-white/50 text-sm mb-6">Choose how you want to discover content</p>

      {/* Library Only Mode Card */}
      <div className="bg-white/[0.08] rounded-2xl border border-white/10 p-5 mb-4">
        <div className="flex items-center gap-4">
          <div className="w-12 h-12 rounded-xl bg-red-500/15 flex items-center justify-center">
            <span className="text-2xl">
              <svg className="w-6 h-6 text-red-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.88 9.88l-3.29-3.29m7.532 7.532l3.29 3.29M3 3l3.59 3.59m0 0A9.953 9.953 0 0112 5c4.478 0 8.268 2.943 9.543 7a10.025 10.025 0 01-4.132 5.411m0 0L21 21" />
              </svg>
            </span>
          </div>
          <div className="flex-1">
            <div className="text-white font-semibold text-base">Library Only Mode</div>
            <div className="text-white/50 text-xs leading-relaxed">
              Turn off all discovery features. Only show content from your Plex library.
            </div>
          </div>
          <label className="relative inline-flex items-center cursor-pointer">
            <input
              type="checkbox"
              checked={discoveryOff}
              onChange={(e) => setDiscoveryOff(e.target.checked)}
              className="sr-only peer"
            />
            <div className="w-11 h-6 bg-white/20 rounded-full peer peer-checked:bg-red-500 after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:after:translate-x-5" />
          </label>
        </div>
      </div>

      {/* Individual Settings Toggle */}
      <button
        onClick={() => !discoveryOff && setShowIndividual(!showIndividual)}
        disabled={discoveryOff}
        className={`flex items-center justify-center gap-2 w-full py-4 text-sm font-medium ${
          discoveryOff ? 'text-white/20 cursor-not-allowed' : 'text-white/50 hover:text-white/70'
        }`}
      >
        <span>Or customize individual settings</span>
        <svg
          className={`w-4 h-4 transition-transform ${showIndividual ? 'rotate-180' : ''}`}
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
        </svg>
      </button>

      {/* Individual Settings */}
      {showIndividual && !discoveryOff && (
        <div className="bg-white/[0.05] rounded-2xl border border-white/[0.08] overflow-hidden mb-4">
          <SettingRow
            icon="📈"
            title="Trending Rows"
            description="Show trending content from TMDB"
            checked={trendingOn}
            onChange={setTrendingOn}
          />
          <SettingRow
            icon="📊"
            title="Trakt Rows"
            description="Show recommendations from Trakt"
            checked={traktOn}
            onChange={setTraktOn}
          />
          <SettingRow
            icon="⭐"
            title="Popular on Plex"
            description="Show popular content on Plex"
            checked={plexPopularOn}
            onChange={setPlexPopularOn}
          />
          <SettingRow
            icon="🔥"
            title="New & Hot Tab"
            description="Show New & Hot tab in navigation"
            checked={newHotOn}
            onChange={setNewHotOn}
          />
          <SettingRow
            icon="🔍"
            title="TMDB in Search"
            description="Include TMDB results when searching"
            checked={tmdbSearchOn}
            onChange={setTmdbSearchOn}
          />
        </div>
      )}

      {/* Info text */}
      <div className="flex items-center gap-2 mt-6 text-white/40 text-xs">
        <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
        <span>You can change these settings anytime in Settings → Home Screen</span>
      </div>
    </div>
  );
}

export default function Onboarding() {
  const navigate = useNavigate();
  const [currentIndex, setCurrentIndex] = useState(0);

  // Config state
  const [discoveryOff, setDiscoveryOff] = useState(false);
  const [showIndividual, setShowIndividual] = useState(false);
  const [trendingOn, setTrendingOn] = useState(true);
  const [traktOn, setTraktOn] = useState(true);
  const [plexPopularOn, setPlexPopularOn] = useState(true);
  const [newHotOn, setNewHotOn] = useState(true);
  const [tmdbSearchOn, setTmdbSearchOn] = useState(true);

  // Load settings on mount
  useEffect(() => {
    const settings = loadSettings();
    setDiscoveryOff(settings.discoveryDisabled ?? false);
    setTrendingOn(settings.showTrendingRows !== false);
    setTraktOn(settings.showTraktRows !== false);
    setPlexPopularOn(settings.showPlexPopularRow !== false);
    setNewHotOn(settings.showNewPopularTab !== false);
    setTmdbSearchOn(settings.includeTmdbInSearch !== false);
  }, []);

  // When master toggle is enabled, disable all individual settings
  useEffect(() => {
    if (discoveryOff) {
      setTrendingOn(false);
      setTraktOn(false);
      setPlexPopularOn(false);
      setNewHotOn(false);
      setTmdbSearchOn(false);
    }
  }, [discoveryOff]);

  const progress = (currentIndex / (onboardingData.length - 1)) * 100;

  const handleSkip = () => {
    saveSettings({ hasCompletedOnboarding: true });
    navigate('/');
  };

  const handleGetStarted = () => {
    // Save discovery settings
    if (discoveryOff) {
      setDiscoveryDisabled(true);
    } else {
      saveSettings({
        discoveryDisabled: false,
        showTrendingRows: trendingOn,
        showTraktRows: traktOn,
        showPlexPopularRow: plexPopularOn,
        showNewPopularTab: newHotOn,
        includeTmdbInSearch: tmdbSearchOn,
      });
    }
    saveSettings({ hasCompletedOnboarding: true });
    navigate('/');
  };

  const goNext = () => {
    if (currentIndex < onboardingData.length - 1) {
      setCurrentIndex(currentIndex + 1);
    }
  };

  const goPrev = () => {
    if (currentIndex > 0) {
      setCurrentIndex(currentIndex - 1);
    }
  };

  const currentSlide = onboardingData[currentIndex];
  const isLastSlide = currentIndex === onboardingData.length - 1;

  return (
    <div className="min-h-screen bg-[#0a0a0a] flex flex-col relative overflow-hidden">
      {/* Animated Background */}
      <div className="absolute inset-0 bg-gradient-to-br from-[#1a1a2e] via-[#16213e] to-[#0f0f23]">
        <div className="absolute w-[400px] h-[400px] rounded-full bg-purple-500/20 blur-[100px] animate-pulse" style={{ top: '10%', left: '60%' }} />
        <div className="absolute w-[300px] h-[300px] rounded-full bg-blue-500/15 blur-[80px] animate-pulse" style={{ bottom: '20%', left: '10%', animationDelay: '1s' }} />
      </div>

      {/* Content */}
      <div className="relative z-10 flex flex-col min-h-screen">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-5">
          <button onClick={handleSkip} className="text-white/40 text-sm font-medium hover:text-white/60">
            Skip
          </button>
          <div className="flex-1 ml-6 h-1 bg-white/10 rounded-full overflow-hidden">
            <div
              className="h-full bg-white rounded-full transition-all duration-300"
              style={{ width: `${progress}%` }}
            />
          </div>
        </div>

        {/* Slide Content */}
        <div className="flex-1 flex items-center justify-center px-6">
          {currentSlide.isConfig ? (
            <ConfigSlide
              discoveryOff={discoveryOff}
              setDiscoveryOff={setDiscoveryOff}
              showIndividual={showIndividual}
              setShowIndividual={setShowIndividual}
              trendingOn={trendingOn}
              setTrendingOn={setTrendingOn}
              traktOn={traktOn}
              setTraktOn={setTraktOn}
              plexPopularOn={plexPopularOn}
              setPlexPopularOn={setPlexPopularOn}
              newHotOn={newHotOn}
              setNewHotOn={setNewHotOn}
              tmdbSearchOn={tmdbSearchOn}
              setTmdbSearchOn={setTmdbSearchOn}
            />
          ) : (
            <div className="max-w-lg text-left">
              <h1 className="text-5xl font-extrabold text-white leading-tight whitespace-pre-line mb-4">
                {currentSlide.title}
              </h1>
              <h2 className="text-lg font-semibold text-white/60 mb-5">
                {currentSlide.subtitle}
              </h2>
              <p className="text-base text-white/40 leading-relaxed max-w-md">
                {currentSlide.description}
              </p>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="px-6 pb-10">
          {/* Pagination Dots */}
          <div className="flex justify-center gap-2 mb-8">
            {onboardingData.map((_, index) => (
              <div
                key={index}
                className={`h-2 rounded-full transition-all duration-300 ${
                  index === currentIndex ? 'w-8 bg-white' : 'w-2 bg-white/30'
                }`}
              />
            ))}
          </div>

          {/* Navigation Buttons */}
          <div className="flex justify-center gap-4">
            <button
              onClick={goPrev}
              disabled={currentIndex === 0}
              className={`flex items-center gap-2 px-6 py-3 rounded-xl text-sm font-medium transition-all ${
                currentIndex === 0
                  ? 'bg-white/5 text-white/20 cursor-not-allowed'
                  : 'bg-white/10 text-white/70 hover:bg-white/15'
              }`}
            >
              <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
              </svg>
              Back
            </button>
            <button
              onClick={isLastSlide ? handleGetStarted : goNext}
              className={`flex items-center gap-2 px-8 py-3 rounded-xl text-sm font-semibold transition-all ${
                isLastSlide
                  ? 'bg-white text-black hover:bg-white/90'
                  : 'bg-white/15 text-white hover:bg-white/20'
              }`}
            >
              {isLastSlide ? 'Get Started' : 'Next'}
              {!isLastSlide && (
                <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
                </svg>
              )}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
