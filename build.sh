#!/usr/bin/env bash
# Build Magisk module zips (publish + personal). Works in Git Bash / WSL / Linux.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
MODULE="$ROOT/module"
DIST="$ROOT/dist"
PROP="$MODULE/module.prop"

version="$(grep -E '^version=' "$PROP" | head -n1 | cut -d= -f2- | tr -d '\r')"
version="${version:-v1.0.0}"

mkdir -p "$DIST"

# LF-normalize shell/text files Magisk will execute
normalize_lf() {
  local f="$1"
  [ -f "$f" ] || return 0
  # skip binary
  if grep -q $'\0' "$f" 2>/dev/null; then return 0; fi
  if command -v sed >/dev/null 2>&1; then
    sed -i 's/\r$//' "$f" 2>/dev/null || perl -pi -e 's/\r\n?/\n/g' "$f"
  fi
}

for f in module.prop customize.sh service.sh .env.example .env \
         META-INF/com/google/android/update-binary \
         META-INF/com/google/android/updater-script; do
  normalize_lf "$MODULE/$f"
done

pack() {
  local out="$1"
  local include_env="$2"
  local stage
  stage="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$stage'" RETURN

  cp -a "$MODULE"/. "$stage"/
  if [ "$include_env" != "1" ]; then
    rm -f "$stage/.env"
  else
    [ -f "$stage/.env" ] || { echo "module/.env missing for personal zip" >&2; exit 1; }
  fi
  find "$stage" -name '.DS_Store' -delete 2>/dev/null || true

  rm -f "$out"
  (
    cd "$stage"
    if command -v zip >/dev/null 2>&1; then
      zip -r -9 "$out" .
    else
      # fallback: python zipfile
      python - "$out" <<'PY'
import sys, os, zipfile
out = sys.argv[1]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk('.'):
        for name in files:
            path = os.path.join(root, name)
            z.write(path, arcname=os.path.relpath(path, '.'))
print(out)
PY
    fi
  )
  echo "Created $out ($(wc -c < "$out") bytes)"
}

pub="$DIST/beszel-agent-magisk-${version}.zip"
personal="$DIST/beszel-agent-magisk-${version}-personal.zip"

pack "$pub" 0
pack "$personal" 1

echo
echo "Publish : $pub"
echo "Personal: $personal"
