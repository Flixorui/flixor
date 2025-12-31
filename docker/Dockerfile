# Flixor Production Dockerfile
# Multi-stage build: Backend (Node.js) + Frontend (Vite) + Nginx

# =============================================================================
# Stage 1: Build Backend
# =============================================================================
FROM node:20-slim AS backend-builder
WORKDIR /app/backend

COPY backend/package*.json ./
RUN --mount=type=cache,target=/root/.npm npm ci

COPY backend/ .
RUN npm run build && npm prune --omit=dev

# =============================================================================
# Stage 2: Build Frontend
# =============================================================================
FROM node:20-slim AS frontend-builder
WORKDIR /app/frontend

COPY web_frontend/package*.json ./
RUN --mount=type=cache,target=/root/.npm npm ci

COPY web_frontend/ .
RUN npm run build

# =============================================================================
# Stage 3: Production Runtime
# =============================================================================
FROM node:20-slim AS production

# Install nginx and supervisord
RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx \
    supervisor \
    && rm -rf /var/lib/apt/lists/* \
    && rm /etc/nginx/sites-enabled/default

WORKDIR /app

# Create directories for config and cache
RUN mkdir -p /app/config/db /app/cache/images

# Copy backend build
COPY --from=backend-builder /app/backend/dist ./backend/dist
COPY --from=backend-builder /app/backend/node_modules ./backend/node_modules
COPY --from=backend-builder /app/backend/package*.json ./backend/

# Copy frontend build to nginx html directory
COPY --from=frontend-builder /app/frontend/dist /usr/share/nginx/html

# Copy configuration files
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Environment defaults
ENV NODE_ENV=production \
    PORT=3001 \
    HOST=127.0.0.1

EXPOSE 80

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
