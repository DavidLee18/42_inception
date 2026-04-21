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

REDIS_PASSWORD=$(read_secret /run/secrets/redis_password)

# Suppress Redis memory overcommit warning (silently ignored if unprivileged)
sysctl vm.overcommit_memory=1 2>/dev/null || true

exec su-exec redis redis-server /etc/redis/redis.conf --requirepass "$REDIS_PASSWORD"
