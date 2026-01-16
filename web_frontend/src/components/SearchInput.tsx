import { useRef, useEffect, useState } from 'react';

interface SearchInputProps {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  autoFocus?: boolean;
}

export default function SearchInput({
  value,
  onChange,
  placeholder = 'Search for movies, TV shows...',
  autoFocus = false
}: SearchInputProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [isFocused, setIsFocused] = useState(false);

  useEffect(() => {
    if (autoFocus && inputRef.current) {
      inputRef.current.focus();
    }
  }, [autoFocus]);

  const handleClear = () => {
    onChange('');
    inputRef.current?.focus();
  };

  return (
    <div
      className={`
        flex items-center gap-3
        px-4 py-3
        bg-white/[0.08] backdrop-blur-sm
        rounded-xl
        ring-1 transition-all duration-200
        ${isFocused ? 'ring-white/20' : 'ring-white/[0.12]'}
      `}
    >
      {/* Search Icon */}
      <svg
        className="w-5 h-5 text-neutral-400 flex-shrink-0"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        viewBox="0 0 24 24"
      >
        <path d="M21 21l-4.3-4.3" strokeLinecap="round" />
        <circle cx="11" cy="11" r="7" />
      </svg>

      {/* Input Field */}
      <input
        ref={inputRef}
        type="text"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        onFocus={() => setIsFocused(true)}
        onBlur={() => setIsFocused(false)}
        placeholder={placeholder}
        className="flex-1 bg-transparent text-white text-base font-normal
                   border-0 outline-none focus:outline-none placeholder:text-neutral-500"
      />

      {/* Clear Button */}
      {value && (
        <button
          onClick={handleClear}
          className="flex-shrink-0 p-1 rounded-full hover:bg-white/10 transition-colors duration-150"
          aria-label="Clear search"
        >
          <svg
            className="w-4 h-4 text-neutral-400 hover:text-white"
            fill="none"
            viewBox="0 0 24 24"
          >
            <path d="M18 6L6 18M6 6l12 12" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
          </svg>
        </button>
      )}
    </div>
  );
}
