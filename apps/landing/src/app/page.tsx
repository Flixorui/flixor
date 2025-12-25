'use client';

import { useState } from 'react';
import Image from 'next/image';

export default function Home() {
  const [email, setEmail] = useState('');
  const [status, setStatus] = useState<'idle' | 'loading' | 'success' | 'error'>('idle');
  const [message, setMessage] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email) return;

    setStatus('loading');

    // TODO: Replace with actual API endpoint
    try {
      await new Promise(resolve => setTimeout(resolve, 1000));
      setStatus('success');
      setMessage("You're on the list! We'll notify you when Flixor launches.");
      setEmail('');
    } catch {
      setStatus('error');
      setMessage('Something went wrong. Please try again.');
    }
  };

  return (
    <div className="min-h-screen gradient-bg">
      {/* Navigation */}
      <nav className="fixed top-0 left-0 right-0 z-50 px-6 py-5">
        <div className="max-w-6xl mx-auto flex items-center justify-between">
          <div className="flex items-center gap-3">
            <Image
              src="/icon.png"
              alt="Flixor"
              width={40}
              height={40}
              className="rounded-xl"
            />
            <span className="text-xl font-bold text-white">Flixor</span>
          </div>
        </div>
      </nav>

      {/* Hero Section */}
      <main className="flex flex-col items-center justify-center min-h-screen px-6 pt-20">
        <div className="max-w-2xl mx-auto text-center">
          {/* Badge */}
          <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-white/5 border border-white/10 mb-10">
            <span className="w-2 h-2 bg-[#E50914] rounded-full animate-pulse"></span>
            <span className="text-sm text-zinc-400">Coming Soon</span>
          </div>

          {/* Headline */}
          <h1 className="text-4xl sm:text-5xl md:text-6xl font-bold text-white mb-6 leading-[1.1] tracking-tight">
            Your Plex library,<br />
            <span className="text-[#E50914]">reimagined</span>
          </h1>

          {/* Subheadline */}
          <p className="text-lg md:text-xl text-zinc-400 mb-12 max-w-lg mx-auto leading-relaxed">
            A beautiful, native client for Plex. Stream your media with a Netflix-like experience on Web, macOS, iOS, and Android (with more platforms coming soon).
          </p>

          {/* Email Signup Form */}
          <div className="max-w-xl mx-auto mb-6">
            <form onSubmit={handleSubmit} className="relative">
              <div className="flex flex-col sm:flex-row gap-3">
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="Enter your email address"
                  className="flex-1 h-14 sm:h-16 px-6 bg-[#1a1a1a] border border-[#333] rounded-xl text-white text-base sm:text-lg"
                  disabled={status === 'loading'}
                  required
                />
                <button
                  type="submit"
                  disabled={status === 'loading'}
                  className="h-14 sm:h-16 px-8 bg-[#E50914] hover:bg-[#f6121d] disabled:bg-[#E50914]/50 text-white font-semibold rounded-xl text-base sm:text-lg transition-all whitespace-nowrap"
                >
                  {status === 'loading' ? 'Joining...' : 'Get Early Access'}
                </button>
              </div>
            </form>

            {/* Status Message */}
            {message && (
              <p className={`text-sm mt-4 ${status === 'success' ? 'text-green-400' : 'text-red-400'}`}>
                {message}
              </p>
            )}

            {/* Trust indicator */}
            <p className="text-sm text-zinc-600 mt-4">
              Join the waitlist. No spam, ever.
            </p>
          </div>

          {/* Platform badges */}
          <div className="flex items-center justify-center gap-4 mt-10">
            <PlatformBadge label="macOS" />
            <PlatformBadge label="iOS" />
            <PlatformBadge label="tvOS" />
          </div>
        </div>

        {/* Features Grid */}
        <div className="max-w-4xl mx-auto mt-28 grid grid-cols-1 md:grid-cols-3 gap-5 px-6 mb-20">
          <FeatureCard
            icon={
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
              </svg>
            }
            title="Native Experience"
            description="Built with SwiftUI. Fast, fluid, and feels right at home on Apple platforms."
          />
          <FeatureCard
            icon={
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z" />
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            }
            title="Powerful Playback"
            description="MPV-powered player with HDR, Dolby Vision, and advanced subtitle support."
          />
          <FeatureCard
            icon={
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z" />
              </svg>
            }
            title="Trakt Integration"
            description="Sync watch history, ratings, and scrobble automatically to Trakt.tv."
          />
        </div>
      </main>

      {/* Footer */}
      <footer className="border-t border-white/5 py-8 px-6">
        <div className="max-w-6xl mx-auto flex flex-col md:flex-row items-center justify-between gap-4">
          <p className="text-sm text-zinc-600">
            &copy; {new Date().getFullYear()} Flixor. All rights reserved.
          </p>
          <div className="flex items-center gap-6">
            <a href="#" className="text-sm text-zinc-600 hover:text-white transition-colors">
              Privacy
            </a>
            <a href="#" className="text-sm text-zinc-600 hover:text-white transition-colors">
              Terms
            </a>
          </div>
        </div>
      </footer>
    </div>
  );
}

function FeatureCard({ icon, title, description }: { icon: React.ReactNode; title: string; description: string }) {
  return (
    <div className="p-6 rounded-2xl bg-[#111]/80 border border-white/5 hover:border-white/10 transition-all">
      <div className="w-11 h-11 rounded-xl bg-[#E50914]/10 flex items-center justify-center text-[#E50914] mb-4">
        {icon}
      </div>
      <h3 className="text-base font-semibold text-white mb-2">{title}</h3>
      <p className="text-sm text-zinc-500 leading-relaxed">{description}</p>
    </div>
  );
}

function PlatformBadge({ label }: { label: string }) {
  return (
    <div className="flex items-center gap-2 px-4 py-2 rounded-full bg-white/5 border border-white/5">
      <svg className="w-4 h-4 text-zinc-500" fill="currentColor" viewBox="0 0 24 24">
        <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
      </svg>
      <span className="text-sm text-zinc-500">{label}</span>
    </div>
  );
}
