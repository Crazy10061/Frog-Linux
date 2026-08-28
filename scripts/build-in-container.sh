#!/usr/bin/env bash
set -euo pipefail

if [ ! -f /var/local-repo/frog-local.db.tar.zst ]; then
  echo "ERROR: /var/local-repo is empty, so this is not the toolchain image." >&2
  echo "Build it first:  docker build -t frog-linux-build docker/" >&2
  echo "Or just run scripts/build-local.sh, which does both steps." >&2
  exit 1
fi

echo "==> [1/2] Set up archiso profile"
rm -rf ./frog-profile ./work
cp -r /usr/share/archiso/configs/releng/ ./frog-profile

sed -i 's/^\s*DownloadUser\s*=/#&/' ./frog-profile/pacman.conf || true

find ./frog-profile/syslinux ./frog-profile/grub ./frog-profile/efiboot \
     -type f \( -name '*.cfg' -o -name '*.conf' \) -print0 |
  xargs -0r sed -i \
    -e 's|vmlinuz-linux |vmlinuz-linux-cachyos |g' \
    -e 's|vmlinuz-linux$|vmlinuz-linux-cachyos|g' \
    -e 's|initramfs-linux\.img|initramfs-linux-cachyos.img|g' \
    -e '/archisobasedir=/ s|archisobasedir=|cow_spacesize=2G archisobasedir=|'

PRESET_DIR=./frog-profile/airootfs/etc/mkinitcpio.d
mkdir -p "$PRESET_DIR"
rm -f "$PRESET_DIR/linux.preset"
cat > "$PRESET_DIR/linux-cachyos.preset" <<'EOF'
PRESETS=('archiso')
ALL_kver="/boot/vmlinuz-linux-cachyos"
archiso_config="/etc/mkinitcpio.conf.d/archiso.conf"
archiso_image="/boot/initramfs-linux-cachyos.img"
EOF

cat >> ./frog-profile/profiledef.sh <<'EOF'
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')

iso_name="frog"
iso_label="FROG_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Frog Linux <https://github.com/Crazy10061/Frog-Linux>"
iso_application="Frog Linux Live/Install CD"

file_permissions+=(
  ["/usr/local/bin/frog-init.sh"]="0:0:755"
  ["/usr/local/bin/frog-install-browser.sh"]="0:0:755"
  ["/usr/local/bin/frog-patch-tauri-desktop.sh"]="0:0:755"
  ["/usr/local/bin/frog-postinstall-cleanup.sh"]="0:0:755"
  ["/etc/skel/Desktop/install-frog-linux.desktop"]="0:0:755"
  ["/etc/sudoers.d/g_wheel"]="0:0:440"
  ["/etc/passwd"]="0:0:644"
)
EOF

cat >> ./frog-profile/pacman.conf <<'EOF'

[frog-local]
SigLevel = Optional TrustAll
Server = file:///var/local-repo

[cachyos]
SigLevel = Required DatabaseOptional
Server = https://mirror.cachyos.org/repo/$arch/$repo
EOF

cat >> ./frog-profile/airootfs/etc/pacman.conf <<'EOF'

[cachyos]
SigLevel = Required DatabaseOptional
Server = https://mirror.cachyos.org/repo/x86_64/cachyos
EOF
sed -i '/^\[options\]/a IgnorePkg = webkit2gtk-4.1 webkit2gtk' ./frog-profile/airootfs/etc/pacman.conf

cp archiso/packages.x86_64 ./frog-profile/packages.x86_64
sed -i 's/\r$//' ./frog-profile/packages.x86_64

if [ -d "archiso/airootfs" ]; then
  cp -r archiso/airootfs/. ./frog-profile/airootfs/
fi

AIROOTFS=./frog-profile/airootfs

mkdir -p "$AIROOTFS/etc/flatpak/remotes.d"
curl -fsSL https://flathub.org/repo/flathub.flatpakrepo \
     -o "$AIROOTFS/etc/flatpak/remotes.d/flathub.flatpakrepo"

ln -sf /usr/lib/systemd/system/graphical.target \
       "$AIROOTFS/etc/systemd/system/default.target"

WANTS_MU="$AIROOTFS/etc/systemd/system/multi-user.target.wants"
WANTS_GR="$AIROOTFS/etc/systemd/system/graphical.target.wants"
mkdir -p "$WANTS_MU" "$WANTS_GR"

rm -f "$WANTS_MU"/{sshd,iwd,ModemManager,livecd-talk}.service
rm -f "$WANTS_MU"/hv_{fcopy,kvp,vss}_daemon.service
rm -f "$AIROOTFS/etc/systemd/system/sockets.target.wants/pcscd.socket"
rm -f "$WANTS_MU/systemd-networkd.service"
rm -f "$AIROOTFS/etc/systemd/system/sockets.target.wants/systemd-networkd.socket"
rm -rf "$AIROOTFS/etc/systemd/system/network-online.target.wants"

ln -sf /usr/lib/systemd/system/NetworkManager.service "$WANTS_MU/NetworkManager.service"
ln -sf /usr/lib/systemd/system/sddm.service           "$WANTS_GR/sddm.service"
ln -sf /usr/lib/systemd/system/ananicy-cpp.service    "$WANTS_MU/ananicy-cpp.service" || true
ln -sf /usr/lib/systemd/system/bluetooth.service      "$WANTS_MU/bluetooth.service" || true
ln -sf /usr/lib/systemd/system/cups.service           "$WANTS_MU/cups.service" || true
ln -sf /usr/lib/systemd/system/vboxservice.service      "$WANTS_MU/vboxservice.service" || true
ln -sf /usr/lib/systemd/system/qemu-guest-agent.service "$WANTS_MU/qemu-guest-agent.service" || true
ln -sf /usr/lib/systemd/system/vmtoolsd.service         "$WANTS_MU/vmtoolsd.service" || true

echo "==> [2/2] Build ISO with mkarchiso"
WORK=/var/tmp/frog-work
rm -rf "$WORK"
mkdir -p "$WORK" ./output

mkarchiso -v -w "$WORK" -o "$(pwd)/output" ./frog-profile

echo
echo "==> Done. ISO(s) in ./output/:"
ls -lh ./output/
