#!/bin/sh
set -e

# Helper: read a secret file, die clearly if missing
read_secret() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "ERROR: secret file not found: $file" >&2
        exit 1
    fi
    cat "$file"
}

DB_NAME=$(read_secret "$WORDPRESS_DB_NAME_FILE")
DB_USER=$(read_secret "$WORDPRESS_DB_USER_FILE")
DB_PASSWORD=$(read_secret "$WORDPRESS_DB_PASSWORD_FILE")

# Write wp-config.php only if it doesn't already exist
if [ ! -f /var/www/html/wp-config.php ]; then
    cat > /var/www/html/wp-config.php <<EOF
<?php
define('DB_NAME',     '${DB_NAME}');
define('DB_USER',     '${DB_USER}');
define('DB_PASSWORD', '${DB_PASSWORD}');
define('DB_HOST',     '${WORDPRESS_DB_HOST}');
define('DB_CHARSET',  'utf8mb4');
define('DB_COLLATE',  '');

\$table_prefix = 'wp_';

define('WP_DEBUG', false);
define('WP_HOME',  'https://jaehylee.42.fr');
define('WP_SITEURL','https://jaehylee.42.fr');

if (!defined('ABSPATH')) {
    define('ABSPATH', __DIR__ . '/');
}

require_once ABSPATH . 'wp-settings.php';
EOF
    # Fetch fresh salts from WordPress API
    SALTS=$(curl -fsSL https://api.wordpress.org/secret-key/1.1/salt/)
    echo "$SALTS" >> /var/www/html/wp-config.php

    chown nobody:nobody /var/www/html/wp-config.php
    chmod 640 /var/www/html/wp-config.php
fi

exec "$@"
