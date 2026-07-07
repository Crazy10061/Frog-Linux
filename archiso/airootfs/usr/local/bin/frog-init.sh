#!/bin/bash
# Runs on XFCE login via ~/.config/autostart/frog-init.desktop

xfconf-query -c xfce4-desktop \
  -p /backdrop/screen0/monitorvirtual1/workspace0/last-image \
  -s /etc/skel/Wallpapers/frog.png 2>/dev/null || true

grep -q "alias fetch='fastfetch'" ~/.bashrc 2>/dev/null || \
  echo "alias fetch='fastfetch'" >> ~/.bashrc
