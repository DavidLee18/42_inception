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

# Initialise the data directory only on first start
if [ ! -d "/var/lib/mariadb/mariadb" ]; then
    echo "Initialising MariaDB data directory..."
    mariadb-install-db --user=maria --datadir=/var/lib/mariadb --skip-test-db > /dev/null

    # Start a temporary server to run setup SQL
    mariadbd --user=maria --skip-networking --socket=/run/mariadbd/mariadbd.sock &
    TEMP_PID=$!

    # Wait until the socket is ready
    until mariadb-admin --socket=/run/mariadb/mariadbd.sock ping --silent; do
        sleep 0.2
    done

    # Bootstrap: set root password, create DB and user
    mariadb --socket=/run/mariadb/mariadb.sock <<-EOSQL
        ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
        CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
        GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
        FLUSH PRIVILEGES;
EOSQL

    # Shut the temporary server down cleanly
    kill "$TEMP_PID"
    wait "$TEMP_PID"
    echo "MariaDB initialisation complete."
fi

rm /etc/my.cnf.d/mariadb.server.cnf

exec "$@"
