FROM caddy:2-builder@sha256:401121e61853cb9c7df83cba43e532e49a68e30f32921c7bdcb7a4912168c067 AS builder
RUN xcaddy build --with github.com/caddy-dns/cloudflare

FROM caddy:2@sha256:504a44d7d74bd2bc28a66afc4774912fc21223ca8a67734af1c54ab2f999b489
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
