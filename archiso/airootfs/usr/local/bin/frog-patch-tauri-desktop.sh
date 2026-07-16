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

    read -r -a tokens <<< "${exec_line#Exec=}"
    bin_path=""
    i=0
    while [ "$i" -lt "${#tokens[@]}" ]; do
      tok="${tokens[$i]}"
      case "$tok" in
        env)
          i=$((i + 1))
          while [ "$i" -lt "${#tokens[@]}" ] && [[ "${tokens[$i]}" == *=* ]]; do
            i=$((i + 1))
          done
          continue
          ;;
        sh|bash)
          i=$((i + 1))
          while [ "$i" -lt "${#tokens[@]}" ] && [ "${tokens[$i]}" != "-c" ]; do
            i=$((i + 1))
          done
          if [ "$i" -lt "${#tokens[@]}" ]; then
            i=$((i + 1))
            read -r -a inner <<< "${tokens[$i]:-}"
            tok="${inner[0]:-}"
          fi
          ;;
        flatpak)
          i=$((i + 1))
          while [ "$i" -lt "${#tokens[@]}" ] && [ "${tokens[$i]}" != "run" ]; do
            i=$((i + 1))
          done
          i=$((i + 1))
          while [ "$i" -lt "${#tokens[@]}" ] && [[ "${tokens[$i]}" == --* ]]; do
            i=$((i + 1))
          done
          tok="${tokens[$i]:-}"
          ;;
      esac
      candidate=$(command -v "$(basename "${tok%%%*}" 2>/dev/null)" 2>/dev/null || true)
      [ -n "$candidate" ] && bin_path="$candidate" && break
      i=$((i + 1))
    done
    [ -n "$bin_path" ] || continue

    if ldd "$bin_path" 2>/dev/null | grep -qi 'libwebkit2gtk'; then
      sed -i \
        "s|^Exec=|Exec=env WEBKIT_DISABLE_DMABUF_RENDERER=1 WEBKIT_DISABLE_COMPOSITING_MODE=1 |" \
        "$desktop"
      printf '\n# %s\n' "$MARKER" >> "$desktop"
    fi
  done
done
