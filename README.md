# Flixor (Cross Platform)

## Description
A fast, Netflix‑style web app, Android, iOS, and MacOS for your Plex library. Browse beautiful rows, see rich details (IMDb/Rotten Tomatoes), and play instantly in your browser with built‑in DASH/HLS playback. Works on any modern desktop or mobile browser.

## Features
- Netflix‑style home: Continue Watching, Trending, Collections, and more
- Built‑in player: DASH/HLS, fullscreen, Picture‑in‑Picture, subtitles
- Rich details: trailers/extras, cast, badges (4K/HDR/Atmos), IMDb/RT ratings
- Smart search and filters; ultra‑fast grids optimized for large libraries
- Recommendations from TMDB/Trakt plus Plex On Deck
- Smooth, responsive UI with image optimization and caching

## Installation
- Quick start (Docker, recommended)
  1) Ensure Docker Desktop is installed
  2) In this folder, run: `docker compose up -d`
  3) Open `http://localhost:8080` and sign in with Plex

- Local (advanced)
  1) Install Node.js 18+ and npm
  2) Run: `npm install` then `npm run dev:all`
  3) Open `http://localhost:5173` and sign in with Plex

Notes for multi‑device/dev
- The app calls the backend via relative `/api` so it works from any device on your network.
- Vite dev server is reachable on your LAN. Visit `http://YOUR_COMPUTER_IP:5173` on your phone/another PC.
- If you need to point dev proxy to a different backend, set `VITE_PROXY_TARGET` in `.env` (see `.env.example`).

That’s it—no extra setup needed. The app uses the bundled backend by default; the database is created and migrations run automatically on first start.

## Screenshots
![Home](docs/screenshots/flixor-01.jpg)
![Details](docs/screenshots/flixor-02.jpg)
![Library 00:52](docs/screenshots/flixor-lib-00m52.png)
![Library 01:20](docs/screenshots/flixor-lib-01m20.png)
![Library 02:14](docs/screenshots/flixor-lib-02m14.png)
![Library 02:24](docs/screenshots/flixor-lib-02m24.png)
![Library 02:34](docs/screenshots/flixor-lib-02m34.png)
![Library 02:48](docs/screenshots/flixor-lib-02m48.png)
![Library 03:04](docs/screenshots/flixor-lib-03m04.png)
![Library 03:11](docs/screenshots/flixor-lib-03m11.png)
