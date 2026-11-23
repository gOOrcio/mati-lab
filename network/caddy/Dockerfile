FROM caddy:2-builder@sha256:cda07fe9d82728c7ac44d844306d435e98131423dc7b114f05a8a8ecfff94707 AS builder
RUN xcaddy build --with github.com/caddy-dns/cloudflare

FROM caddy:2@sha256:5e5286cb37d44086d651a5363f05f43a692ce4d649d88fb1bd844579f45fa9e8
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
