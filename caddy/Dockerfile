FROM caddy:2-builder AS builder
RUN xcaddy build --with github.com/caddy-dns/duckdns

FROM caddy:2-alpine
RUN addgroup -g 1000 pier && adduser -D -u 1000 -G pier pier
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
