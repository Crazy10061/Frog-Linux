#!/bin/bash
# Runs on Plasma login via ~/.config/autostart/frog-init.desktop

# Apply the Frog wallpaper. plasma-apply-wallpaperimage ships with plasma-workspace
# and talks to the running Plasma session, so this only works after login.
if command -v plasma-apply-wallpaperimage >/dev/null; then
  plasma-apply-wallpaperimage "$HOME/Wallpapers/frog.png" 2>/dev/null || true
fi

# Convenient shell aliases
grep -q "alias fetch='fastfetch'" ~/.bashrc 2>/dev/null || \
  echo "alias fetch='fastfetch'" >> ~/.bashrc
grep -q "alias neofetch='fastfetch'" ~/.bashrc 2>/dev/null || \
  echo "alias neofetch='fastfetch'" >> ~/.bashrc

if systemctl is-active --quiet NetworkManager; then
    (
        for _ in {1..30}; do
            if getent hosts archlinux.org >/dev/null 2>&1; then
                pacman -Sy --noconfirm >/dev/null 2>&1 || true
                break
            fi
            sleep 2
        done
    ) &
fi
