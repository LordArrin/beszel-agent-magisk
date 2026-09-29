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
mkdir -p "$BINDIR" "$CONFIG_DIR"

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

killall -TERM beszel-agent 2>/dev/null
sleep 1
killall -KILL beszel-agent 2>/dev/null

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

ui_print "- beszel-agent ($BESZEL_ARCH) installed successfully"