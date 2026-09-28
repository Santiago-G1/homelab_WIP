# The official caddy image does not ship DNS providers, and the wildcard
# certificate (*.{$DOMAINNAME_HS}) can only be issued through the DNS-01
# challenge, so the Cloudflare module is compiled in here.
FROM caddy:2-builder AS builder
RUN xcaddy build --with github.com/caddy-dns/cloudflare

FROM caddy:2
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
