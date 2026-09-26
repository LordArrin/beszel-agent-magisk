#!/system/bin/sh

MODDIR=${0%/*}
CONFIG_DIR="/data/adb/beszel-agent"
ENV_FILE="$CONFIG_DIR/.env"
LOG="$CONFIG_DIR/beszel-agent.log"
PIDFILE="$CONFIG_DIR/supervise.pid"
PROP_FILE="$MODDIR/module.prop"

# Helper function to update module description
update_status() {
  local status="$1"
  if [ -f "$PROP_FILE" ]; then
    sed -i "s|^description=.*|description=$status|" "$PROP_FILE"
  fi
}

# Stop existing supervisor if running
if [ -f "$PIDFILE" ]; then
  old_pid=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$old_pid" ] && [ -d "/proc/$old_pid" ]; then
    kill "$old_pid" 2>/dev/null
    sleep 1
  fi
  rm -f "$PIDFILE"
fi

# Kill any existing beszel-agent processes
pkill -f "beszel-agent" 2>/dev/null
sleep 1

# Check config exists
if [ ! -f "$ENV_FILE" ]; then
  update_status "🔴 Error: Config not found"
  echo "ERROR: Config not found at $ENV_FILE"
  exit 1
fi

# Check binary exists
BIN="$MODDIR/bin/beszel-agent"
if [ ! -x "$BIN" ]; then
  update_status "🔴 Error: Binary missing"
  echo "ERROR: Binary not found at $BIN"
  exit 1
fi

# Update status to starting
update_status "🟡 Starting beszel-agent..."

# Launch service.sh in background
nohup "$MODDIR/service.sh" >/dev/null 2>&1 &

echo "beszel-agent started successfully!"
echo "Check logs: cat $LOG"