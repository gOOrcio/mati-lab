FROM caddy:2-builder@sha256:bf6a7d38add2508b7d2e3e3f40cf2af399214f143c0fa3daa51f254e01f8d293 AS builder
RUN xcaddy build --with github.com/caddy-dns/cloudflare

FROM caddy:2@sha256:ce773ec7a742ce15ee6bf2bb5f65882b9e2a4487b10733e6f1484f86e6b5d8bc
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
