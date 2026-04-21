FROM alpine:3.22.4

RUN apk add --no-cache \
    php83 \
    php83-fpm \
    php83-session \
    php83-mysqli \
    php83-pdo \
    php83-pdo_mysql \
    php83-json \
    nginx \
    curl

RUN ln -sf /usr/bin/php83 /usr/bin/php

# Download Adminer single-file app
ARG ADMINER_VERSION=4.8.1
RUN mkdir -p /var/www/adminer \
    && curl -fsSL "https://github.com/vrana/adminer/releases/download/v${ADMINER_VERSION}/adminer-${ADMINER_VERSION}.php" \
       -o /var/www/adminer/index.php \
    && chown -R nobody:nobody /var/www/adminer

COPY nginx.conf /etc/nginx/nginx.conf
COPY php-fpm.conf /etc/php83/php-fpm.d/www.conf

EXPOSE 8081

# Start both php-fpm and nginx
CMD ["sh", "-c", "php-fpm83 -F & nginx -g 'daemon off;'"]
