#!/bin/sh
set -e

read_secret() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "ERROR: secret file not found: $file" >&2
        exit 1
    fi
    tr -d '\r\n' < "$file"
}

# ── Validate required env (wired via env_file: .env) ────────────────────────
: "${DOMAIN_NAME:?DOMAIN_NAME must be set (from .env)}"

FTP_USER=$(read_secret /run/secrets/ftp_user)
FTP_PASSWORD=$(read_secret /run/secrets/ftp_password)

# Validate: user must not be root
if [ "$FTP_USER" = "root" ]; then
    echo "ERROR: FTP user cannot be root." >&2
    exit 1
fi

# ── Render vsftpd.conf from template on every start ─────────────────────────
cp /etc/vsftpd/vsftpd.conf.template /etc/vsftpd/vsftpd.conf
# sed -i -e "s|__DOMAIN_NAME__|${DOMAIN_NAME}|g" /etc/vsftpd/vsftpd.conf

# Create the FTP user if it does not exist
if ! id "$FTP_USER" > /dev/null 2>&1; then
    echo "Creating FTP user '${FTP_USER}'..."
    adduser -h /var/www/html -s /sbin/nologin -D "$FTP_USER"
    echo "${FTP_USER}:${FTP_PASSWORD}" | chpasswd
fi

chown -R "${FTP_USER}:${FTP_USER}" /var/www/html

exec "$@"
