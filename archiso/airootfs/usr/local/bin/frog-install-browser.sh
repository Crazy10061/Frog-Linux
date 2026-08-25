#!/usr/bin/env bash
set -euo pipefail

browser_package="${1:-}"
case "$browser_package" in
    brave-bin|zen-browser-bin|chromium) ;;
    *)
        echo "ERROR: unsupported browser package: $browser_package" >&2
        exit 2
        ;;
esac

pacman -Syu --noconfirm --needed "$browser_package"
pacman -Rns --noconfirm firefox
