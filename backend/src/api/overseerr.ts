import { Router, Request, Response, NextFunction } from 'express';
import { AppError } from '../middleware/errorHandler';
import { createLogger } from '../utils/logger';

const router = Router();
const logger = createLogger('overseerr-proxy');

interface OverseerrProxyRequest {
  targetUrl: string;
  apiKey: string;
  endpoint: string;
  method?: string;
  body?: any;
}

/**
 * Proxy requests to user's Overseerr instance to avoid CORS issues
 * POST /api/overseerr/proxy
 */
router.post('/proxy',
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { targetUrl, apiKey, endpoint, method = 'GET', body } = req.body as OverseerrProxyRequest;

      if (!targetUrl || !apiKey || !endpoint) {
        throw new AppError('Missing required fields: targetUrl, apiKey, endpoint', 400);
      }

      // Normalize the URL - remove trailing slashes
      const baseUrl = targetUrl.replace(/\/+$/, '');
      const fullUrl = `${baseUrl}/api/v1${endpoint}`;

      logger.debug(`Proxying ${method} request to Overseerr: ${fullUrl}`);

      const fetchOptions: RequestInit = {
        method,
        headers: {
          'X-Api-Key': apiKey,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      };

      if (body && (method === 'POST' || method === 'PUT' || method === 'PATCH')) {
        fetchOptions.body = JSON.stringify(body);
      }

      const response = await fetch(fullUrl, fetchOptions);
      const contentType = response.headers.get('content-type');

      // Forward the response status and body
      if (contentType?.includes('application/json')) {
        const data = await response.json();
        res.status(response.status).json(data);
      } else {
        const text = await response.text();
        res.status(response.status).send(text);
      }
    } catch (error: any) {
      logger.error('Overseerr proxy error:', error);

      // Handle fetch errors (network issues, etc.)
      if (error.cause?.code === 'ECONNREFUSED') {
        next(new AppError('Could not connect to Overseerr server', 502));
      } else if (error.cause?.code === 'ENOTFOUND') {
        next(new AppError('Overseerr server not found', 502));
      } else {
        next(new AppError(error.message || 'Failed to proxy request to Overseerr', 500));
      }
    }
  }
);

export default router;
