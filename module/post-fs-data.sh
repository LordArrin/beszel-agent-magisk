#!/system/bin/sh

MODDIR=${0%/*}
PROP_FILE="$MODDIR/module.prop"

# Update module description to show status in KernelSU/Magisk UI
if [ -f "$PROP_FILE" ]; then
  sed -i 's|^description=.*|description=🟡 Starting beszel-agent...|' "$PROP_FILE"
fi