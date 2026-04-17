#!/bin/sh
set -e

# Substitute Docker metrics target in prometheus.yml
if [ -z "$DOCKER_METRICS_HOST" ]; then
    echo "ERROR: DOCKER_METRICS_HOST is not set." >&2
    exit 1
fi
sed -i "s|\$DOCKER_METRICS_HOST|${DOCKER_METRICS_HOST}|g" \
    /etc/prometheus/prometheus.yml

exec "$@"
