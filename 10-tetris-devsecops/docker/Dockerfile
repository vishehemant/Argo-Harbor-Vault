# Multi-stage Dockerfile for the Tetris DevSecOps project
#
# Stage 1: Copy static files (no build step needed for vanilla JS)
# Stage 2: Nginx serves the game with security hardening

# ── Stage 1: Prepare files ──
FROM alpine:3.19 AS builder

WORKDIR /app
COPY app/src/ ./

# ── Stage 2: Production image ──
FROM nginx:1.25-alpine

# Security: run as non-root
RUN addgroup -g 1001 appgroup && \
    adduser -u 1001 -G appgroup -D appuser && \
    chown -R appuser:appgroup /var/cache/nginx /var/log/nginx /etc/nginx/conf.d && \
    touch /var/run/nginx.pid && chown appuser:appgroup /var/run/nginx.pid

# Copy game files
COPY --from=builder /app/ /usr/share/nginx/html/

# Copy nginx config with health check and API endpoints
COPY app/nginx/default.conf /etc/nginx/conf.d/default.conf

# Environment variables (overridden by Kubernetes)
ENV APP_VERSION="local" \
    APP_ENV="local"

EXPOSE 80

USER appuser

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
    CMD wget -qO- http://localhost/health || exit 1
