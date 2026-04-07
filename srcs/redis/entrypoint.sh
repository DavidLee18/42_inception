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

REDIS_PASSWORD=$(read_secret "$REDIS_PASSWORD_FILE")

exec redis-server /etc/redis/redis.conf --requirepass "$REDIS_PASSWORD"
