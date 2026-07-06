#!/usr/bin/env bash
set -e

# 1. Install required build dependencies on the host
sudo apt-get update
sudo apt-get install -y debootstrap squashfs-tools xorriso isolinux syslinux-common

# 2. Create workspaces
mkdir -p live_boot/chroot
mkdir -p live_boot/image/live
mkdir -p live_boot/image/isolinux

# 3. Bootstrap a minimal Debian stable system
sudo debootstrap --arch=amd64 bookworm live_boot/chroot http://deb.debian.org/debian/

# 4. Configure RinthOS settings (Chroot)
echo "rinthos" | sudo tee live_boot/chroot/etc/hostname
echo "Welcome to RinthOS (Live Mode)" | sudo tee live_boot/chroot/etc/issue

sudo chroot live_boot/chroot apt-get update
sudo chroot live_boot/chroot apt-get install -y --no-install-recommends linux-image-amd64 live-boot systemd-sysv

# 5. Copy kernel and initrd out to the bootable image folder
sudo cp live_boot/chroot/vmlinuz live_boot/image/vmlinuz
sudo cp live_boot/chroot/initrd.img live_boot/image/initrd.img

# 6. Compress the filesystem into a SquashFS image
sudo mksquashfs live_boot/chroot live_boot/image/live/filesystem.squashfs -comp xz -e boot

# 7. Set up the bootloader configuration (ISOLINUX)
sudo cp /usr/lib/ISOLINUX/isolinux.bin live_boot/image/isolinux/
sudo cp /usr/lib/syslinux/modules/bios/ldlinux.c32 live_boot/image/isolinux/

cat << 'EOF' | sudo tee live_boot/image/isolinux/isolinux.cfg
default rinthos
label rinthos
  kernel /vmlinuz
  append initrd=/initrd.img boot=live quiet splash
EOF

# 8. Package everything into the final RinthOS ISO
sudo xorriso -as mkisofs \
  -iso-level 3 \
  -full-iso9660-filenames \
  -volid "RinthOS" \
  -eltorito-boot isolinux/isolinux.bin \
  -eltorito-catalog isolinux/boot.cat \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -output rinthos-amd64.iso \
  live_boot/image

echo "RinthOS Build complete"
