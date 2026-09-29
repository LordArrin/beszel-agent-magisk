# Beszel Agent Magisk Module

Runs [beszel-agent](https://github.com/henrygd/beszel) as a systemless service on Android via Magisk, KernelSU or another modern root solution. 

To keep the module lightweight and always up-to-date, binaries are not bundled. The installer automatically detects your device's architecture and downloads the latest official `beszel-agent` release directly from GitHub during installation.

## Requirements

- **Magisk v28.0+**, **KernelSU**, or **APatch**
- Device ABI: `arm64-v8a`, `armeabi-v7a`, `x86_64`, or `x86`
- **An active internet connection** during module installation (to download the agent binary)
- A reachable Beszel Hub and valid agent credentials (`KEY`, `TOKEN`, `HUB_URL`)

## Install

1. *(Optional but recommended)* Download the `beszel.txt` template from the latest release, fill in your credentials, and place it in your internal storage (`/sdcard/beszel.txt`) **before** installation.
2. Flash `beszel-agent-magisk-vX.Y.Z.zip` in your root manager (Modules → Install from storage). 
   *(The installer will automatically fetch the correct binary for your architecture and copy the config if found).*
3. If you didn't use step 1, manually edit the config:
   ```text
   /data/adb/beszel-agent/.env
   ```
   ```env
   KEY=ssh-ed25519 AAAA...
   TOKEN=your-token
   HUB_URL=http://your-hub:8090
   ```
4. Reboot your device. The agent starts automatically after `sys.boot_completed`.

## Action Button (Update & Restart)

The module includes an **Action** button in the Magisk/KernelSU manager interface. Pressing it will:
1. Check the GitHub API for a newer version of `beszel-agent`.
2. If an update is available, it safely stops the current agent, downloads, and replaces the binary.
3. Restarts the agent with the new binary (or simply restarts it if no update was found).
4. Display the last few lines of the log to confirm successful startup.

## Architecture Selection

Handled dynamically in `customize.sh` at install time. The script maps the manager's `$ARCH` variable to the official Beszel release assets:

| Manager `$ARCH` | Typical ABIs                      | Beszel Asset Downloaded           |
|-----------------|-----------------------------------|-----------------------------------|
| `arm64`         | `arm64-v8a`, `aarch64`            | `beszel-agent_linux_arm64.tar.gz` |
| `arm`           | `armeabi-v7a`, `armv7l`, `armv8l` | `beszel-agent_linux_armv7.tar.gz` |
| `x64`           | `x86_64`, `amd64`                 | `beszel-agent_linux_amd64.tar.gz` |
| `x86`           | `i386`, `i686`                    | `beszel-agent_linux_amd64.tar.gz` *(fallback)* |
| `riscv64`       | `riscv64`                         | `beszel-agent_linux_riscv64.tar.gz` |

## Runtime Behavior

`service.sh` runs in the `late_start` (non-blocking) stage:

1. Waits for `sys.boot_completed` to ensure the system is fully ready.
2. Parses `KEY`, `TOKEN`, and `HUB_URL` from `/data/adb/beszel-agent/.env`.
3. Sets `HOME=/data/adb/beszel-agent` to ensure the agent can persist its fingerprint and state files without permission issues on Android.
4. Spawns the agent directly in the background.

**Important:** The agent's state (fingerprint) is stored in `/data/adb/beszel-agent/`. Because this directory is outside the module's mount point, your agent identity persists seamlessly across module updates and reboots, preventing "fingerprint mismatch" errors on the Hub.

- **Config:** `/data/adb/beszel-agent/.env`
- **Logs:** `/data/adb/beszel-agent/beszel-agent.log`
- **Boot Log:** `/data/adb/beszel-agent/boot.log`
- **PID File:** `/data/adb/beszel-agent/beszel-agent.pid`

## Project Layout

```text
module/
  module.prop
  customize.sh          # Arch detection, version check, and dynamic binary download
  service.sh            # late_start launcher
  post-fs-data.sh       # Early boot directory preparation
  action.sh             # Update checker and manual restart handler
  uninstall.sh          # Cleanup script
  .env.example          # Configuration template
  bin/                  # Populated at install time
```

## License

This Magisk module packaging is released under the **AGPL-3.0 license** (see [LICENSE](LICENSE)).

Upstream `beszel-agent` binaries are dynamically downloaded from [henrygd/beszel](https://github.com/henrygd/beszel) and remain under that project’s original license (MIT).
