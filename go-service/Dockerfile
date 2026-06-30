# ── Stage 1: Build ──────────────────────────────────────────
FROM golang:1.22-alpine AS builder

WORKDIR /build
COPY go.mod .
RUN go mod download

COPY main.go .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o admin .

# ── Stage 2: Minimal runtime ──────────────────────────────
FROM scratch

COPY --from=builder /build/admin /admin

EXPOSE 8080
ENTRYPOINT ["/admin"]
