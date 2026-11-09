import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { AppError } from './errorHandler';

// Extend Express Request type to include user
declare module 'express-session' {
  interface SessionData {
    userId?: string;
    plexId?: number;
    username?: string;
    /** Set while a Plex Home profile is active: the account that signed in. */
    mainUserId?: string;
    profile?: SessionProfile;
  }
}

/** The Plex Home profile a session has switched to. Absent for the signed-in account. */
export interface SessionProfile {
  uuid: string;
  title: string;
  thumb?: string;
  restricted: boolean;
  protected: boolean;
}

export interface AuthenticatedRequest extends Request {
  user?: {
    id: string;
    plexId: number;
    username: string;
  };
}

export function requireAuth(req: AuthenticatedRequest, res: Response, next: NextFunction) {
  // 1) Try session cookie (web)
  if (req.session.userId) {
    req.user = {
      id: req.session.userId,
      plexId: req.session.plexId!,
      username: req.session.username!,
    };
    return next();
  }

  // 2) Try Bearer JWT (mobile/API)
  const auth = req.headers['authorization'] || '';
  const m = /^Bearer\s+(.+)$/i.exec(Array.isArray(auth) ? auth[0] : auth);
  if (m) {
    try {
      const secret = process.env.SESSION_SECRET || 'change-this-in-production';
      const payload: any = jwt.verify(m[1], secret);
      if (payload && payload.sub) {
        req.user = {
          id: String(payload.sub),
          plexId: payload.plexId || 0,
          username: payload.username || 'user',
        };
        return next();
      }
    } catch {}
  }

  throw new AppError('Authentication required', 401);
}

export function optionalAuth(req: AuthenticatedRequest, res: Response, next: NextFunction) {
  if (req.session.userId) {
    req.user = {
      id: req.session.userId,
      plexId: req.session.plexId!,
      username: req.session.username!,
    };
  }
  next();
}
