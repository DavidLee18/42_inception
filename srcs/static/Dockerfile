# ── Stage 1: build ──────────────────────────────────────────────────────────
FROM alpine:3.22.3 AS builder

RUN apk add --no-cache pandoc bash

WORKDIR /build

# Copy all site source files
COPY site/ ./site/
COPY build.sh ./build.sh
RUN chmod +x build.sh && ./build.sh

# ── Stage 2: serve ──────────────────────────────────────────────────────────
FROM alpine:3.22.3

RUN apk add --no-cache nginx

COPY nginx.conf /etc/nginx/nginx.conf

# Pull only the compiled output from the builder stage
COPY --from=builder /build/out/ /var/www/static/

RUN mkdir -p /var/run/nginx

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
