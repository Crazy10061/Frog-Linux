#!/bin/bash
set -euo pipefail

MARKER="FROG_TAURI_COMPAT=1"
APPDIRS=(/usr/share/applications /usr/local/share/applications)

for dir in "${APPDIRS[@]}"; do
  [ -d "$dir" ] || continue
  for desktop in "$dir"/*.desktop; do
    [ -f "$desktop" ] || continue
    grep -q "$MARKER" "$desktop" 2>/dev/null && continue

    exec_line=$(grep -m1 '^Exec=' "$desktop" || true)
    [ -n "$exec_line" ] || continue

    bin=$(echo "${exec_line#Exec=}" | awk '{print $1}')
    bin_path=$(command -v "$bin" 2>/dev/null || true)
    [ -n "$bin_path" ] || continue

    if ldd "$bin_path" 2>/dev/null | grep -qi 'libwebkit2gtk'; then
      sed -i \
        "s|^Exec=|Exec=env WEBKIT_DISABLE_DMABUF_RENDERER=1 WEBKIT_DISABLE_COMPOSITING_MODE=1 |" \
        "$desktop"
      printf '\n# %s\n' "$MARKER" >> "$desktop"
    fi
  done
done
