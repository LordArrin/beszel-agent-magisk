# Beszel Agent Magisk Module

Runs [beszel-agent](https://github.com/henrygd/beszel) as a Magisk **late_start** service on Android (ARM / ARM64).

## Requirements

- Magisk **v20.4+** (recommended: current Magisk)
- Device ABI: `arm64-v8a` / `aarch64` **or** `armeabi-v7a` / 32-bit ARM
- A reachable Beszel Hub and agent credentials (`KEY`, `TOKEN`, `HUB_URL`)

## Install

1. Flash `beszel-agent-magisk-vX.Y.Z.zip` in Magisk Manager (Modules → Install from storage).
2. Edit config:

   ```text
   /data/adb/modules/beszel-agent/.env
   ```

   ```env
   KEY=ssh-ed25519 AAAA...
   TOKEN=your-token
   HUB_URL=http://your-hub:8090
   # optional
   FILESYSTEM=/data
   ```

3. Reboot. The agent starts after `sys.boot_completed`.

## Architecture selection

Handled in `customize.sh` at install time using Magisk’s `$ARCH`:

| Magisk `$ARCH` | Typical ABIs                         | Binary used            |
|----------------|--------------------------------------|------------------------|
| `arm64`        | `arm64-v8a`, `aarch64`               | `beszel-agent-arm64`   |
| `arm`          | `armeabi-v7a`, `armv7l`, `armv8l` 32-bit | `beszel-agent-arm` |

The selected binary is renamed to `bin/beszel-agent`; the other is removed to save space.

## Runtime

`service.sh` (late_start):

Magisk runs `service` stage with **`fork_dont_care`** (non-blocking).  
`service.sh` therefore:

1. Waits for `sys.boot_completed`
2. Loads `KEY` / `TOKEN` / `HUB_URL` (and optional `FILESYSTEM`) from `.env`
3. Spawns a **background supervisor** and exits immediately
4. Supervisor runs the agent and restarts it on death with exponential backoff:

   ```text
   1s → 2s → 4s → 8s → … → 300s (cap)
   ```

   If a run stayed up ≥ 60s, the next backoff resets to **1s**.

   ```sh
   FILESYSTEM="/data" ./beszel-agent -k "$KEY" -t "$TOKEN" --url "$HUB_URL"
   ```

Equivalent intent to systemd `Restart=always` with exponential `RestartSec`.  
Only handles **process exit**, not hung-but-alive agents.

Agent state (fingerprint) is stored under `DATA_DIR` (default `/data/adb/modules/beszel-agent/data`). Android has no usable `/var/lib/beszel-agent`; without `DATA_DIR` the agent cannot persist identity and Hub may reject with `fingerprint mismatch` after re-registration.

Logs: `/data/adb/modules/beszel-agent/beszel-agent.log`  
Supervisor pid: `/data/adb/modules/beszel-agent/supervise.pid`

## Project layout

```text
module/
  module.prop
  customize.sh          # arch detect + binary install
  service.sh            # late_start launcher
  .env.example          # template (no secrets)
  bin/
    beszel-agent-arm
    beszel-agent-arm64
  META-INF/com/google/android/
    update-binary
    updater-script
```

## Build zips

```sh
# public release (no credentials)
./build.sh

# or on Windows PowerShell
./build.ps1
```

Outputs under `dist/`:

- `beszel-agent-magisk-vX.Y.Z.zip` — publishable (uses `.env.example` only)
- `beszel-agent-magisk-vX.Y.Z-personal.zip` — includes your local `module/.env` (gitignored)

## Manual test (root adb)

Read-only arch check:

```sh
adb shell getprop ro.product.cpu.abi
adb shell uname -m
```

After install, without rebooting you can dry-run the binary (will connect to your hub):

```sh
adb shell su -c '/data/adb/modules/beszel-agent/bin/beszel-agent -h'
```

## License

This Magisk module packaging is released under the **BSD 3-Clause License** (see [LICENSE](LICENSE)).

Upstream `beszel-agent` binaries are from [henrygd/beszel](https://github.com/henrygd/beszel) and remain under that project’s license.
