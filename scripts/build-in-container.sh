#!/usr/bin/env bash
# Runs INSIDE an archlinux:latest container. Mirrors .github/workflows/build.yml.
set -euo pipefail

# --- Disable pacman's alpm sandbox ---
# pacman 7+ switches to user 'alpm' + applies seccomp for downloads.
# Under QEMU x86_64-on-ARM emulation, seccomp() calls fail with EINVAL (22),
# breaking every pacman sync. Comment out DownloadUser so pacman runs as root
# with no seccomp. Only needed for local emulated builds; harmless on native.
sed -i 's/^\s*DownloadUser\s*=/#&/' /etc/pacman.conf || true

echo "==> [1/4] Initialize pacman keyring"
# Both commands are internally idempotent — safe to run every time.
pacman-key --init
pacman-key --populate archlinux

echo "==> [2/4] Sync keyring, add CachyOS repo, install build tools"
pacman -Syy --noconfirm --needed archlinux-keyring ca-certificates curl

if ! grep -q '^\[cachyos\]' /etc/pacman.conf; then
  pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
  pacman-key --lsign-key F3B607488DB35A47
  cat >> /etc/pacman.conf <<'EOF'

[cachyos]
SigLevel = Required DatabaseOptional
Server = https://mirror.cachyos.org/repo/$arch/$repo
EOF
fi

pacman -Syy --noconfirm
pacman -S --noconfirm --needed cachyos-keyring cachyos-mirrorlist
pacman -S --noconfirm --needed archiso git tar

echo "==> [3/4] Set up archiso profile"
rm -rf ./frog-profile ./work
cp -r /usr/share/archiso/configs/releng/ ./frog-profile

# Same alpm-sandbox disable for the profile pacman.conf pacstrap will use
sed -i 's/^\s*DownloadUser\s*=/#&/' ./frog-profile/pacman.conf || true

# Override the squashfs compressor to zstd (default is xz). zstd at level 15
# is ~3-5x faster to compress with only ~5-10% larger output — worth it for
# both local iteration under QEMU and CI runtime.
cat >> ./frog-profile/profiledef.sh <<'EOF'
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')
EOF

cat >> ./frog-profile/pacman.conf <<'EOF'

[cachyos]
SigLevel = Required DatabaseOptional
Server = https://mirror.cachyos.org/repo/$arch/$repo
EOF

cat >> ./frog-profile/airootfs/etc/pacman.conf <<'EOF'

[cachyos]
SigLevel = Required DatabaseOptional
Server = https://mirror.cachyos.org/repo/x86_64/cachyos
EOF

cp archiso/packages.x86_64 ./frog-profile/packages.x86_64
# Strip CRLF from the package list if the repo was checked out on Windows —
# mkarchiso does exact-string matches and a trailing \r breaks validation.
sed -i 's/\r$//' ./frog-profile/packages.x86_64

if [ -d "archiso/airootfs" ]; then
  cp -r archiso/airootfs/. ./frog-profile/airootfs/
fi

AIROOTFS=./frog-profile/airootfs
mkdir -p "$AIROOTFS/etc" "$AIROOTFS/home/arch"
touch "$AIROOTFS/etc/passwd" "$AIROOTFS/etc/shadow" "$AIROOTFS/etc/group" "$AIROOTFS/etc/gshadow"
grep -q '^arch:' "$AIROOTFS/etc/passwd" 2>/dev/null || \
  echo 'arch:x:1000:1000:Live User:/home/arch:/bin/bash' >> "$AIROOTFS/etc/passwd"
grep -q '^arch:' "$AIROOTFS/etc/shadow" 2>/dev/null || \
  echo 'arch::19000:0:99999:7:::' >> "$AIROOTFS/etc/shadow"
grep -q '^arch:' "$AIROOTFS/etc/group" 2>/dev/null || \
  echo 'arch:x:1000:' >> "$AIROOTFS/etc/group"
if grep -q '^wheel:' "$AIROOTFS/etc/group"; then
  sed -i '/^wheel:/ s/$/arch/' "$AIROOTFS/etc/group"
else
  echo 'wheel:x:998:arch' >> "$AIROOTFS/etc/group"
fi
if grep -q '^autologin:' "$AIROOTFS/etc/group"; then
  sed -i '/^autologin:/ s/$/arch/' "$AIROOTFS/etc/group"
else
  echo 'autologin:x:997:arch' >> "$AIROOTFS/etc/group"
fi
cp -rT "$AIROOTFS/etc/skel" "$AIROOTFS/home/arch"

WANTS_MU="$AIROOTFS/etc/systemd/system/multi-user.target.wants"
WANTS_GR="$AIROOTFS/etc/systemd/system/graphical.target.wants"
mkdir -p "$WANTS_MU" "$WANTS_GR"
ln -sf /usr/lib/systemd/system/NetworkManager.service "$WANTS_MU/NetworkManager.service"
ln -sf /usr/lib/systemd/system/lightdm.service        "$WANTS_GR/lightdm.service"
ln -sf /usr/lib/systemd/system/ananicy-cpp.service    "$WANTS_MU/ananicy-cpp.service" || true
ln -sf /usr/lib/systemd/system/bluetooth.service      "$WANTS_MU/bluetooth.service" || true
ln -sf /usr/lib/systemd/system/cups.service           "$WANTS_MU/cups.service" || true

chmod 0440 "$AIROOTFS/etc/sudoers.d/g_wheel"
chmod +x   "$AIROOTFS/usr/local/bin/frog-init.sh" || true

echo "==> [4/4] Build ISO with mkarchiso"
# The work dir MUST be on a case-sensitive filesystem. If /build is a Windows
# bind mount (NTFS), pacman fails on /usr/lib/Xorg (file) vs /usr/lib/xorg/
# (dir) because NTFS folds them together. Keep work on container ext4 and
# only copy the final ISO back to /build/output.
WORK=/var/tmp/frog-work
rm -rf "$WORK"
mkdir -p "$WORK" ./output

mkarchiso -v -w "$WORK" -o "$(pwd)/output" ./frog-profile

echo
echo "==> Done. ISO(s) in ./output/:"
ls -lh ./output/
