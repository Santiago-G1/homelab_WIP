# The upstream image ships no DNS provider and the wildcard certificate needs
# DNS-01, so the Cloudflare module is compiled in. Both stages are pinned:
# `xcaddy build` alone compiles whatever tag was newest that day.
FROM caddy:2.11.4-builder AS builder
RUN xcaddy build v2.11.4 --with github.com/caddy-dns/cloudflare@v0.2.4

FROM caddy:2.11.4
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
