FROM caddy:2-builder@sha256:b8f9c720f13f64c13dd42db28e8f38a3fab54c11fce4d93bda26d710c448dcfd AS builder
RUN xcaddy build --with github.com/caddy-dns/cloudflare

FROM caddy:2@sha256:844f60b64e4724a5aa8245e019dace0d3f199f7433ce6c57676cb30a920dbad9
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
