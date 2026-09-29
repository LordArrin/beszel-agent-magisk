#!/system/bin/sh

MODDIR=${0%/*}
CONFIG_DIR="/data/adb/beszel-agent"

chmod 700 "$CONFIG_DIR" 2>/dev/null
chown 0:0 "$CONFIG_DIR" 2>/dev/null

echo "[$(date '+%Y-%m-%d %H:%M:%S')] post-fs-data: Module loaded" >> "$CONFIG_DIR/boot.log"