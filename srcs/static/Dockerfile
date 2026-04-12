# ── Stage 1: build ──────────────────────────────────────────────────────────
FROM alpine:3.22.3 AS builder

RUN apk add --no-cache pandoc bash nix nix-openrc

WORKDIR /build

RUN rc-update add nix-daemon && rc-service nix-daemon start

RUN addgroup $USER nix

# Copy all site source files
COPY site/ ./site/
RUN nix run github:jhvst/barbell -- ./site/template.html

# ── Stage 2: serve ──────────────────────────────────────────────────────────
FROM alpine:3.22.3

RUN apk add --no-cache nginx

COPY nginx.conf /etc/nginx/nginx.conf

# Pull only the compiled output from the builder stage
COPY --from=builder /build/site/template.html /var/www/static/index.html
COPY --from=builder /build/site/style.css /var/www/static/

RUN mkdir -p /var/run/nginx

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
