# ── Stage 1: build ──────────────────────────────────────────────────────────
FROM alpine:3.22.3 AS builder

RUN apk update && apk add --no-cache \
    bash coreutils curl tar sed xz gnupg sudo shadow bash-completion

RUN addgroup -g 1000 nixuser && \
    adduser -D -u 1000 -G nixuser -s /bin/bash nixuser && \
    echo "nixuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    mkdir -m 0755 /nix && chown nixuser:nixuser /nix

USER nixuser
WORKDIR /home/nixuser
ENV HOME=/home/nixuser USER=nixuser

RUN mkdir -p ~/.config/nix && \
    echo 'sandbox = false' >> ~/.config/nix/nix.conf && \
    echo 'filter-syscalls = false' >> ~/.config/nix/nix.conf

RUN curl -L https://nixos.org/nix/install | bash -s -- --no-daemon

RUN . /home/nixuser/.nix-profile/etc/profile.d/nix.sh && \
    nix-channel --update

ENV PATH=/home/nixuser/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/nix/var/nix/profiles/default/sbin:$PATH \
    NIX_PATH=/nix/var/nix/profiles/per-user/nixuser/channels

RUN echo ". /home/nixuser/.nix-profile/etc/profile.d/nix.sh" >> ~/.bashrc


RUN nix-env --version

USER root
RUN rm -rf /var/cache/apk/*

USER nixuser
WORKDIR /build

# Copy all site source files
COPY site/ ./site/
RUN nix run github:jhvst/barbell \
    --extra-experimental-features nix-command \
    --extra-experimental-features flakes \
    -- ./site/template.html

# ── Stage 2: serve ──────────────────────────────────────────────────────────
FROM alpine:3.22.3

RUN apk update && apk add --no-cache nginx

COPY nginx.conf /etc/nginx/nginx.conf

# Pull only the compiled output from the builder stage
COPY --from=builder /build/site/template.html /var/www/static/index.html
COPY --from=builder /build/site/style.css /var/www/static/

RUN mkdir -p /var/run/nginx

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
