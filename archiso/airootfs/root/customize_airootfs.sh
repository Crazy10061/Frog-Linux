#!/usr/bin/env bash
# Runs INSIDE the pacstrapped airootfs chroot (mkarchiso _make_customize_airootfs).
# Purpose: guarantee the linux-cachyos initramfs is built with the archiso
# hooks. Placing the preset in the airootfs overlay isn't enough — pacstrap
# installs the linux-cachyos package AFTER the overlay is copied, so the
# stock preset (PRESETS=('default' 'fallback')) wins and the resulting
# initramfs has no archiso init, causing:
#   Kernel panic - not syncing: VFS: Unable to mount root fs on unknown-block(0,0)
# Running this in-chroot after pacstrap lets us overwrite the preset and
# regenerate the image with archiso hooks.
set -euo pipefail

cat > /etc/mkinitcpio.d/linux-cachyos.preset <<'EOF'
# mkinitcpio preset for linux-cachyos (Frog Linux archiso build)
PRESETS=('archiso')
ALL_kver="/boot/vmlinuz-linux-cachyos"
archiso_config="/etc/mkinitcpio.conf.d/archiso.conf"
archiso_image="/boot/initramfs-linux-cachyos.img"
EOF

# Any preset the stock kernel package left behind can only produce a non-archiso
# initramfs. Nuke stray fallback images so they can't accidentally be picked
# up by the boot loaders.
rm -f /boot/initramfs-linux-cachyos-fallback.img

mkinitcpio -P

# Fail loud if the archiso hooks aren't actually embedded — this catches
# preset/config drift before it becomes a boot-time kernel panic. A non-archiso
# initramfs (default/fallback) contains zero paths matching 'archiso'.
# `|| true` avoids masking the miss when lsinitcpio itself errors under pipefail.
initramfs_listing="$(lsinitcpio /boot/initramfs-linux-cachyos.img 2>/dev/null || true)"
if ! grep -q 'archiso' <<< "$initramfs_listing"; then
    echo "ERROR: /boot/initramfs-linux-cachyos.img has no archiso hooks." >&2
    echo "The generated initramfs cannot mount the live squashfs and will panic on boot." >&2
    exit 1
fi
