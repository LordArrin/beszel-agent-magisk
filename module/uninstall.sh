#!/system/bin/sh

MODDIR=${0%/*}
CONFIG_DIR="/data/adb/beszel-agent"
PIDFILE="$CONFIG_DIR/beszel-agent.pid"

if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$PID" ] && [ -d "/proc/$PID" ]; then
        kill -TERM "$PID" 2>/dev/null
        sleep 2
        kill -KILL "$PID" 2>/dev/null
    fi
    rm -f "$PIDFILE"
fi

killall -9 beszel-agent 2>/dev/null
rm -rf "$CONFIG_DIR/tmp"