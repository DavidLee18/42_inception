#!/bin/sh
set -e

read_secret() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "ERROR: secret file not found: $file" >&2
        exit 1
    fi
    tr -d '\r\n' < "$file"
}

# ── Validate required env (wired via env_file: .env) ────────────────────────
: "${DOMAIN_NAME:?DOMAIN_NAME must be set (from .env)}"
: "${DB_HOST:?DB_HOST must be set (from .env)}"
: "${DB_PORT:?DB_PORT must be set (from .env)}"
: "${REDIS_HOST:?REDIS_HOST must be set (from .env)}"
: "${REDIS_PORT:?REDIS_PORT must be set (from .env)}"
: "${WP_TITLE:=Inception}"

SITE_URL="https://${DOMAIN_NAME}:8443"

# ── Read all secrets ────────────────────────────────────────────────────────
DB_NAME=$(read_secret /run/secrets/db_name)
DB_USER=$(read_secret /run/secrets/db_user)
DB_PASSWORD=$(read_secret /run/secrets/db_password)
REDIS_PASSWORD=$(read_secret /run/secrets/redis_password)
WP_ADMIN_USER=$(read_secret /run/secrets/wp_admin_user)
WP_ADMIN_PASSWORD=$(read_secret /run/secrets/wp_admin_password)
WP_ADMIN_EMAIL=$(read_secret /run/secrets/wp_admin_email)
WP_USER=$(read_secret /run/secrets/wp_user)
WP_USER_PASSWORD=$(read_secret /run/secrets/wp_user_password)
WP_USER_EMAIL=$(read_secret /run/secrets/wp_user_email)

# ── Guard: admin username must not contain 'admin' (case-insensitive) ───────
echo "$WP_ADMIN_USER" | grep -qi "admin" && {
    echo "ERROR: admin username '${WP_ADMIN_USER}' must not contain 'admin'." >&2
    exit 1
}

# ── Write wp-config.php on first start ──────────────────────────────────────
if [ ! -f /var/www/html/wp-config.php ]; then
    echo "Generating wp-config.php..."

    # Part 1: DB config (needs shell variable expansion)
    cat > /var/www/html/wp-config.php <<EOF
<?php
define('DB_NAME',     '${DB_NAME}');
define('DB_USER',     '${DB_USER}');
define('DB_PASSWORD', '${DB_PASSWORD}');
define('DB_HOST',     '${DB_HOST}:${DB_PORT}');
define('DB_CHARSET',  'utf8mb4');
define('DB_COLLATE',  '');

EOF

    # Part 2: Salts (fetched verbatim — must NOT go through shell expansion
    # because the values contain $ signs). Placed before wp-settings.php
    # so the constants are defined when WordPress reads them.
    curl -fsSL https://api.wordpress.org/secret-key/1.1/salt/ \
        >> /var/www/html/wp-config.php

    # Part 3: Remaining config
    cat >> /var/www/html/wp-config.php <<EOF

define('WP_REDIS_HOST',     '${REDIS_HOST}');
define('WP_REDIS_PORT',     ${REDIS_PORT});
define('WP_REDIS_PASSWORD', '${REDIS_PASSWORD}');
define('WP_REDIS_TIMEOUT',  1);
define('WP_REDIS_DATABASE', 0);

\$table_prefix = 'wp_';


define('WP_DEBUG', true);
define('WP_DEBUG_LOG', '/dev/stderr');
define('WP_DEBUG_DISPLAY', false);
define('WP_HOME',    '${SITE_URL}');
define('WP_SITEURL', '${SITE_URL}');

if (!defined('ABSPATH')) {
    define('ABSPATH', __DIR__ . '/');
}

require_once ABSPATH . 'wp-settings.php';
EOF

    chmod 644 /var/www/html/wp-config.php
fi

# ── Wait for MariaDB to be ready ────────────────────────────────────────────
echo "Waiting for MariaDB at ${DB_HOST}:${DB_PORT}..."
until nc -z "${DB_HOST}" "${DB_PORT}" 2>/dev/null; do
    sleep 1
done
echo "MariaDB is up."

# ── Install WordPress core and create users (first start only) ──────────────
if ! wp core is-installed --allow-root --path=/var/www/html > /dev/null 2>&1; then
    echo "Installing WordPress core..."
    wp core install \
        --allow-root \
        --path=/var/www/html \
        --url="${SITE_URL}" \
        --title="${WP_TITLE}" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --skip-email

    echo "Creating subscriber user..."
    wp user create \
        --allow-root \
        --path=/var/www/html \
        "${WP_USER}" "${WP_USER_EMAIL}" \
        --role=subscriber \
        --user_pass="${WP_USER_PASSWORD}"

    echo "WordPress installed. Users created:"
    wp user list --allow-root --path=/var/www/html

    # ── Install and enable Redis object cache ────────────────────────────────
    echo "Installing WP Redis plugin..."
    wp plugin install redis-cache \
        --activate \
        --allow-root \
        --path=/var/www/html
    wp redis enable --allow-root --path=/var/www/html

    # Fix ownership — wp-cli ran as root but php-fpm runs as nobody
    chown -R nobody:nobody /var/www/html/wp-content
fi

exec "$@"
