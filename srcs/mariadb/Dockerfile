FROM alpine:3.22.4

RUN apk add --no-cache \
    mariadb \
    mariadb-client

RUN addgroup -S maria \
    && adduser -S -D -H -G maria -s /sbin/nologin maria

# Create the data directory and set ownership
RUN mkdir -p /var/lib/mariadb /run/mariadbd \
    && chown -R maria:maria /var/lib/mariadb /run/mariadbd

# Remove the default config (sets port=0 / skip-networking) and copy ours
RUN rm -f /etc/my.cnf.d/mariadb-server.cnf
COPY my.cnf /etc/my.cnf.d/custom.cnf

# Copy entrypoint that initialises the DB and reads Docker secrets
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3306

ENTRYPOINT ["/entrypoint.sh"]
CMD ["mariadbd", "--user=maria"]
