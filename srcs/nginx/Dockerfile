FROM alpine:3.22.3

RUN apk update && apk add --no-cache nginx openssl

COPY nginx.conf /etc/nginx/nginx.conf

RUN mkdir -p /etc/nginx/ssl /var/www/html

RUN openssl req -x509 -newkey rsa:4096 -sha256 -days 365 -nodes \
  -keyout /etc/nginx/ssl/server.key \
  -out /etc/nginx/ssl/server.crt \
  -subj "/CN=jaehylee.42.fr"

EXPOSE 443

CMD ["nginx", "-g", "daemon off;"]
