# NetworkMonitor

A self-contained network monitoring stack for home and SOHO networks, built on Prometheus, Grafana, Blackbox Exporter, and Node Exporter. Runs on any Linux host — including **Firewalla**, **TrueNAS Scale**, Raspberry Pi, or any x86-64/ARM64 machine — using Docker Compose.

## What it monitors

| Probe type | What it checks |
|---|---|
| **ICMP ping** | Reachability + round-trip latency to any host |
| **DNS** | Query time for UDP DNS resolvers |
| **HTTP/HTTPS** | 2xx response, SSL cert validity + expiry |
| **TCP** | Port reachability (SSH, HTTPS, DNS-over-TCP, etc.) |
| **Host interfaces** | Per-interface bandwidth, packet errors, interface up/down state |

## Prerequisites

- Docker Engine 24+ and Docker Compose v2 (`docker compose` not `docker-compose`)
- A Linux host (x86-64 or ARM64)
- Outbound internet access for pulling images on first run

## Quick start

```bash
# 1. Clone the repo
git clone https://github.com/sharbron/NetworkMonitor.git
cd NetworkMonitor

# 2. Configure secrets and settings
cp .env.example .env
$EDITOR .env          # set GF_SECURITY_ADMIN_PASSWORD, PROMETHEUS_SITE, and alert credentials

# 3. Add your targets
$EDITOR targets.yml   # add your hosts/IPs/URLs

# 4. Run setup (downloads dashboards, creates data dirs, generates config)
chmod +x setup.sh && ./setup.sh

# 5. Start the stack
docker compose up -d
```

> **Re-run `./setup.sh` after editing `.env`** to regenerate config files with your updated values.

Open Grafana at **http://localhost:3000** (or your host IP).

## Default ports

| Service | Port | URL |
|---|---|---|
| Grafana | 3000 | http://localhost:3000 |
| Prometheus | 9090 | http://localhost:9090 |
| Alertmanager | 9093 | http://localhost:9093 |
| Blackbox Exporter | 9115 | http://localhost:9115 |
| Node Exporter | 9100 | http://localhost:9100/metrics |

All ports are configurable in `.env`.

## Adding monitoring targets

Edit `targets.yml` — the only file you need to touch for day-to-day changes. Prometheus watches this file and picks up changes automatically within 30 seconds. **No container restart needed.**

```yaml
# Ping a new host
- targets:
    - 192.168.1.50      # NAS
  labels:
    job: icmp_ping

# Monitor an internal web UI
- targets:
    - http://192.168.1.50:8080
  labels:
    job: http_probe
```

The four `job` label values Prometheus recognises are:

| Label | Probe type |
|---|---|
| `icmp_ping` | ICMP ping |
| `dns_probe` | DNS UDP query |
| `http_probe` | HTTP/HTTPS GET |
| `tcp_probe` | TCP connect |

## Alerting setup

Alerts are pre-configured in `prometheus/rules/`. They fire via **Alertmanager**, which routes to Slack and/or email.

Fill in `.env` with your credentials:

```bash
# Slack
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
SLACK_CHANNEL=#network-alerts

# Email (example: Gmail app password)
SMTP_SMARTHOST=smtp.gmail.com:587
SMTP_FROM=alerts@example.com
SMTP_AUTH_USERNAME=alerts@example.com
SMTP_AUTH_PASSWORD=your_app_password
ALERT_EMAIL_TO=you@example.com
```

Then restart Alertmanager to pick up the changes:

```bash
docker compose restart alertmanager
```

If you don't want external notifications, leave those fields as-is — alerts still appear in the Alertmanager UI at http://localhost:9093.

### Alert rules summary

**Probe alerts** (`prometheus/rules/blackbox_alerts.yml`):
- `ProbeFailed` — target unreachable for 2+ minutes (critical)
- `HighPingLatency` — average ping >200ms over 5 min (warning)
- `SlowHTTPResponse` — average HTTP response >2s over 5 min (warning)
- `HTTPBadStatusCode` — non-2xx HTTP status for 2+ minutes (critical)
- `SSLCertExpiringSoon` — cert expires within 30 days (warning)
- `SSLCertExpired` — cert already expired (critical)
- `SlowDNSResolution` — average DNS query >500ms over 5 min (warning)

**Host alerts** (`prometheus/rules/node_alerts.yml.template`):
- `HighInboundBandwidth` — interface receiving >`BANDWIDTH_THRESHOLD_MBPS` Mbps for 5 min (warning)
- `HighOutboundBandwidth` — interface sending >`BANDWIDTH_THRESHOLD_MBPS` Mbps for 5 min (warning)
- `NetworkInterfaceDown` — interface down for 1+ minute (critical)
- `HighPacketErrors` — receive errors >10/sec for 5 min (warning)
- `NodeExporterDown` — node_exporter unreachable for 1 min (critical)

Set `BANDWIDTH_THRESHOLD_MBPS` in `.env` to match your link speed (default: `800`). Re-run `./setup.sh` to apply.

> **Grafana monitoring:** The `ProbeFailed` alert also covers Grafana itself — Prometheus probes `http://grafana:3000/api/health` every 30 seconds and fires if it's unreachable for 2+ minutes.

## Grafana dashboards

Two community dashboards load automatically via Grafana provisioning:

| Dashboard | Grafana ID | What it shows |
|---|---|---|
| Node Exporter Full | [1860](https://grafana.com/grafana/dashboards/1860) | CPU, memory, disk, per-interface bandwidth |
| Prometheus Blackbox Exporter | [7587](https://grafana.com/grafana/dashboards/7587) | Probe status, HTTP codes, SSL expiry, response times |

> **Note:** The JSON files in `grafana/dashboards/` are placeholders. `setup.sh` downloads the real dashboards automatically.

## Useful management commands

```bash
# Reload Prometheus config and targets without restart
curl -X POST http://localhost:9090/-/reload

# View logs for a specific service
docker compose logs -f prometheus
docker compose logs -f grafana

# Stop the stack (data is preserved in data/)
docker compose down

# Stop and remove all data (destructive)
docker compose down -v
rm -rf data/
```

## Platform notes

### Firewalla

- Firewalla runs custom Linux on ARM64 — all images have ARM64 support.
- Port 3000 is usually free. If Firewalla's UI uses it, set `GRAFANA_PORT=3001` in `.env`.
- If ICMP probes fail, add to the `blackbox` service in `docker-compose.yml`:
  ```yaml
  sysctls:
    net.ipv4.ping_group_range: "0 2147483647"
  ```

### TrueNAS Scale

- TrueNAS Scale uses Kubernetes internally; run this stack via the TrueNAS terminal as root using plain Docker.
- Port 3000 may conflict with the TrueNAS web UI — set `GRAFANA_PORT=3001`.
- The `network_mode: host` on node_exporter exposes TrueNAS host interface metrics directly.

## Architecture

```
targets.yml ──► Prometheus ──► Blackbox Exporter
                    │                (ICMP / HTTP / DNS / TCP)
                    ├──► Node Exporter (host interface stats)
                    └──► Alertmanager ──► Slack / Email
                              │
                           Grafana
```

- `targets.yml` uses Prometheus `file_sd_configs` for hot-reload without restarts
- Node Exporter uses `network_mode: host` to see real host network interfaces
- Blackbox Exporter uses `cap_add: NET_RAW` (minimum privilege) for ICMP
- All secrets live in `.env`, which is gitignored
- Data is persisted in `data/` (also gitignored), backed by named volumes

## File structure

```
NetworkMonitor/
├── setup.sh                            # ← Run this first (downloads dashboards, generates config)
├── docker-compose.yml                  # Service definitions
├── targets.yml                         # ← Edit this to add hosts
├── .env.example                        # Copy to .env and fill in secrets
├── prometheus/
│   ├── prometheus.yml.template         # Scrape config template (generates prometheus.yml)
│   └── rules/
│       ├── blackbox_alerts.yml         # Probe alert rules
│       └── node_alerts.yml.template    # Host network alert rules template (generates node_alerts.yml)
├── blackbox/
│   └── blackbox.yml                    # Probe module definitions
├── alertmanager/
│   └── alertmanager.yml                # Routing and receivers
└── grafana/
    ├── grafana.ini                     # Server settings
    ├── provisioning/
    │   ├── datasources/prometheus.yml  # Auto-wires Prometheus
    │   └── dashboards/dashboards.yml   # Points Grafana at dashboard JSONs
    └── dashboards/                     # Dashboard JSONs downloaded by setup.sh
```
