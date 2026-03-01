#!/usr/bin/env bash
# NetworkMonitor — setup.sh
# Run this once before 'docker compose up -d', and again whenever you change .env.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Load .env ──────────────────────────────────────────────────────────────────
if [ ! -f .env ]; then
  echo "ERROR: .env not found."
  echo "       Run: cp .env.example .env  then edit it before re-running setup.sh"
  exit 1
fi
set -a; source .env; set +a

# ── Data directories ───────────────────────────────────────────────────────────
echo "==> Creating data directories..."
mkdir -p data/{prometheus,grafana,alertmanager}
chown -R 65534:65534 data/prometheus     # Prometheus runs as nobody (UID 65534)

# ── Generate config files from templates ──────────────────────────────────────
echo "==> Generating config files..."
# Substitute only the specific variables to avoid clobbering PromQL $labels/$value
envsubst '${PROMETHEUS_SITE}' \
  < prometheus/prometheus.yml.template \
  > prometheus/prometheus.yml

envsubst '${BANDWIDTH_THRESHOLD_MBPS}' \
  < prometheus/rules/node_alerts.yml.template \
  > prometheus/rules/node_alerts.yml

# ── Download Grafana dashboards ────────────────────────────────────────────────
echo "==> Checking Grafana dashboards..."

download_if_placeholder() {
  local file="$1" url="$2" name="$3"
  if grep -q '"_PLACEHOLDER"' "$file" 2>/dev/null; then
    echo "    Downloading $name..."
    curl -fsSL "$url" -o "$file"
    echo "    Done."
  else
    echo "    $name already downloaded, skipping."
  fi
}

download_if_placeholder \
  "grafana/dashboards/node-exporter-full.json" \
  "https://grafana.com/api/dashboards/1860/revisions/latest/download" \
  "Node Exporter Full (1860)"

download_if_placeholder \
  "grafana/dashboards/blackbox-exporter.json" \
  "https://grafana.com/api/dashboards/7587/revisions/latest/download" \
  "Prometheus Blackbox Exporter (7587)"

echo ""
echo "All done. Start the stack with:"
echo "  docker compose up -d"
