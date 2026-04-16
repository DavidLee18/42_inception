#!/bin/sh
set -e

# Substitute Docker metrics target in prometheus.yml
if [ -z "$DOCKER_METRICS_HOST" ]; then
    echo "ERROR: DOCKER_METRICS_HOST is not set." >&2
    exit 1
fi
sed -i "s|host-gateway:9323|${DOCKER_METRICS_HOST}|" \
    /etc/prometheus/prometheus.yml

exec "$@"
