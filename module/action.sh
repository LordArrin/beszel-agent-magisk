#!/system/bin/sh

MODDIR=${0%/*}
BIN="$MODDIR/bin/beszel-agent"
CONFIG_DIR="/data/adb/beszel-agent"
ENV_FILE="$CONFIG_DIR/.env"
LOG="$CONFIG_DIR/beszel-agent.log"
PIDFILE="$CONFIG_DIR/beszel-agent.pid"
TMP_DIR="$CONFIG_DIR/tmp"

echo "=== Beszel Agent Manager ==="
echo ""

check_update() {
    local current_arch
    current_arch=$(uname -m)
    
    case "$current_arch" in
        aarch64|arm64) BESZEL_ARCH="arm64" ;;
        armv7l|armv8l) BESZEL_ARCH="armv7" ;;
        armv6l) BESZEL_ARCH="arm" ;;
        x86_64|amd64) BESZEL_ARCH="amd64" ;;
        *) BESZEL_ARCH="amd64" ;;
    esac
    
    local url="https://github.com/henrygd/beszel/releases/latest/download/beszel-agent_linux_${BESZEL_ARCH}.tar.gz"
    
    echo "- Checking for updates..."
    
    mkdir -p "$TMP_DIR"
    cd "$TMP_DIR" || return 1
    
    if command -v curl >/dev/null 2>&1; then
        curl -sLo beszel-agent-update.tar.gz "$url" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -qO beszel-agent-update.tar.gz "$url" 2>/dev/null
    else
        echo "- ERROR: No download tool available"
        return 1
    fi
    
    if [ ! -s beszel-agent-update.tar.gz ]; then
        echo "- ERROR: Download failed"
        rm -rf "$TMP_DIR"
        return 1
    fi
    
    echo "- Update downloaded, extracting..."
    
    if tar -xzf beszel-agent-update.tar.gz; then
        if [ -f beszel-agent ]; then
            killall -TERM beszel-agent 2>/dev/null
            sleep 1
            killall -KILL beszel-agent 2>/dev/null
            
            mv beszel-agent "$BIN"
            chmod 755 "$BIN"
            chown 0:0 "$BIN"
            chcon u:object_r:system_file:s0 "$BIN" 2>/dev/null
            
            echo "- Binary updated successfully"
            rm -rf "$TMP_DIR"
            return 0
        fi
    fi
    
    echo "- ERROR: Extraction failed"
    rm -rf "$TMP_DIR"
    return 1
}

if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$PID" ] && [ -d "/proc/$PID" ]; then
        echo "Status: Running (PID=$PID)"
    else
        echo "Status: Stopped"
        rm -f "$PIDFILE"
    fi
else
    echo "Status: Stopped"
fi

echo ""
echo "Checking for binary updates..."
check_update

echo ""
echo "Starting agent..."

if [ ! -f "$BIN" ]; then
    echo "ERROR: Binary not found"
    sleep 5
    exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: Config not found"
    sleep 5
    exit 1
fi

KEY=$(grep -E '^KEY=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '\r' | tr -d '"' | tr -d "'" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
TOKEN=$(grep -E '^TOKEN=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '\r' | tr -d '"' | tr -d "'" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
HUB_URL=$(grep -E '^HUB_URL=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '\r' | tr -d '"' | tr -d "'" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [ -z "$KEY" ] || [ -z "$TOKEN" ] || [ -z "$HUB_URL" ]; then
    echo "ERROR: Missing required config values"
    sleep 5
    exit 1
fi

chmod 700 "$CONFIG_DIR"
chown 0:0 "$CONFIG_DIR"

cd "$CONFIG_DIR" || exit 1
export HOME="$CONFIG_DIR"

"$BIN" --key="$KEY" --token="$TOKEN" --url="$HUB_URL" >> "$LOG" 2>&1 &
NEW_PID=$!
echo "$NEW_PID" > "$PIDFILE"

sleep 2
if [ -d "/proc/$NEW_PID" ]; then
    echo "Agent started (PID=$NEW_PID)"
    echo ""
    echo "Last 10 log lines:"
    tail -n 10 "$LOG" | while read -r line; do
        echo "  $line"
    done
else
    echo "ERROR: Failed to start"
    tail -n 10 "$LOG" | while read -r line; do
        echo "  $line"
    done
    rm -f "$PIDFILE"
fi

echo ""
echo "Done. Window will close in 10 seconds..."
sleep 10