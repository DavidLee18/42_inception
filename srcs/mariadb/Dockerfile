FROM alpine:3.22.3

RUN apk add --no-cache \
    mariadb \
    mariadb-client

# Create the data directory and set ownership
RUN mkdir -p /var/lib/mysql /run/mysqld \
    && chown -R mysql:mysql /var/lib/mysql /run/mysqld

# Copy custom config
COPY my.cnf /etc/my.cnf.d/custom.cnf

# Copy entrypoint that initialises the DB and reads Docker secrets
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3306

ENTRYPOINT ["/entrypoint.sh"]
CMD ["mariadbd", "--user=mysql", "--port=3306", "--bind-address=0.0.0.0"]
