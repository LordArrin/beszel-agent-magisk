#!/system/bin/sh

MODDIR=${0%/*}
BIN="$MODDIR/bin/beszel-agent"
CONFIG_DIR="/data/adb/beszel-agent"
ENV_FILE="$CONFIG_DIR/.env"
LOG="$CONFIG_DIR/beszel-agent.log"
PIDFILE="$CONFIG_DIR/beszel-agent.pid"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$CONFIG_DIR/boot.log"
}

log "Waiting for boot completion..."
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done
log "Boot completed"

[ ! -f "$BIN" ] && log "ERROR: Binary not found" && exit 1
[ ! -f "$ENV_FILE" ] && log "ERROR: Config not found" && exit 1

KEY=$(grep -E '^KEY=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '\r' | tr -d '"' | tr -d "'" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
TOKEN=$(grep -E '^TOKEN=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '\r' | tr -d '"' | tr -d "'" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
HUB_URL=$(grep -E '^HUB_URL=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '\r' | tr -d '"' | tr -d "'" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

[ -z "$KEY" ] && log "ERROR: KEY not set" && exit 1
[ -z "$TOKEN" ] && log "ERROR: TOKEN not set" && exit 1
[ -z "$HUB_URL" ] && log "ERROR: HUB_URL not set" && exit 1

if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && [ -d "/proc/$OLD_PID" ]; then
        kill -TERM "$OLD_PID" 2>/dev/null
        sleep 2
        kill -KILL "$OLD_PID" 2>/dev/null
    fi
    rm -f "$PIDFILE"
fi

killall -TERM beszel-agent 2>/dev/null
sleep 1
killall -KILL beszel-agent 2>/dev/null

chcon u:object_r:system_file:s0 "$BIN" 2>/dev/null
chmod 755 "$BIN"
chmod 700 "$CONFIG_DIR"
chown 0:0 "$CONFIG_DIR"

cd "$CONFIG_DIR" || exit 1
export HOME="$CONFIG_DIR"

"$BIN" --key="$KEY" --token="$TOKEN" --url="$HUB_URL" >> "$LOG" 2>&1 &
NEW_PID=$!
echo "$NEW_PID" > "$PIDFILE"

sleep 2
if [ -d "/proc/$NEW_PID" ]; then
    log "Started successfully (PID=$NEW_PID)"
else
    log "ERROR: Failed to start"
    rm -f "$PIDFILE"
    exit 1
fi