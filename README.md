# Beszel Agent Magisk Module

Runs [beszel-agent](https://github.com/henrygd/beszel) as a Magisk **late_start** service on Android. 

To keep the module lightweight and up-to-date, binaries are no longer bundled. The installer automatically detects your device's architecture and downloads the latest official `beszel-agent` release directly from GitHub during installation.

## Requirements

- Magisk **v20.4+** (also compatible with KernelSU / APatch)
- Device ABI: `arm64-v8a`, `armeabi-v7a`, `x86_64`, or `x86`
- **An active internet connection** during module installation (to download the agent binary)
- A reachable Beszel Hub and agent credentials (`KEY`, `TOKEN`, `HUB_URL`)

## Install

1. Flash `beszel-agent-magisk-vX.Y.Z.zip` in Magisk Manager (Modules → Install from storage). 
   *(The installer will automatically fetch the correct binary for your architecture).*
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

3. Reboot. The agent starts automatically after `sys.boot_completed`.

## Architecture selection

Handled dynamically in `customize.sh` at install time. The script maps Magisk's `$ARCH` variable to the official Beszel release assets and downloads the latest version:

| Magisk `$ARCH` | Typical ABIs                         | Beszel Asset Downloaded                  |
|----------------|--------------------------------------|------------------------------------------|
| `arm64`        | `arm64-v8a`, `aarch64`               | `beszel-agent_linux_arm64.tar.gz`        |
| `arm`          | `armeabi-v7a`, `armv7l`, `armv8l`    | `beszel-agent_linux_armv7.tar.gz`        |
| `x64`          | `x86_64`                             | `beszel-agent_linux_amd64.tar.gz`        |
| `x86`          | `i386`, `i686`                       | `beszel-agent_linux_386.tar.gz`          |

The downloaded archive is extracted, documentation files are stripped, and the binary is placed in `bin/beszel-agent`.

## Runtime

`service.sh` (late_start):

Magisk runs the `service` stage with **`fork_dont_care`** (non-blocking).  
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
*Note: Only handles **process exit**, not hung-but-alive agents.*

Agent state (fingerprint) is stored under `DATA_DIR` (default `/data/adb/modules/beszel-agent/data`). Android has no usable `/var/lib/beszel-agent`; without `DATA_DIR` the agent cannot persist identity and Hub may reject it with `fingerprint mismatch` after re-registration.

- **Logs:** `/data/adb/modules/beszel-agent/beszel-agent.log`  
- **Supervisor pid:** `/data/adb/modules/beszel-agent/supervise.pid`

## Project layout

```text
module/
  module.prop
  customize.sh          # arch detect + dynamic binary download
  service.sh            # late_start launcher
  .env.example          # template (no secrets)
  bin/                  # populated at install time (empty in repo)
  META-INF/com/google/android/
    update-binary
    updater-script
```

Outputs under `dist/` (if using a build script):

- `beszel-agent-magisk-vX.Y.Z.zip` — publishable (uses `.env.example` only)
- `beszel-agent-magisk-vX.Y.Z-personal.zip` — includes your local `module/.env` (gitignored)

## Manual test (root adb)

Read-only arch check:

```sh
adb shell getprop ro.product.cpu.abi
adb shell uname -m
```

After install, without rebooting you can dry-run the binary (will print help, or connect to your hub if credentials are set):

```sh
adb shell su -c '/data/adb/modules/beszel-agent/bin/beszel-agent -h'
```

## License

This Magisk module packaging is released under the **AGPL-3.0 license** (see [LICENSE](LICENSE)).

Upstream `beszel-agent` binaries are dynamically downloaded from [henrygd/beszel](https://github.com/henrygd/beszel) and remain under that project’s original license (MIT).