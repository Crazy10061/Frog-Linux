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
