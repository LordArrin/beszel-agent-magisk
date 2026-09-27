ui_print "- Detecting architecture..."

BESZEL_ARCH=""
FALLBACK_ARCH=""
UNAME_M=$(uname -m 2>/dev/null)

ui_print "- Magisk ARCH: $ARCH"
ui_print "- uname -m: $UNAME_M"

case "$ARCH" in
    arm64)
        BESZEL_ARCH="arm64"
        ;;
    arm)
        case "$UNAME_M" in
            armv7l|armv8l|armv7*)
                BESZEL_ARCH="armv7"
                ;;
            armv6l|armv6*)
                BESZEL_ARCH="arm"
                FALLBACK_ARCH="armv5"
                ;;
            armv5tel|armv5tejl|armv5*)
                BESZEL_ARCH="armv5"
                FALLBACK_ARCH="arm"
                ;;
            *)
                if [ -f /proc/cpuinfo ]; then
                    CPUINFO=$(tr '[:upper:]' '[:lower:]' < /proc/cpuinfo)
                    if echo "$CPUINFO" | grep -qE 'vfpv3|neon|thumb-2|armv7'; then
                        BESZEL_ARCH="armv7"
                    elif echo "$CPUINFO" | grep -qE 'vfpv2|arm11|armv6'; then
                        BESZEL_ARCH="arm"
                        FALLBACK_ARCH="armv5"
                    else
                        BESZEL_ARCH="armv5"
                        FALLBACK_ARCH="arm"
                    fi
                else
                    BESZEL_ARCH="armv7"
                fi
                ;;
        esac
        ;;
    x64)
        BESZEL_ARCH="amd64"
        ;;
    x86)
        ui_print "- WARNING: i386/i686 has no official Beszel release"
        BESZEL_ARCH="amd64"
        ;;
    *)
        case "$UNAME_M" in
            aarch64|arm64|armv8*)
                BESZEL_ARCH="arm64"
                ;;
            armv7l|armv8l|armv7*)
                BESZEL_ARCH="armv7"
                ;;
            armv6l|armv6*)
                BESZEL_ARCH="arm"
                FALLBACK_ARCH="armv5"
                ;;
            armv5*)
                BESZEL_ARCH="armv5"
                FALLBACK_ARCH="arm"
                ;;
            x86_64|amd64)
                BESZEL_ARCH="amd64"
                ;;
            mips|mipsel)
                if [ "$UNAME_M" = "mipsel" ]; then
                    BESZEL_ARCH="mipsle"
                else
                    BESZEL_ARCH="mips"
                fi
                ;;
            mips64*)
                BESZEL_ARCH="mips64"
                ;;
            ppc64le)
                BESZEL_ARCH="ppc64le"
                ;;
            riscv64)
                BESZEL_ARCH="riscv64"
                ;;
            *)
                abort "! Unsupported architecture: ARCH=$ARCH, uname=$UNAME_M"
                ;;
        esac
        ;;
esac

ui_print "- Selected: beszel-agent_linux_${BESZEL_ARCH}.tar.gz"
if [ -n "$FALLBACK_ARCH" ]; then
    ui_print "- Fallback: beszel-agent_linux_${FALLBACK_ARCH}.tar.gz"
fi

BINDIR="$MODPATH/bin"
mkdir -p "$BINDIR"
cd "$BINDIR" || abort "! Failed to enter $BINDIR"

download_binary() {
    arch="$1"
    url="https://github.com/henrygd/beszel/releases/latest/download/beszel-agent_linux_${arch}.tar.gz"
    ui_print "- Trying: $url"
    if command -v curl >/dev/null 2>&1; then
        http_code=$(curl -sLo /dev/null -w "%{http_code}" "$url" 2>/dev/null)
        if [ "$http_code" = "200" ]; then
            curl -sLo beszel-agent.tar.gz "$url"
            if [ -s beszel-agent.tar.gz ]; then
                return 0
            fi
        fi
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -qO beszel-agent.tar.gz "$url" 2>/dev/null
        if [ -s beszel-agent.tar.gz ]; then
            return 0
        fi
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
        ui_print "- Primary failed, using fallback: $BESZEL_ARCH"
    fi
fi

if [ "$DOWNLOADED" = "0" ] || [ ! -s beszel-agent.tar.gz ]; then
    rm -f beszel-agent.tar.gz
    abort "! Failed to download beszel-agent. Check your internet connection."
fi

ui_print "- Extracting..."
if tar -xzf beszel-agent.tar.gz; then
    rm -f beszel-agent.tar.gz LICENSE readme.md
else
    rm -f beszel-agent.tar.gz
    abort "! Failed to extract beszel-agent.tar.gz"
fi

if [ ! -f beszel-agent ]; then
    abort "! beszel-agent binary not found after extraction."
fi

ui_print "- Stopping existing beszel-agent processes..."

if pidof beszel-agent >/dev/null 2>&1; then
    ui_print "- Found running process, sending SIGTERM..."
    kill -TERM $(pidof beszel-agent) 2>/dev/null
    sleep 2
    if pidof beszel-agent >/dev/null 2>&1; then
        ui_print "- Process still running, sending SIGKILL..."
        kill -KILL $(pidof beszel-agent) 2>/dev/null
        sleep 1
    fi
fi

OLD_PIDFILE="/data/adb/beszel-agent/supervise.pid"
if [ -f "$OLD_PIDFILE" ]; then
    old_supervisor=$(cat "$OLD_PIDFILE" 2>/dev/null)
    if [ -n "$old_supervisor" ] && [ -d "/proc/$old_supervisor" ]; then
        ui_print "- Stopping supervisor (pid=$old_supervisor)..."
        kill -TERM "$old_supervisor" 2>/dev/null
        sleep 1
        kill -KILL "$old_supervisor" 2>/dev/null
    fi
    rm -f "$OLD_PIDFILE"
fi

ui_print "- beszel-agent ($BESZEL_ARCH) installed successfully."

set_perm "$BINDIR/beszel-agent" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
