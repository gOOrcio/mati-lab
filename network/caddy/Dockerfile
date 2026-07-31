FROM caddy:2-builder@sha256:c54715e63a99f6bc427f6733749b71dd48fc036f9c4fcda10aa29fb278518ee0 AS builder
RUN xcaddy build --with github.com/caddy-dns/cloudflare

FROM caddy:2@sha256:844f60b64e4724a5aa8245e019dace0d3f199f7433ce6c57676cb30a920dbad9
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
