#!/usr/bin/env python3
"""
Lightweight container metrics exporter.
Queries the Docker Engine API via /var/run/docker.sock and serves
Prometheus-format metrics on :8080/metrics.
"""

import http.server
import json
import socket
import threading
import time

DOCKER_SOCKET = "/var/run/docker.sock"
LISTEN_PORT = 8080
SCRAPE_INTERVAL = 5  # seconds


def docker_api(path):
    """Send an HTTP GET to the Docker Engine API over the Unix socket."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(10)
    sock.connect(DOCKER_SOCKET)
    request = f"GET {path} HTTP/1.0\r\nHost: localhost\r\n\r\n"
    sock.sendall(request.encode())
    chunks = []
    while True:
        try:
            data = sock.recv(65536)
            if not data:
                break
            chunks.append(data)
        except socket.timeout:
            break
    sock.close()
    raw = b"".join(chunks).decode("utf-8", errors="replace")
    # Split headers from body
    parts = raw.split("\r\n\r\n", 1)
    if len(parts) < 2:
        return None
    body = parts[1]
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        return None


def collect_metrics():
    """Collect per-container metrics from the Docker API."""
    containers = docker_api("/containers/json")
    if not containers:
        return ""

    lines = []

    # Header comments
    lines.append(
        "# HELP container_cpu_usage_seconds_total Cumulative CPU time consumed in seconds."
    )
    lines.append("# TYPE container_cpu_usage_seconds_total counter")
    lines.append("# HELP container_memory_usage_bytes Current memory usage in bytes.")
    lines.append("# TYPE container_memory_usage_bytes gauge")
    lines.append("# HELP container_network_receive_bytes_total Network bytes received.")
    lines.append("# TYPE container_network_receive_bytes_total counter")
    lines.append(
        "# HELP container_network_transmit_bytes_total Network bytes transmitted."
    )
    lines.append("# TYPE container_network_transmit_bytes_total counter")
    lines.append("# HELP container_blkio_device_usage_total Block I/O bytes.")
    lines.append("# TYPE container_blkio_device_usage_total counter")

    for c in containers:
        cid = c["Id"]
        # Container name: strip leading '/'
        names = c.get("Names", ["/unknown"])
        name = names[0].lstrip("/")

        stats = docker_api(f"/containers/{cid}/stats?stream=false&one-shot=true")
        if not stats:
            continue

        # ── CPU ──────────────────────────────────────────────────────
        cpu = stats.get("cpu_stats", {})
        cpu_usage = cpu.get("cpu_usage", {})
        total_usage_ns = cpu_usage.get("total_usage", 0)
        cpu_seconds = total_usage_ns / 1e9
        lines.append(
            f'container_cpu_usage_seconds_total{{name="{name}"}} {cpu_seconds:.6f}'
        )

        # ── Memory ───────────────────────────────────────────────────
        mem = stats.get("memory_stats", {})
        mem_usage = mem.get("usage", 0)
        lines.append(f'container_memory_usage_bytes{{name="{name}"}} {mem_usage}')

        # ── Network ──────────────────────────────────────────────────
        networks = stats.get("networks", {})
        rx_total = 0
        tx_total = 0
        for iface, net_stats in networks.items():
            rx_total += net_stats.get("rx_bytes", 0)
            tx_total += net_stats.get("tx_bytes", 0)
        lines.append(
            f'container_network_receive_bytes_total{{name="{name}"}} {rx_total}'
        )
        lines.append(
            f'container_network_transmit_bytes_total{{name="{name}"}} {tx_total}'
        )

        # ── Block I/O ────────────────────────────────────────────────
        blkio = stats.get("blkio_stats", {})
        io_service = blkio.get("io_service_bytes_recursive", []) or []
        read_bytes = 0
        write_bytes = 0
        for entry in io_service:
            op = entry.get("op", "").lower()
            if op == "read":
                read_bytes += entry.get("value", 0)
            elif op == "write":
                write_bytes += entry.get("value", 0)
        lines.append(
            f'container_blkio_device_usage_total{{name="{name}",op="Read"}} {read_bytes}'
        )
        lines.append(
            f'container_blkio_device_usage_total{{name="{name}",op="Write"}} {write_bytes}'
        )

    return "\n".join(lines) + "\n"


# ── Cached metrics (refreshed in background) ────────────────────────────────
_metrics_cache = ""
_cache_lock = threading.Lock()


def background_collector():
    global _metrics_cache
    while True:
        try:
            result = collect_metrics()
            with _cache_lock:
                _metrics_cache = result
        except Exception as e:
            print(f"[exporter] collection error: {e}", flush=True)
        time.sleep(SCRAPE_INTERVAL)


class MetricsHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics":
            with _cache_lock:
                body = _metrics_cache
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
            self.end_headers()
            self.wfile.write(body.encode())
        else:
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Container Metrics Exporter. Use /metrics\n")

    def log_message(self, fmt, *args):
        # Suppress per-request logging noise
        pass


if __name__ == "__main__":
    print(
        f"[exporter] starting background collector (interval={SCRAPE_INTERVAL}s)",
        flush=True,
    )
    t = threading.Thread(target=background_collector, daemon=True)
    t.start()

    # Let the first collection finish before serving
    time.sleep(SCRAPE_INTERVAL + 1)

    print(f"[exporter] listening on :{LISTEN_PORT}/metrics", flush=True)
    server = http.server.HTTPServer(("0.0.0.0", LISTEN_PORT), MetricsHandler)
    server.serve_forever()
