#!/system/bin/sh

MODDIR=${0%/*}
BIN="$MODDIR/bin/beszel-agent"
CONFIG_DIR="/data/adb/beszel-agent"
ENV_FILE="$CONFIG_DIR/.env"
LOG="$CONFIG_DIR/beszel-agent.log"
PIDFILE="$CONFIG_DIR/beszel-agent.pid"
TMP_DIR="$CONFIG_DIR/tmp"
VERSION_FILE="$CONFIG_DIR/.version"
ARCH_FILE="$CONFIG_DIR/.arch"

echo "=== Beszel Agent Manager ==="
echo ""

get_latest_version() {
    if command -v curl >/dev/null 2>&1; then
        curl -s https://api.github.com/repos/henrygd/beszel/releases/latest 2>/dev/null | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' | tr -d '\r'
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- https://api.github.com/repos/henrygd/beszel/releases/latest 2>/dev/null | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' | tr -d '\r'
    fi
}

check_update() {
    [ ! -f "$ARCH_FILE" ] && echo "- ERROR: Architecture file not found" && return 1
    
    local CURRENT_ARCH=$(cat "$ARCH_FILE" | tr -d '\r')
    local CURRENT_VERSION=$(cat "$VERSION_FILE" 2>/dev/null | tr -d '\r')
    
    echo "- Current version: ${CURRENT_VERSION:-unknown}"
    echo "- Checking for updates..."
    
    local LATEST_VERSION=$(get_latest_version)
    if [ -z "$LATEST_VERSION" ]; then
        echo "- ERROR: Failed to check latest version"
        return 1
    fi
    
    echo "- Latest version: $LATEST_VERSION"
    
    if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
        echo "- Already up to date"
        return 0
    fi
    
    echo "- Update available: $CURRENT_VERSION -> $LATEST_VERSION"
    
    local url="https://github.com/henrygd/beszel/releases/latest/download/beszel-agent_linux_${CURRENT_ARCH}.tar.gz"
    
    echo "- Downloading update..."
    
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
            
            echo "$LATEST_VERSION" > "$VERSION_FILE"
            
            echo "- Binary updated successfully to $LATEST_VERSION"
            rm -rf "$TMP_DIR"
            return 2
        fi
    fi
    
    echo "- ERROR: Extraction failed"
    rm -rf "$TMP_DIR"
    return 1
}

is_running() {
    if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE" 2>/dev/null)
        if [ -n "$PID" ] && [ -d "/proc/$PID" ]; then
            return 0
        fi
        rm -f "$PIDFILE"
    fi
    return 1
}

start_agent() {
    if [ ! -f "$BIN" ]; then
        echo "ERROR: Binary not found"
        return 1
    fi
    
    if [ ! -f "$ENV_FILE" ]; then
        echo "ERROR: Config not found"
        return 1
    fi
    
    KEY=$(grep -E '^KEY=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '\r' | tr -d '"' | tr -d "'" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    TOKEN=$(grep -E '^TOKEN=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '\r' | tr -d '"' | tr -d "'" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    HUB_URL=$(grep -E '^HUB_URL=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '\r' | tr -d '"' | tr -d "'" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    if [ -z "$KEY" ] || [ -z "$TOKEN" ] || [ -z "$HUB_URL" ]; then
        echo "ERROR: Missing required config values"
        return 1
    fi
    
    chmod 700 "$CONFIG_DIR"
    chown 0:0 "$CONFIG_DIR"
    
    cd "$CONFIG_DIR" || return 1
    export HOME="$CONFIG_DIR"
    
    "$BIN" --key="$KEY" --token="$TOKEN" --url="$HUB_URL" >> "$LOG" 2>&1 &
    NEW_PID=$!
    echo "$NEW_PID" > "$PIDFILE"
    
    sleep 2
    if [ -d "/proc/$NEW_PID" ]; then
        echo "Agent started (PID=$NEW_PID)"
        return 0
    else
        echo "ERROR: Failed to start"
        rm -f "$PIDFILE"
        return 1
    fi
}

# Main logic
UPDATED=0
check_update
UPDATED=$?

if [ $UPDATED -eq 2 ]; then
    echo ""
    echo "Binary was updated, restarting agent..."
    start_agent
elif [ $UPDATED -eq 0 ]; then
    if is_running; then
        PID=$(cat "$PIDFILE" 2>/dev/null)
        echo ""
        echo "Status: Running (PID=$PID)"
        echo "No restart needed."
    else
        echo ""
        echo "Status: Stopped"
        echo "Starting agent..."
        start_agent
    fi
else
    echo ""
    echo "Update check failed, trying to start agent anyway..."
    if ! is_running; then
        start_agent
    fi
fi

echo ""
echo "Last 5 log lines:"
tail -n 5 "$LOG" 2>/dev/null | while read -r line; do
    echo "  $line"
done

echo ""
echo "Done. Window will close in 10 seconds..."
sleep 10