FROM alpine:3.22.4

RUN apk update && apk add --no-cache nginx openssl

RUN ln -sf /dev/stdout /var/log/nginx/access.log \
 && ln -sf /dev/stderr /var/log/nginx/error.log

# Ship config as a template — entrypoint renders it with env values at runtime
COPY nginx.conf /etc/nginx/nginx.conf.template

RUN mkdir -p /etc/nginx/ssl /var/www/html

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 443

ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
