# Stage 1: Builder
FROM alpine:3.19 AS builder
WORKDIR /build
COPY app/ .

# Stage 2: Runtime
FROM nginx:1.25-alpine
RUN adduser -D -u 1001 nginxuser
USER 1001

COPY --from=builder /build/ /usr/share/nginx/html/
COPY --from=builder /build/nginx/default.conf /etc/nginx/conf.d/default.conf

ENV APP_VERSION="local" \
    APP_ENV="local"

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q -O- http://localhost:8080/health || exit 1
