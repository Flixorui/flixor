import { useRef, useEffect } from 'react';

interface SearchInputProps {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  autoFocus?: boolean;
}

export default function SearchInput({
  value,
  onChange,
  placeholder = 'Search by title, genre, team or league',
  autoFocus = false
}: SearchInputProps) {
  const inputRef = useRef<HTMLInputElement>(null);

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
    <div className="relative group pb-3">
      {/* Search Icon */}
      <div className="absolute left-2.5 top-1/2 -translate-y-1/2 pointer-events-none">
        <svg
          className="w-6 h-6 text-white/80"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          viewBox="0 0 24 24"
        >
          <path d="M21 21l-4.3-4.3" />
          <circle cx="11" cy="11" r="7" />
        </svg>
      </div>

      {/* Input Field */}
      <input
        ref={inputRef}
        type="text"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="w-full bg-transparent text-white text-2xl md:text-3xl font-medium py-2 pl-10 pr-10
                   border-0 outline-none focus:outline-none placeholder:text-neutral-400"
      />

      {/* Clear Button */}
      {value && (
        <button
          onClick={handleClear}
          className="absolute right-1 top-1/2 -translate-y-1/2 p-1.5 rounded hover:bg-white/5 transition-colors duration-150"
          aria-label="Clear search"
        >
          <svg
            className="w-5 h-5 text-white/80 hover:text-white"
            fill="currentColor"
            viewBox="0 0 24 24"
          >
            <path d="M18 6L6 18M6 6l12 12" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
          </svg>
        </button>
      )}

      {/* Underline */}
      <div className="pointer-events-none absolute left-0 right-0 bottom-0 h-[2px] bg-white/30 group-focus-within:bg-white/60 transition-colors duration-150" />
    </div>
  );
}
