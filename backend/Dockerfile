# Backend Dockerfile (Node.js + TypeScript)

# 1) Build stage
FROM node:20-slim AS builder
WORKDIR /app

# Only copy backend package files first for better caching
COPY package*.json ./
RUN --mount=type=cache,target=/root/.npm npm ci

# Copy source
COPY . .

# Build TypeScript
RUN npm run build

# Prune dev dependencies after build
RUN npm prune --omit=dev

# 2) Runtime stage
FROM node:20-slim AS runner
ENV NODE_ENV=production
WORKDIR /app

# FFmpeg lets the web player remux or convert addon files browsers can't open
# (MKV with TrueHD/DTS/AC3, AVI, HEVC). Debian's build includes zscale for HDR.
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Create writable directories for DB and caches (mountable as volumes)
RUN mkdir -p /app/config/db && mkdir -p /app/cache/images

# Copy minimal runtime artifacts
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package*.json ./

EXPOSE 3001

# Default env; override via compose or environment
ENV PORT=3001
ENV HOST=0.0.0.0

CMD ["node", "dist/server.js"]

