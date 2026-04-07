FROM alpine:3.22.3

RUN apk add --no-cache redis

COPY redis.conf /etc/redis/redis.conf
COPY entrypoint.sh /entrypoint.sh

RUN mkdir -p /data && chown redis:redis /data \
    && chmod +x /entrypoint.sh

EXPOSE 6379

USER redis

ENTRYPOINT ["/entrypoint.sh"]
