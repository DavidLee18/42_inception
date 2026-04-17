#!/bin/sh
set -e

read_secret() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "ERROR: secret file not found: $file" >&2
        exit 1
    fi
    cat "$file"
}

# ── Read all secrets ────────────────────────────────────────────────────────
DB_NAME=$(read_secret "$WORDPRESS_DB_NAME_FILE")
DB_USER=$(read_secret "$WORDPRESS_DB_USER_FILE")
DB_PASSWORD=$(read_secret "$WORDPRESS_DB_PASSWORD_FILE")
REDIS_PASSWORD=$(read_secret "$REDIS_PASSWORD_FILE")

WP_ADMIN_USER=$(read_secret "$WP_ADMIN_USER_FILE")
WP_ADMIN_PASSWORD=$(read_secret "$WP_ADMIN_PASSWORD_FILE")
WP_ADMIN_EMAIL=$(read_secret "$WP_ADMIN_EMAIL_FILE")
WP_USER=$(read_secret "$WP_USER_FILE")
WP_USER_PASSWORD=$(read_secret "$WP_USER_PASSWORD_FILE")
WP_USER_EMAIL=$(read_secret "$WP_USER_EMAIL_FILE")

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
define('DB_HOST',     '${WORDPRESS_DB_HOST}');
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

define('WP_REDIS_HOST',     '${REDIS_HOST:-redis}');
define('WP_REDIS_PORT',     ${REDIS_PORT:-6379});
define('WP_REDIS_PASSWORD', '${REDIS_PASSWORD}');
define('WP_REDIS_TIMEOUT',  1);
define('WP_REDIS_DATABASE', 0);

\$table_prefix = 'wp_';

define('WP_DEBUG',   false);
define('WP_HOME',    'https://${DOMAIN_NAME}');
define('WP_SITEURL', 'https://${DOMAIN_NAME}');

if (!defined('ABSPATH')) {
    define('ABSPATH', __DIR__ . '/');
}

require_once ABSPATH . 'wp-settings.php';
EOF

    chown nobody:nobody /var/www/html/wp-config.php
    chmod 640 /var/www/html/wp-config.php
fi

# ── Wait for MariaDB to be ready ────────────────────────────────────────────
echo "Waiting for MariaDB..."
until nc -z ${DB_HOST} ${DB_PORT} 2>/dev/null; do
    sleep 1
done
echo "MariaDB is up."

# ── Install WordPress core and create users (first start only) ──────────────
if ! wp core is-installed --allow-root --path=/var/www/html > /dev/null 2>&1; then
    echo "Installing WordPress core..."
    wp core install \
        --allow-root \
        --path=/var/www/html \
        --url="https://${DOMAIN_NAME}" \
        --title="Inception" \
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
