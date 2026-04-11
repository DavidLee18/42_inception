FROM alpine:3.22.3

RUN apk add --no-cache \
    php83 \
    php83-fpm \
    php83-mysqli \
    php83-pdo \
    php83-pdo_mysql \
    php83-opcache \
    php83-gd \
    php83-curl \
    php83-mbstring \
    php83-xml \
    php83-zip \
    php83-intl \
    php83-exif \
    php83-fileinfo \
    php83-tokenizer \
    php83-iconv \
    php83-session \
    php83-phar \
    php83-pecl-redis \
    curl \
    tar \
    netcat-openbsd

RUN ln -sf /usr/bin/php83 /usr/bin/php

ARG WP_VERSION=6.5.2
RUN mkdir -p /var/www
RUN curl -fsSL "https://wordpress.org/wordpress-${WP_VERSION}.tar.gz" \
    | tar -xz -C /var/www/ \
    && mv /var/www/wordpress /var/www/html \
    && chown -R nobody:nobody /var/www/html

# Install WP-CLI
RUN curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
        -o /usr/local/bin/wp \
    && chmod +x /usr/local/bin/wp

COPY php-fpm.conf /etc/php83/php-fpm.d/www.conf

# Entrypoint reads secrets and writes wp-config.php at runtime
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /var/www/html

EXPOSE 9000

ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm83", "-F"]
