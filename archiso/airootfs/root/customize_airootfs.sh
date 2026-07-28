#!/usr/bin/env bash
# Runs inside the pacstrapped chroot via mkarchiso's _make_customize_airootfs,
# after pacstrap and after the overlay has been copied in. mkarchiso deletes
# this script afterwards, so nothing here ships on the ISO.
set -euo pipefail

# Live user's groups.
# This cannot move into the build driver, which runs before pacstrap when
# /etc/group does not exist yet. Creating it early makes pacman treat
# filesystem's /etc/group as a conflicting backup file and divert it to
# group.pacnew, which _cleanup_pacstrap_dir then deletes. By now /etc/group is
# the real one: filesystem's root entry plus whatever systemd-sysusers built
# from /usr/lib/sysusers.d, at canonical GIDs.
#
# UID 1500 keeps the live user clear of the 1000+ range Calamares hands to the
# first real account.
getent group liveuser >/dev/null || groupadd -g 1500 liveuser
getent group wheel    >/dev/null || groupadd -r wheel
usermod -g liveuser -aG wheel liveuser

# The archiso preset is already staged in the overlay and pacstrap has already
# used it: mkinitcpio's alpm hook only writes a preset when none exists, and
# linux-cachyos ships none. So the initramfs should already be correct and the
# rest of this is a check, not a fix.
rm -f /boot/initramfs-linux-cachyos-fallback.img

# Catch preset or config drift here rather than as a kernel panic at boot. A
# non-archiso initramfs contains no paths matching 'archiso'. The `|| true`
# keeps a failing lsinitcpio from masking the real result under pipefail.
initramfs_listing="$(lsinitcpio /boot/initramfs-linux-cachyos.img 2>/dev/null || true)"
if ! grep -q 'archiso' <<< "$initramfs_listing"; then
    echo "ERROR: /boot/initramfs-linux-cachyos.img has no archiso hooks." >&2
    echo "It cannot mount the live squashfs and will panic on boot." >&2
    exit 1
fi
