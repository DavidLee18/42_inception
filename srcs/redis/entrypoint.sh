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

# Suppress Redis memory overcommit warning (silently ignored if unprivileged)
sysctl vm.overcommit_memory=1 2>/dev/null || true

exec su-exec redis redis-server /etc/redis/redis.conf --requirepass "$REDIS_PASSWORD"
