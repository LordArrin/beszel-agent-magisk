#!/system/bin/sh

MODDIR=${0%/*}
BIN="$MODDIR/bin/beszel-agent"

# Persistent config and data directories
CONFIG_DIR="/data/adb/beszel-agent"
ENV_FILE="$CONFIG_DIR/.env"
DATA_DIR="$CONFIG_DIR/data"
LOG="$CONFIG_DIR/beszel-agent.log"
PIDFILE="$CONFIG_DIR/supervise.pid"

MIN_BACKOFF=1
MAX_BACKOFF=300
RESET_AFTER_SECS=60

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG" 2>/dev/null
}

# Single-instance guard
if [ -f "$PIDFILE" ]; then
  old=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$old" ] && [ -d "/proc/$old" ]; then
    exit 0
  fi
  rm -f "$PIDFILE"
fi

# Wait for boot completion
if command -v resetprop >/dev/null 2>&1; then
  resetprop -w sys.boot_completed 0
else
  i=0
  while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 120 ]; do
    sleep 1
    i=$((i + 1))
  done
fi

sleep 5

# Ensure binary is executable
if [ ! -x "$BIN" ]; then
  [ -f "$BIN" ] && chmod 0755 "$BIN"
fi

if [ ! -x "$BIN" ]; then
  log "ERROR: binary missing or not executable: $BIN"
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  log "ERROR: config not found: $ENV_FILE"
  exit 1
fi

# Parse .env
KEY=""; TOKEN=""; HUB_URL=""; FILESYSTEM=""; LISTEN=""
while IFS= read -r line || [ -n "$line" ]; do
  line=$(printf '%s' "$line" | tr -d '\r')
  while [ -n "$line" ]; do
    case "$line" in
      [[:space:]]*) line=${line#?} ;;
      *) break ;;
    esac
  done
  [ -z "$line" ] && continue
  case "$line" in
    \#*) continue ;;
  esac
  case "$line" in
    set\ *) line=${line#set } ;;
  esac
  case "$line" in
    *=*) ;;
    *) continue ;;
  esac
  key=${line%%=*}
  val=${line#*=}
  key=$(printf '%s' "$key" | tr -d '[:space:]')
  case "$val" in
    \"*\") val=${val#\"}; val=${val%\"} ;;
    \'*\') val=${val#\'}; val=${val%\'} ;;
  esac
  case "$key" in
    KEY) KEY="$val" ;;
    TOKEN) TOKEN="$val" ;;
    HUB_URL) HUB_URL="$val" ;;
    FILESYSTEM) FILESYSTEM="$val" ;;
    LISTEN) LISTEN="$val" ;;
  esac
done < "$ENV_FILE"

if [ -z "$KEY" ] || [ -z "$TOKEN" ] || [ -z "$HUB_URL" ]; then
  log "ERROR: KEY, TOKEN, and HUB_URL must be set in $ENV_FILE"
  exit 1
fi

[ -n "$FILESYSTEM" ] || FILESYSTEM="/data"
mkdir -p "$DATA_DIR" 2>/dev/null
chmod 700 "$DATA_DIR" 2>/dev/null

export FILESYSTEM
export DATA_DIR
[ -n "$LISTEN" ] && export LISTEN

# Double-check supervisor singleton
if [ -f "$PIDFILE" ]; then
  old=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$old" ] && [ -d "/proc/$old" ]; then
    exit 0
  fi
fi

(
  echo $$ > "$PIDFILE"
  log "supervisor started pid=$$ DATA_DIR=$DATA_DIR"

  if pidof beszel-agent >/dev/null 2>&1; then
    log "beszel-agent already running; waiting for it to exit"
    while pidof beszel-agent >/dev/null 2>&1; do
      sleep 5
    done
    log "previous beszel-agent exited; taking over"
  fi

  backoff=$MIN_BACKOFF

  while true; do
    started=$(date +%s 2>/dev/null || echo 0)
    log "starting beszel-agent (FILESYSTEM=$FILESYSTEM DATA_DIR=$DATA_DIR HUB_URL=$HUB_URL backoff=${backoff}s)"

    FILESYSTEM="$FILESYSTEM" DATA_DIR="$DATA_DIR" "$BIN" \
      -k "$KEY" \
      -t "$TOKEN" \
      --url "$HUB_URL" \
      >> "$LOG" 2>&1
    rc=$?

    ended=$(date +%s 2>/dev/null || echo 0)
    if [ "$started" -gt 0 ] && [ "$ended" -ge "$started" ]; then
      ran=$((ended - started))
    else
      ran=0
    fi

    if [ "$ran" -ge "$RESET_AFTER_SECS" ]; then
      backoff=$MIN_BACKOFF
    fi

    log "beszel-agent exited rc=$rc after ${ran}s; retry in ${backoff}s"
    sleep "$backoff"

    next=$((backoff * 2))
    if [ "$next" -gt "$MAX_BACKOFF" ]; then
      backoff=$MAX_BACKOFF
    else
      backoff=$next
    fi
  done
) >/dev/null 2>&1 &

exit 0