#!/system/bin/sh

MODDIR=${0%/*}
BIN="$MODDIR/bin/beszel-agent"
PROP_FILE="$MODDIR/module.prop"

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

# Update module description in KernelSU/Magisk UI
update_status() {
  local status="$1"
  if [ -f "$PROP_FILE" ]; then
    sed -i "s|^description=.*|description=$status|" "$PROP_FILE"
  fi
}

if [ -f "$PIDFILE" ]; then
  old=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$old" ] && [ -d "/proc/$old" ]; then
    exit 0
  fi
  rm -f "$PIDFILE"
fi

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

if [ ! -x "$BIN" ]; then
  [ -f "$BIN" ] && chmod 0755 "$BIN"
fi

if [ ! -x "$BIN" ]; then
  log "ERROR: binary missing or not executable: $BIN"
  update_status "🔴 Error: Binary missing"
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  log "ERROR: config not found: $ENV_FILE"
  update_status "🔴 Error: Config not found"
  exit 1
fi

KEY=""; TOKEN=""; HUB_URL=""; FILESYSTEM=""; LISTEN=""; SYSTEM_NAME=""
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
    SYSTEM_NAME) SYSTEM_NAME="$val" ;;
  esac
done < "$ENV_FILE"

if [ -z "$KEY" ] || [ -z "$TOKEN" ] || [ -z "$HUB_URL" ]; then
  log "ERROR: KEY, TOKEN, and HUB_URL must be set in $ENV_FILE"
  update_status "🔴 Error: Invalid config"
  exit 1
fi

[ -n "$FILESYSTEM" ] || FILESYSTEM="/data"
mkdir -p "$DATA_DIR" 2>/dev/null
chmod 700 "$DATA_DIR" 2>/dev/null

if [ -z "$SYSTEM_NAME" ]; then
  DEVICE_MODEL=$(getprop ro.product.model 2>/dev/null)
  DEVICE_MANUFACTURER=$(getprop ro.product.manufacturer 2>/dev/null)
  
  if [ -n "$DEVICE_MODEL" ] && [ -n "$DEVICE_MANUFACTURER" ]; then
    SYSTEM_NAME="$DEVICE_MANUFACTURER $DEVICE_MODEL"
  elif [ -n "$DEVICE_MODEL" ]; then
    SYSTEM_NAME="$DEVICE_MODEL"
  else
    SYSTEM_NAME=$(hostname 2>/dev/null)
  fi
fi

export FILESYSTEM
export DATA_DIR
export SYSTEM_NAME
[ -n "$LISTEN" ] && export LISTEN

if [ -f "$PIDFILE" ]; then
  old=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$old" ] && [ -d "/proc/$old" ]; then
    exit 0
  fi
fi

(
  echo $$ > "$PIDFILE"
  log "supervisor started pid=$$ DATA_DIR=$DATA_DIR SYSTEM_NAME=$SYSTEM_NAME"
  update_status "🟢 Running beszel-agent"

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
    log "starting beszel-agent (FILESYSTEM=$FILESYSTEM DATA_DIR=$DATA_DIR HUB_URL=$HUB_URL SYSTEM_NAME=$SYSTEM_NAME backoff=${backoff}s)"

    FILESYSTEM="$FILESYSTEM" DATA_DIR="$DATA_DIR" SYSTEM_NAME="$SYSTEM_NAME" "$BIN" \
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

    update_status "🟠 Restarting in ${backoff}s"
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
