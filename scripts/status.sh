#!/usr/bin/env bash
# Show status of all Docker Compose stacks, disk usage, and system resources.
set -euo pipefail

DOCKER_DIR="/home/laszlokr/guix-config/docker"
STACKS=(odoo nextcloud ai automation search)

header() { printf "\n\033[1;34m=== %s ===\033[0m\n" "$1"; }

# ---------------------------------------------------------------------------
# Docker Compose stacks
# ---------------------------------------------------------------------------
header "Docker Compose stacks"
for stack in "${STACKS[@]}"; do
  printf "\n\033[1m%s\033[0m\n" "$stack"
  docker compose \
    --project-directory "${DOCKER_DIR}/${stack}" \
    ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" \
    2>/dev/null || echo "  (not running or compose file missing)"
done

# ---------------------------------------------------------------------------
# Shepherd service status
# ---------------------------------------------------------------------------
header "Shepherd service status"
for stack in "${STACKS[@]}"; do
  printf "  %-20s " "docker-${stack}:"
  sudo herd status "docker-${stack}" 2>/dev/null \
    | grep -E 'Status:|Running:' | head -1 \
    || echo "unknown"
done

# ---------------------------------------------------------------------------
# Disk usage
# ---------------------------------------------------------------------------
header "Disk usage"
df -h /data /storage / 2>/dev/null || df -h /

echo ""
for dir in /data/docker /storage/backups; do
  if [ -d "$dir" ]; then
    printf "  %-30s %s\n" "$dir" "$(du -sh "$dir" 2>/dev/null | cut -f1)"
  fi
done

# ---------------------------------------------------------------------------
# Memory
# ---------------------------------------------------------------------------
header "Memory"
free -h

# ---------------------------------------------------------------------------
# CPU load
# ---------------------------------------------------------------------------
header "CPU load"
uptime
echo ""
grep -c ^processor /proc/cpuinfo | xargs -I{} echo "  {} logical CPUs"
