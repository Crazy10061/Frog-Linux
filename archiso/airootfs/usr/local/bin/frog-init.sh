#!/bin/bash
# Runs on Plasma login via ~/.config/autostart/frog-init.desktop

# Apply the Frog wallpaper. plasma-apply-wallpaperimage ships with plasma-workspace
# and talks to the running Plasma session, so this only works after login.
if command -v plasma-apply-wallpaperimage >/dev/null; then
  plasma-apply-wallpaperimage /etc/skel/Wallpapers/frog.png 2>/dev/null || true
fi

# Convenient shell alias
grep -q "alias fetch='fastfetch'" ~/.bashrc 2>/dev/null || \
  echo "alias fetch='fastfetch'" >> ~/.bashrc
