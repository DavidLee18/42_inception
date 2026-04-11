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

DB_ROOT_PASSWORD=$(read_secret "$MYSQL_ROOT_PASSWORD_FILE")
DB_NAME=$(read_secret "$MYSQL_DATABASE_FILE")
DB_USER=$(read_secret "$MYSQL_USER_FILE")
DB_PASSWORD=$(read_secret "$MYSQL_PASSWORD_FILE")

INIT_MARKER="/var/lib/mariadb/.init_complete"

# Use a marker file instead of checking the data directory: mariadb-install-db
# may have succeeded on a previous (broken) run while the bootstrap SQL never ran.
if [ ! -f "$INIT_MARKER" ]; then
    # Only create the system tables if they don't already exist
    if [ ! -d "/var/lib/mariadb/mysql" ]; then
        echo "Initialising MariaDB data directory..."
        mariadb-install-db --user=maria --datadir=/var/lib/mariadb --skip-test-db > /dev/null
    fi

    # Start a temporary server to run setup SQL
    mariadbd --user=maria --skip-networking --socket=/run/mariadbd/mariadbd.sock &
    TEMP_PID=$!

    # Wait until the socket is ready
    until mariadb-admin --socket=/run/mariadbd/mariadbd.sock ping --silent; do
        sleep 0.2
    done

    # Bootstrap: create DB and user first, change root password last.
    # Keeping ALTER USER last ensures we can still connect via unix_socket
    # if a previous attempt crashed mid-way through this block.
    mariadb --socket=/run/mariadbd/mariadbd.sock <<-EOSQL
        CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
        GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
        FLUSH PRIVILEGES;
        ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
EOSQL

    # Shut the temporary server down cleanly
    kill "$TEMP_PID"
    wait "$TEMP_PID"

    touch "$INIT_MARKER"
    echo "MariaDB initialisation complete."
fi

exec "$@"
