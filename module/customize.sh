#!/system/bin/sh

CONFIG_DIR="/data/adb/beszel-agent"
ENV_FILE="$CONFIG_DIR/.env"
DATA_DIR="$CONFIG_DIR/data"

mkdir -p "$CONFIG_DIR"
mkdir -p "$DATA_DIR"
chmod 0700 "$CONFIG_DIR"
chmod 0700 "$DATA_DIR"

# First installation: check for user-provided config in internal storage
if [ ! -f "$ENV_FILE" ]; then
  CONFIG_LOADED=false
  
  # Check common paths for internal storage (works on Android 9-17)
  for storage_path in "/storage/emulated/0" "/sdcard" "/mnt/sdcard"; do
    if [ -f "$storage_path/beszel.txt" ]; then
      ui_print "- Found config: $storage_path/beszel.txt"
      cp -f "$storage_path/beszel.txt" "$ENV_FILE"
      chmod 0600 "$ENV_FILE"
      ui_print "- Config loaded from $storage_path/beszel.txt"
      CONFIG_LOADED=true
      break
    fi
  done
  
  # Fallback to .env.example if no user config found
  if [ "$CONFIG_LOADED" = false ]; then
    if [ -f "$MODPATH/.env.example" ]; then
      ui_print "- Creating $ENV_FILE from template (edit it before reboot)"
      cp -f "$MODPATH/.env.example" "$ENV_FILE"
      chmod 0600 "$ENV_FILE"
      ui_print "- No beszel.txt found in internal storage"
      ui_print "- To auto-load config, place beszel.txt in /sdcard/ before install"
    else
      ui_print "! No .env.example found; create $ENV_FILE manually"
    fi
  fi
else
  ui_print "- Keeping existing $ENV_FILE"
fi

# Architecture detection and binary download
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

BESZEL_URL="https://github.com/henrygd/beszel/releases/latest/download/beszel-agent_linux_${BESZEL_ARCH}.tar.gz"
ui_print "- Downloading latest beszel-agent..."

DOWNLOADED=0
if command -v curl >/dev/null 2>&1; then
  if curl -sLo beszel-agent.tar.gz "$BESZEL_URL"; then
    DOWNLOADED=1
  fi
fi

if [ "$DOWNLOADED" = 0 ] && command -v wget >/dev/null 2>&1; then
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

ui_print "- Config directory: $CONFIG_DIR"
ui_print "- Data directory: $DATA_DIR"
ui_print "- Done. Edit $ENV_FILE then reboot."
