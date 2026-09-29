#!/system/bin/sh

MODDIR=${0%/*}
CONFIG_DIR="/data/adb/beszel-agent"

# Log boot completion
echo "[$(date '+%Y-%m-%d %H:%M:%S')] boot-completed: Device fully booted" >> "$CONFIG_DIR/boot.log"

# Ensure agent is still running
if ! pidof beszel-agent >/dev/null 2>&1; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] boot-completed: Agent not running, restarting via action" >> "$CONFIG_DIR/boot.log"
    # Agent will be started by service.sh, but we can trigger restart if needed
fi