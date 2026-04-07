FROM alpine:3.22.3

RUN apk update && apk add --no-cache mariadb mariadb-client
RUN mariadb-install-db --user=mysql --datadir=/var/lib/mysql

VOLUME ["/var/lib/mysql"]

EXPOSE 3306

ENTRYPOINT ["mariadbd", "--user=mysql", "--datadir=/var/lib/mysql"]
