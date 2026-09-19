#!/usr/bin/env bash
# Read-only checks after any change to the live setup. Run on the VPS:
#   CONTAINER=freqtrade-bot ./vps-preflight.sh
set -u
CONTAINER="${CONTAINER:-freqtrade-bot}"

echo "DOCKER_ENABLED_AT_BOOT"; systemctl is-enabled docker 2>/dev/null || true
echo "CONTAINER_STATE"; docker inspect -f '{{.State.Status}} restart={{.HostConfig.RestartPolicy.Name}}' "$CONTAINER" 2>/dev/null || echo "no container $CONTAINER"
echo "UNATTENDED_UPGRADES"; systemctl is-enabled unattended-upgrades 2>/dev/null || true
echo "UNATTENDED_AUTOMATIC_REBOOT"; sudo grep -RhsE '^[[:space:]]*Unattended-Upgrade::Automatic-Reboot' /etc/apt/apt.conf.d/ 2>/dev/null || echo "not configured (no automatic reboot)"
echo "REBOOT_REQUIRED"; if [ -f /var/run/reboot-required ]; then echo yes; sudo head -20 /var/run/reboot-required.pkgs 2>/dev/null; else echo no; fi
echo "BOOT_TIME"; uptime -s
echo "RECENT_REBOOTS"; last reboot -n 3 2>/dev/null || true
echo "MEMORY_AND_DISK"; free -h; df -h /
echo "LISTENING_ON_PUBLIC"; (ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null) | grep -v '127.0.0.1' | grep -v '::1' || true
