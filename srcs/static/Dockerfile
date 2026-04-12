# ── Stage 1: build ──────────────────────────────────────────────────────────
FROM alpine:3.22.3 AS builder

RUN apk update && apk add --no-cache cbqn

COPY site/ /build/site/
COPY template.bqn /build

RUN cbqn /build/template.bqn < /build/site/template.html > /build/site/index.html

# ── Stage 2: serve ──────────────────────────────────────────────────────────
FROM alpine:3.22.3

RUN apk update && apk add --no-cache nginx

COPY nginx.conf /etc/nginx/nginx.conf

# Pull only the compiled output from the builder stage
COPY --from=builder /build/site/index.html /var/www/static/index.html
COPY --from=builder /build/site/style.css /var/www/static/
# COPY --from=builder /var/log/barbell.log /var/log/

RUN mkdir -p /var/run/nginx

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
