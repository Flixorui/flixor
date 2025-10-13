# Frontend Dockerfile (Vite build + Nginx static server)

# 1) Build stage (Node)
FROM node:20-slim AS builder
WORKDIR /app

COPY package*.json ./
RUN --mount=type=cache,target=/root/.npm npm ci

COPY . .
RUN npm run build

# 2) Runtime stage (Nginx)
FROM nginx:1.27-alpine AS runner
WORKDIR /usr/share/nginx/html

# Replace default site with SPA config
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf

# Copy built static assets
COPY --from=builder /app/dist .

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]

