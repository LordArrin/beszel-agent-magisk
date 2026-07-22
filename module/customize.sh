#!/system/bin/sh
# Magisk module installer customization.
# Sourced (not executed) by Magisk installer after unzip.
# $ARCH is set by Magisk: arm | arm64 | x86 | x64 | riscv64
# $IS64BIT is true/false.

# We only ship ARM binaries (arm + arm64).
case "$ARCH" in
  arm|arm64) ;;
  *)
    abort "! Unsupported architecture: $ARCH (need arm or arm64)"
    ;;
esac

ui_print "- Device architecture: $ARCH (IS64BIT=$IS64BIT)"

# Magisk $ARCH already maps:
#   arm64-v8a / aarch64  -> arm64
#   armeabi-v7a / armv7l / armv8l (32-bit userspace) -> arm
# Pick matching binary, install as a single name, drop the other.
BINDIR="$MODPATH/bin"
if [ "$ARCH" = "arm64" ]; then
  SELECTED="beszel-agent-arm64"
  REMOVED="beszel-agent-arm"
else
  SELECTED="beszel-agent-arm"
  REMOVED="beszel-agent-arm64"
fi

if [ ! -f "$BINDIR/$SELECTED" ]; then
  abort "! Missing binary: bin/$SELECTED"
fi

ui_print "- Installing $SELECTED as bin/beszel-agent"
mv -f "$BINDIR/$SELECTED" "$BINDIR/beszel-agent"
rm -f "$BINDIR/$REMOVED"

set_perm "$BINDIR/beszel-agent" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755

# Persistent agent state (fingerprint). Required on Android — default
# /var/lib/beszel-agent is not usable / not writable.
mkdir -p "$MODPATH/data"
set_perm "$MODPATH/data" 0 0 0700

# Ship a template .env if the user doesn't already have one.
# Never overwrite an existing .env (preserves credentials across updates).
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
