# Multi-stage build: keeps the final image small and secure
# Stage 1 — compile the Go binary
FROM golang:1.22-alpine AS builder

WORKDIR /build
COPY app/main.go .
RUN go build -o server main.go

# Stage 2 — minimal runtime image
FROM alpine:3.19

RUN apk --no-cache add ca-certificates
WORKDIR /app

COPY --from=builder /build/server .

EXPOSE 8080

# Run as non-root for security
RUN adduser -D -u 1001 appuser
USER appuser

ENTRYPOINT ["./server"]
