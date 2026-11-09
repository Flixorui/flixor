/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './index.html',
    './src/**/*.{ts,tsx}',
  ],
  theme: {
    extend: {
      colors: {
        brand: {
          DEFAULT: 'rgb(var(--accent-rgb) / <alpha-value>)',
          600: 'rgb(var(--accent-strong-rgb) / <alpha-value>)',
          bright: 'rgb(var(--accent-bright-rgb) / <alpha-value>)',
        },
      },
    },
  },
  plugins: [],
};
