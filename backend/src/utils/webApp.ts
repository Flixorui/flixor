/**
 * Serves the built web app from the backend itself, so one process is the whole
 * server. The standalone executable sets FLIXOR_WEB_DIR; Docker (nginx) and
 * development (Vite) leave it unset and serve the app themselves.
 */
import express, { type Express, type RequestHandler } from 'express';
import fs from 'fs';
import path from 'path';

/** Paths the app never handles: the API, the FFmpeg relay and the health check. */
const SERVER_PATH = /^\/(?:api|internal)(?:\/|$)|^\/health$/;

/** Last path segment has an extension: a file request, which 404s when missing (as nginx does). */
const FILE_PATH = /\/[^/]*\.[^/]+$/;

/** index.html for every client-side route: GET or HEAD, not a file, not a server path. */
export function spaFallback(indexFile: string): RequestHandler {
  return (req, res, next) => {
    if ((req.method !== 'GET' && req.method !== 'HEAD') || SERVER_PATH.test(req.path) || FILE_PATH.test(req.path)) {
      return next();
    }
    res.setHeader('Cache-Control', 'no-cache');
    res.sendFile(indexFile);
  };
}

/**
 * Mounts the app at `dir` before the 404 handler. Returns the folder served, or
 * null when there is nothing to serve.
 */
export function mountWebApp(app: Express, dir: string | undefined = process.env.FLIXOR_WEB_DIR): string | null {
  if (!dir) return null;
  const root = path.resolve(dir);
  const indexFile = path.join(root, 'index.html');
  if (!fs.existsSync(indexFile)) return null;

  app.use(express.static(root, {
    index: false,
    setHeaders(res, file) {
      // Vite puts content-hashed files in assets/; everything else can change between versions.
      const hashed = path.relative(root, file).split(path.sep)[0] === 'assets';
      res.setHeader('Cache-Control', hashed ? 'public, max-age=31536000, immutable' : 'no-cache');
    },
  }));
  app.use(spaFallback(indexFile));
  return root;
}
