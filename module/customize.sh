#!/system/bin/sh

# Map Magisk $ARCH to Beszel agent release architecture
case "$ARCH" in
  arm64) BESZEL_ARCH="arm64" ;;
  arm) BESZEL_ARCH="armv7" ;;
  x64) BESZEL_ARCH="amd64" ;;
  x86) BESZEL_ARCH="386" ;;
  *) abort "! Unsupported architecture: $ARCH" ;;
esac

ui_print "- Device architecture: $ARCH (mapped to beszel-agent_linux_${BESZEL_ARCH})"

BINDIR="$MODPATH/bin"
mkdir -p "$BINDIR"
cd "$BINDIR" || abort "! Failed to enter $BINDIR"

# GitHub automatically redirects this URL to the latest release asset
BESZEL_URL="https://github.com/henrygd/beszel/releases/latest/download/beszel-agent_linux_${BESZEL_ARCH}.tar.gz"
ui_print "- Downloading latest beszel-agent..."

DOWNLOADED=0
if command -v curl >/dev/null 2>&1; then
  # -s: silent, -L: follow redirects, -o: output file
  if curl -sLo beszel-agent.tar.gz "$BESZEL_URL"; then
    DOWNLOADED=1
  fi
fi

if [ "$DOWNLOADED" = 0 ] && command -v wget >/dev/null 2>&1; then
  # -q: quiet, -O: output file (wget follows redirects by default)
  if wget -qO beszel-agent.tar.gz "$BESZEL_URL"; then
    DOWNLOADED=1
  fi
fi

if [ "$DOWNLOADED" = 0 ] || [ ! -s beszel-agent.tar.gz ]; then
  rm -f beszel-agent.tar.gz
  abort "! Failed to download beszel-agent. Check your internet connection."
fi

ui_print "- Extracting..."
if tar -xzf beszel-agent.tar.gz; then
  # Remove archive and unnecessary docs, keep only the binary
  rm -f beszel-agent.tar.gz LICENSE readme.md
else
  rm -f beszel-agent.tar.gz
  abort "! Failed to extract beszel-agent.tar.gz"
fi

if [ ! -f beszel-agent ]; then
  abort "! beszel-agent binary not found after extraction."
fi

ui_print "- beszel-agent installed successfully."
set_perm "$BINDIR/beszel-agent" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755

# Persistent agent state (fingerprint). Required on Android — default
# /var/lib/beszel-agent is not usable / not writable.
mkdir -p "$MODPATH/data"
set_perm "$MODPATH/data" 0 0 0700

# Never overwrite an existing .env to preserve credentials across updates.
if [ ! -f "$MODPATH/.env" ]; then
  if [ -f "$MODPATH/.env.example" ]; then
    ui_print "- Creating .env from .env.example (edit it before reboot)"
    cp -f "$MODPATH/.env.example" "$MODPATH/.env"
    set_perm "$MODPATH/.env" 0 0 0600
  else
    ui_print "! No .env.example found; create $MODPATH/.env manually"
  fi
else
  ui_print "- Keeping existing .env"
  set_perm "$MODPATH/.env" 0 0 0600
fi

# Ensure DATA_DIR is set for upgrades that predate this field.
if [ -f "$MODPATH/.env" ] && ! grep -q '^DATA_DIR=' "$MODPATH/.env" 2>/dev/null; then
  ui_print "- Appending DATA_DIR=$MODPATH/data to .env"
  printf '\nDATA_DIR=%s\n' "$MODPATH/data" >> "$MODPATH/.env"
fi

ui_print "- Done. Edit /data/adb/modules/beszel-agent/.env then reboot."
