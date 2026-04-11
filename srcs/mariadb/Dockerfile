FROM alpine:3.22.3

RUN apk add --no-cache \
    mariadb \
    mariadb-client

RUN addgroup -S maria \
    && adduser -S -D -H -G maria -s /sbin/nologin maria

# Create the data directory and set ownership
RUN mkdir -p /var/lib/mariadb /run/mariadbd \
    && chown -R maria:maria /var/lib/mariadb /run/mariadbd

# Copy custom config
COPY my.cnf /etc/my.cnf.d/custom.cnf

# Copy entrypoint that initialises the DB and reads Docker secrets
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3306

ENTRYPOINT ["/entrypoint.sh"]
CMD ["mariadbd", "--user=maria"]
