#!/bin/bash
# Set up the Modrinth green background wallpaper
xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitorvirtual1/workspace0/last-image -s /etc/skel/Wallpapers/frog.png

# Enable standard terminal settings
echo "alias fetch='fastfetch'" >> ~/.bashrc
