#!/sbin/sh

if [ -z "$KSU" ] && [ -n "$MAGISK_VER_CODE" ] && [ "$MAGISK_VER_CODE" -lt 28000 ]; then
    abort "! This module requires Magisk v28.0+"
fi

ui_print "- Detecting architecture..."
BESZEL_ARCH=""
FALLBACK_ARCH=""
UNAME_M=$(uname -m 2>/dev/null)

case "$ARCH" in
    arm64) BESZEL_ARCH="arm64" ;;
    arm)
        case "$UNAME_M" in
            armv7l|armv8l|armv7*) BESZEL_ARCH="armv7" ;;
            armv6l|armv6*) BESZEL_ARCH="arm"; FALLBACK_ARCH="armv5" ;;
            armv5*) BESZEL_ARCH="armv5"; FALLBACK_ARCH="arm" ;;
            *) BESZEL_ARCH="armv7" ;;
        esac
        ;;
    x64) BESZEL_ARCH="amd64" ;;
    x86) BESZEL_ARCH="amd64" ;;
    riscv64) BESZEL_ARCH="riscv64" ;;
    *) abort "! Unsupported architecture: ARCH=$ARCH, uname=$UNAME_M" ;;
esac

BINDIR="$MODPATH/bin"
CONFIG_DIR="/data/adb/beszel-agent"
VERSION_FILE="$CONFIG_DIR/.version"
ARCH_FILE="$CONFIG_DIR/.arch"

mkdir -p "$BINDIR" "$CONFIG_DIR"

get_latest_version() {
    if command -v curl >/dev/null 2>&1; then
        curl -s https://api.github.com/repos/henrygd/beszel/releases/latest 2>/dev/null | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' | tr -d '\r'
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- https://api.github.com/repos/henrygd/beszel/releases/latest 2>/dev/null | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' | tr -d '\r'
    fi
}

CURRENT_VERSION=$(cat "$VERSION_FILE" 2>/dev/null | tr -d '\r')
CURRENT_ARCH=$(cat "$ARCH_FILE" 2>/dev/null | tr -d '\r')
LATEST_VERSION=$(get_latest_version)

ui_print "- Current version: ${CURRENT_VERSION:-not installed}"
ui_print "- Latest version: ${LATEST_VERSION:-unknown}"

NEED_DOWNLOAD=0
NEED_RESTART=0

if [ -z "$LATEST_VERSION" ]; then
    ui_print "- WARNING: Failed to check latest version, assuming current is latest"
    if [ ! -f "$BINDIR/beszel-agent" ] && [ -z "$CURRENT_VERSION" ]; then
        abort "! No binary found and cannot determine version"
    fi
elif [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
    NEED_DOWNLOAD=1
    ui_print "- Update available: ${CURRENT_VERSION:-none} -> $LATEST_VERSION"
elif [ ! -f "$CONFIG_DIR/../modules/beszel-agent/bin/beszel-agent" ] && [ ! -f "$BINDIR/beszel-agent" ]; then
    NEED_DOWNLOAD=1
    ui_print "- Binary not found, downloading..."
else
    ui_print "- Binary is up to date"
    if [ -n "$CURRENT_VERSION" ] && [ -f "$CONFIG_DIR/../modules/beszel-agent/bin/beszel-agent" ]; then
        cp "$CONFIG_DIR/../modules/beszel-agent/bin/beszel-agent" "$BINDIR/beszel-agent" 2>/dev/null
        ui_print "- Copied existing binary to new module path"
    fi
fi

if [ "$NEED_DOWNLOAD" = "1" ]; then
    cd "$BINDIR" || abort "! Failed to enter $BINDIR"
    
    download_binary() {
        local arch="$1"
        local url="https://github.com/henrygd/beszel/releases/latest/download/beszel-agent_linux_${arch}.tar.gz"
        local http_code
        
        if command -v curl >/dev/null 2>&1; then
            http_code=$(curl -sLo /dev/null -w "%{http_code}" --connect-timeout 10 "$url" 2>/dev/null)
            if [ "$http_code" = "200" ]; then
                curl -sLo beszel-agent.tar.gz "$url"
                [ -s beszel-agent.tar.gz ] && return 0
            fi
        fi
        
        if command -v wget >/dev/null 2>&1; then
            wget -qO beszel-agent.tar.gz --timeout=10 "$url" 2>/dev/null
            [ -s beszel-agent.tar.gz ] && return 0
        fi
        
        rm -f beszel-agent.tar.gz
        return 1
    }
    
    ui_print "- Downloading beszel-agent..."
    DOWNLOADED=0
    if download_binary "$BESZEL_ARCH"; then
        DOWNLOADED=1
    elif [ -n "$FALLBACK_ARCH" ]; then
        if download_binary "$FALLBACK_ARCH"; then
            DOWNLOADED=1
            BESZEL_ARCH="$FALLBACK_ARCH"
        fi
    fi
    
    if [ "$DOWNLOADED" = "0" ] || [ ! -s beszel-agent.tar.gz ]; then
        rm -f beszel-agent.tar.gz
        abort "! Failed to download beszel-agent"
    fi
    
    if tar -xzf beszel-agent.tar.gz; then
        rm -f beszel-agent.tar.gz LICENSE readme.md README.md
    else
        rm -f beszel-agent.tar.gz
        abort "! Failed to extract beszel-agent.tar.gz"
    fi
    
    [ ! -f beszel-agent ] && abort "! beszel-agent binary not found"
    
    NEED_RESTART=1
    ui_print "- Binary downloaded and extracted"
fi

if [ "$NEED_RESTART" = "1" ]; then
    ui_print "- Stopping existing agent..."
    killall -TERM beszel-agent 2>/dev/null
    sleep 1
    killall -KILL beszel-agent 2>/dev/null
fi

echo "$BESZEL_ARCH" > "$ARCH_FILE"
echo "$LATEST_VERSION" > "$VERSION_FILE"
ui_print "- Saved version: $LATEST_VERSION ($BESZEL_ARCH)"

if [ ! -f "$CONFIG_DIR/.env" ]; then
    if [ -f "/sdcard/beszel.txt" ]; then
        cp "/sdcard/beszel.txt" "$CONFIG_DIR/.env"
        ui_print "- Config loaded from /sdcard/beszel.txt"
    elif [ -f "$MODPATH/.env.example" ]; then
        cp "$MODPATH/.env.example" "$CONFIG_DIR/.env"
        ui_print "- Default config created"
    fi
fi

set_perm "$BINDIR/beszel-agent" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755

chmod 700 "$CONFIG_DIR"
chown 0:0 "$CONFIG_DIR"

if [ "$NEED_RESTART" = "1" ]; then
    ui_print "- Restarting agent..."
    sh "$MODPATH/service.sh" &
fi

ui_print "- beszel-agent ($BESZEL_ARCH) installed successfully"