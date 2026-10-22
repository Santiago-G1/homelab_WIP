# The official caddy image does not ship DNS providers, and the wildcard
# certificate (*.{$DOMAINNAME_HS}) can only be issued through the DNS-01
# challenge, so the Cloudflare module is compiled in here.
# Both stages are pinned to the Caddy release the lab runs: `xcaddy build` on its
# own compiles the newest upstream tag, which would make the proxy's version
# depend on the day the image was built.
FROM caddy:2.11.4-builder AS builder
RUN xcaddy build v2.11.4 --with github.com/caddy-dns/cloudflare@v0.2.4

FROM caddy:2.11.4
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
