FROM caddy:2-builder@sha256:c2fc374fd352439d76e1777b28d97d9f6d9c1dd86116db9227460374d46097d5 AS builder
RUN xcaddy build --with github.com/caddy-dns/cloudflare

FROM caddy:2@sha256:14a9c00d4e833ebc2b65d36515b37bde3b73f0b323a2663aaafc88953d8c4e3f
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
