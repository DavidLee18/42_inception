FROM alpine:3.22.3

# ── Install all three components ─────────────────────────────────────────────
RUN apk add --no-cache \
    prometheus \
    grafana \
    supervisor

RUN mkdir -p /etc/grafana && touch /etc/grafana/grafana.ini
RUN echo -e "[paths]\nprovisioning = /etc/grafana/provisioning" > /etc/grafana/grafana.ini

# ── Prometheus configuration ─────────────────────────────────────────────────
COPY prometheus.yml /etc/prometheus/prometheus.yml

# ── Grafana provisioning (datasource + dashboard auto-wired at startup) ──────
COPY grafana/provisioning/datasources/prometheus.yml \
     /etc/grafana/provisioning/datasources/prometheus.yml
COPY grafana/provisioning/dashboards/dashboard.yml \
     /etc/grafana/provisioning/dashboards/dashboard.yml
RUN mkdir -p /etc/grafana/dashboards
COPY grafana/dashboards/docker.json \
     /etc/grafana/dashboards/docker.json

# ── Supervisord configuration ─────────────────────────────────────────────────
COPY supervisord.conf /etc/supervisord.conf

# Data directories
RUN mkdir -p /var/lib/prometheus /var/lib/grafana \
    && chown -R nobody:nobody /var/lib/prometheus \
    && chown -R grafana:grafana /var/lib/grafana 2>/dev/null || true

# Prometheus: 9090  Grafana: 3000
EXPOSE 9090 3000

CMD ["supervisord", "-c", "/etc/supervisord.conf", "-n"]
