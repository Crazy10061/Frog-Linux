#!/usr/bin/env bash
# Runs INSIDE an archlinux:latest container. Mirrors .github/workflows/build.yml.
set -euo pipefail

# --- Disable pacman's alpm sandbox ---
# pacman 7+ switches to user 'alpm' + applies seccomp for downloads.
# Under QEMU x86_64-on-ARM emulation, seccomp() calls fail with EINVAL (22),
# breaking every pacman sync. Comment out DownloadUser so pacman runs as root
# with no seccomp. Only needed for local emulated builds; harmless on native.
sed -i 's/^\s*DownloadUser\s*=/#&/' /etc/pacman.conf || true

echo "==> [1/5] Initialize pacman keyring"
# Both commands are internally idempotent — safe to run every time.
pacman-key --init
pacman-key --populate archlinux

echo "==> [2/5] Sync keyring, add CachyOS repo, install build tools"
pacman -Syy --noconfirm --needed archlinux-keyring ca-certificates curl

if ! grep -q '^\[cachyos\]' /etc/pacman.conf; then
  # Public keyservers are flaky (keyserver.ubuntu.com has returned "Server
  # indicated a failure" for hours at a stretch). Try several before giving up.
  CACHY_KEY=F3B607488DB35A47
  key_ok=0
  for ks in \
      hkps://keyserver.ubuntu.com \
      hkps://keys.openpgp.org \
      hkps://pgp.mit.edu \
      hkps://keys.mailvelope.com \
      keyserver.ubuntu.com; do
    echo "==> Trying keyserver $ks"
    if pacman-key --recv-keys "$CACHY_KEY" --keyserver "$ks"; then
      key_ok=1
      break
    fi
    echo "==> keyserver $ks failed, trying next..."
  done
  if [ "$key_ok" = 0 ]; then
    echo "==> All keyservers failed; fetching CachyOS signing key from GitHub"
    curl -fsSL \
      "https://raw.githubusercontent.com/CachyOS/CachyOS-PKGBUILDS/master/cachyos-keyring/cachyos.gpg" \
      | pacman-key --add -
  fi
  pacman-key --lsign-key "$CACHY_KEY"
  cat >> /etc/pacman.conf <<'EOF'

[cachyos]
SigLevel = Required DatabaseOptional
Server = https://mirror.cachyos.org/repo/$arch/$repo
EOF
fi

pacman -Syy --noconfirm
pacman -S --noconfirm --needed cachyos-keyring cachyos-mirrorlist
pacman -S --noconfirm --needed archiso git tar

echo "==> [3/5] Build calamares from AUR (contextualprocess + packagechooser)"
# cachyos-calamares strips contextualprocess; AUR calamares strips
# packagechooser. We need both modules for the browser picker, so rebuild
# the AUR package with packagechooser un-skipped, then serve it from a
# file:// pacman repo the archiso profile prefers over [cachyos].
if [ ! -f /var/local-repo/frog-local.db.tar.zst ]; then
  pacman -S --noconfirm --needed base-devel sudo \
    kcoreaddons kpmcore libpwquality qt6-declarative qt6-svg yaml-cpp \
    extra-cmake-modules libglvnd ninja qt6-tools qt6-translations

  # makepkg refuses to run as root — create an unprivileged builder.
  if ! id builder >/dev/null 2>&1; then
    useradd -m -G wheel builder
    echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder
  fi

  # Fresh checkout each run so re-running against an updated AUR PKGBUILD
  # doesn't reuse a stale tree.
  rm -rf /tmp/calamares
  sudo -Hu builder bash -euxo pipefail <<'BUILD'
cd /tmp
git clone --depth 1 https://aur.archlinux.org/calamares.git
cd calamares

# Drop packagechooser from the skip list so the resulting package ships
# that module too (we reference it in settings.conf). Leave packagechooserq
# skipped — we don't use the Qt-only variant.
sed -i '/^\s*packagechooser$/d' PKGBUILD

makepkg -s --noconfirm --nosign
BUILD

  mkdir -p /var/local-repo
  cp /tmp/calamares/calamares-*.pkg.tar.zst /var/local-repo/
  repo-add /var/local-repo/frog-local.db.tar.zst /var/local-repo/*.pkg.tar.zst
else
  echo "==> /var/local-repo already populated, skipping rebuild"
fi

echo "==> [4/5] Set up archiso profile"
rm -rf ./frog-profile ./work
cp -r /usr/share/archiso/configs/releng/ ./frog-profile

# Same alpm-sandbox disable for the profile pacman.conf pacstrap will use
sed -i 's/^\s*DownloadUser\s*=/#&/' ./frog-profile/pacman.conf || true

# Rewrite releng boot menus + mkinitcpio preset for linux-cachyos.
find ./frog-profile/syslinux ./frog-profile/grub ./frog-profile/efiboot \
     -type f \( -name '*.cfg' -o -name '*.conf' \) -print0 |
  xargs -0r sed -i \
    -e 's|vmlinuz-linux |vmlinuz-linux-cachyos |g' \
    -e 's|vmlinuz-linux$|vmlinuz-linux-cachyos|g' \
    -e 's|initramfs-linux\.img|initramfs-linux-cachyos.img|g'

PRESET_DIR=./frog-profile/airootfs/etc/mkinitcpio.d
mkdir -p "$PRESET_DIR"
rm -f "$PRESET_DIR/linux.preset"
cat > "$PRESET_DIR/linux-cachyos.preset" <<'EOF'
# mkinitcpio preset for linux-cachyos (Frog Linux archiso build)
PRESETS=('archiso')
ALL_kver="/boot/vmlinuz-linux-cachyos"
archiso_config="/etc/mkinitcpio.conf.d/archiso.conf"
archiso_image="/boot/initramfs-linux-cachyos.img"
EOF

# Override the squashfs compressor to zstd (default is xz). zstd at level 15
# is ~3-5x faster to compress with only ~5-10% larger output — worth it for
# both local iteration under QEMU and CI runtime.
cat >> ./frog-profile/profiledef.sh <<'EOF'
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')
EOF

# [frog-local] holds the AUR-built calamares (with contextualprocess +
# packagechooser); listed BEFORE [cachyos] so pacstrap resolves "calamares"
# to the local build instead of cachyos-calamares (which conflicts=calamares).
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
# Strip CRLF from the package list if the repo was checked out on Windows —
# mkarchiso does exact-string matches and a trailing \r breaks validation.
sed -i 's/\r$//' ./frog-profile/packages.x86_64

if [ -d "archiso/airootfs" ]; then
  cp -r archiso/airootfs/. ./frog-profile/airootfs/
fi

AIROOTFS=./frog-profile/airootfs
mkdir -p "$AIROOTFS/etc" "$AIROOTFS/home/admin"
touch "$AIROOTFS/etc/passwd" "$AIROOTFS/etc/shadow" "$AIROOTFS/etc/group" "$AIROOTFS/etc/gshadow"
grep -q '^admin:' "$AIROOTFS/etc/passwd" 2>/dev/null || \
  echo 'admin:x:1000:1000:Live User:/home/admin:/bin/bash' >> "$AIROOTFS/etc/passwd"
grep -q '^admin:' "$AIROOTFS/etc/shadow" 2>/dev/null || \
  echo 'admin:$6$qWGoNTRX6yQfhnlJ$O96L0iZSxurKLSaQwvi7gXxRdzQR9cpWjvt8rslC29hHL76Wh.MfY0XfFhag4ld2.uVeV58JE6EGBT1m/.LcA0:19000:0:99999:7:::' >> "$AIROOTFS/etc/shadow"
grep -q '^admin:' "$AIROOTFS/etc/group" 2>/dev/null || \
  echo 'admin:x:1000:' >> "$AIROOTFS/etc/group"
add_to_group() {
  local grp="$1" file="$AIROOTFS/etc/group"
  if grep -qE "^${grp}:[^:]*:[^:]*:.*\badmin\b" "$file"; then
    return 0
  fi
  if grep -qE "^${grp}:[^:]*:[^:]*:$" "$file"; then
    sed -i "/^${grp}:/ s/\$/admin/" "$file"
  elif grep -qE "^${grp}:" "$file"; then
    sed -i "/^${grp}:/ s/\$/,admin/" "$file"
  else
    echo "${grp}:x:$2:admin" >> "$file"
  fi
}
add_to_group wheel     998
# SDDM's autologin doesn't gate on any group — no autologin membership needed.

cp -rT "$AIROOTFS/etc/skel" "$AIROOTFS/home/admin"
# xfce4-session needs the live user to own their own home; otherwise
# login succeeds then session dies silently.
chown -R 1000:1000 "$AIROOTFS/home/admin"

# Switch default.target from multi-user (releng default, CLI-only) to
# graphical, otherwise lightdm never starts.
ln -sf /usr/lib/systemd/system/graphical.target \
       "$AIROOTFS/etc/systemd/system/default.target"

WANTS_MU="$AIROOTFS/etc/systemd/system/multi-user.target.wants"
WANTS_GR="$AIROOTFS/etc/systemd/system/graphical.target.wants"
mkdir -p "$WANTS_MU" "$WANTS_GR"
ln -sf /usr/lib/systemd/system/NetworkManager.service "$WANTS_MU/NetworkManager.service"
ln -sf /usr/lib/systemd/system/sddm.service           "$WANTS_GR/sddm.service"
ln -sf /usr/lib/systemd/system/ananicy-cpp.service    "$WANTS_MU/ananicy-cpp.service" || true
ln -sf /usr/lib/systemd/system/bluetooth.service      "$WANTS_MU/bluetooth.service" || true
ln -sf /usr/lib/systemd/system/cups.service           "$WANTS_MU/cups.service" || true
# VM guest tools — no-op on bare metal, essential inside a hypervisor
ln -sf /usr/lib/systemd/system/vboxservice.service      "$WANTS_MU/vboxservice.service" || true
ln -sf /usr/lib/systemd/system/qemu-guest-agent.service "$WANTS_MU/qemu-guest-agent.service" || true
ln -sf /usr/lib/systemd/system/vmtoolsd.service         "$WANTS_MU/vmtoolsd.service" || true

chmod 0440 "$AIROOTFS/etc/sudoers.d/g_wheel"
chmod +x   "$AIROOTFS/usr/local/bin/frog-init.sh" || true
chmod +x   "$AIROOTFS/usr/local/bin/frog-patch-tauri-desktop.sh" || true
chmod +x   "$AIROOTFS/etc/profile.d/tauri-compat.sh" || true
# customize_airootfs.sh must be executable — mkarchiso runs it via arch-chroot
# after pacstrap, and it's what forces the archiso-flavored initramfs onto the
# linux-cachyos preset (see the script itself for details).
chmod +x   "$AIROOTFS/root/customize_airootfs.sh"

echo "==> [5/5] Build ISO with mkarchiso"
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
