FROM caddy:2-builder@sha256:bf6a7d38add2508b7d2e3e3f40cf2af399214f143c0fa3daa51f254e01f8d293 AS builder
RUN xcaddy build --with github.com/caddy-dns/cloudflare

FROM caddy:2@sha256:4851e54a46b206517c574821bb5cc67f170d2156041e9fbc4c9193b45e84a75b
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
