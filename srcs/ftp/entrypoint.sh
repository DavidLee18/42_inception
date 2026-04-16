#!/bin/sh
set -e

read_secret() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "ERROR: secret file not found: $file" >&2
        exit 1
    fi
    cat "$file"
}

FTP_USER=$(read_secret "$FTP_USER_FILE")
FTP_PASSWORD=$(read_secret "$FTP_PASSWORD_FILE")

# Validate: user must not be root
if [ "$FTP_USER" = "root" ]; then
    echo "ERROR: FTP user cannot be root." >&2
    exit 1
fi

# Substitute pasv_address with runtime env var
if [ -z "$DOMAIN_NAME" ]; then
    echo "ERROR: DOMAIN_NAME is not set." >&2
    exit 1
fi
sed -i "s|pasv_address=.*|pasv_address=${DOMAIN_NAME}|" \
    /etc/vsftpd/vsftpd.conf

# Create the FTP user if it does not exist
if ! id "$FTP_USER" > /dev/null 2>&1; then
    echo "Creating FTP user '${FTP_USER}'..."
    adduser -h /var/www/html -s /sbin/nologin -D "$FTP_USER"
    echo "${FTP_USER}:${FTP_PASSWORD}" | chpasswd
fi

chown -R "${FTP_USER}:${FTP_USER}" /var/www/html

exec "$@"
