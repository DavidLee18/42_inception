#!/bin/sh
set -e

# ── Validate required env (wired via env_file: .env) ────────────────────────
: "${DOMAIN_NAME:?DOMAIN_NAME must be set (from .env)}"
: "${WP_HOST:?WP_HOST must be set (from .env)}"
: "${WP_FPM_PORT:?WP_FPM_PORT must be set (from .env)}"

# ── Render nginx.conf from template on every start ──────────────────────────
# Re-rendering each time means changes to .env take effect on container restart
# without a rebuild, and there are no stale substitutions.
cp /etc/nginx/nginx.conf.template /etc/nginx/nginx.conf
sed -i \
    -e "s|__DOMAIN_NAME__|${DOMAIN_NAME}|g" \
    -e "s|__WP_UPSTREAM__|${WP_HOST}:${WP_FPM_PORT}|g" \
    /etc/nginx/nginx.conf

# ── Generate self-signed TLS cert on first start only ───────────────────────
if [ ! -f /etc/nginx/ssl/server.crt ]; then
    echo "Generating self-signed TLS cert for CN=${DOMAIN_NAME}..."
    openssl req -x509 -newkey rsa:4096 -sha256 -days 365 -nodes \
        -keyout /etc/nginx/ssl/server.key \
        -out    /etc/nginx/ssl/server.crt \
        -subj   "/CN=${DOMAIN_NAME}"
fi

exec "$@"
