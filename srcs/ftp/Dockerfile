FROM alpine:3.22.4

RUN apk add --no-cache vsftpd linux-pam

# Ship config as a template — entrypoint renders it with env values at runtime
COPY vsftpd.conf /etc/vsftpd/vsftpd.conf.template

RUN mkdir -p /var/run/vsftpd/empty
RUN mkdir -p /etc/pam.d
RUN echo 'auth required pam_unix.so' > /etc/pam.d/vsftpd && \
    echo 'account required pam_unix.so' >> /etc/pam.d/vsftpd && \
    echo 'session required pam_unix.so' >> /etc/pam.d/vsftpd

# Copy entrypoint that reads secrets and creates the FTP user
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Passive port range (must match vsftpd.conf and exposed ports)
EXPOSE 21 21100-21110

ENTRYPOINT ["/entrypoint.sh"]
CMD ["vsftpd", "/etc/vsftpd/vsftpd.conf"]
