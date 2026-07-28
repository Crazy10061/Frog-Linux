ARG BASE=archlinux:base

FROM ${BASE} AS pacman-base
RUN sed -i 's/^\s*DownloadUser\s*=/#&/' /etc/pacman.conf \
 && pacman-key --init \
 && pacman-key --populate archlinux \
 && pacman -Syy --noconfirm --needed archlinux-keyring ca-certificates curl

FROM pacman-base AS calamares
RUN pacman -S --noconfirm --needed base-devel sudo git \
      kcoreaddons kpmcore libpwquality qt6-declarative qt6-svg yaml-cpp \
      extra-cmake-modules libglvnd ninja qt6-tools qt6-translations
RUN useradd -m -G wheel builder \
 && echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder
ARG CALAMARES_REV=HEAD
USER builder
WORKDIR /tmp
RUN git clone https://aur.archlinux.org/calamares.git \
 && cd calamares \
 && git checkout "${CALAMARES_REV}" \
 && sed -i '/^\s*packagechooser$/d' PKGBUILD \
 && makepkg -s --noconfirm --nosign \
 && mkdir -p /tmp/out \
 && cp /tmp/calamares/calamares-*.pkg.tar.zst /tmp/out/

FROM pacman-base AS toolchain
ARG CACHY_KEY=F3B607488DB35A47
RUN set -eux; \
    key_ok=0; \
    for ks in hkps://keyserver.ubuntu.com \
              hkps://keys.openpgp.org \
              hkps://pgp.mit.edu \
              hkps://keys.mailvelope.com \
              keyserver.ubuntu.com; do \
      if pacman-key --recv-keys "$CACHY_KEY" --keyserver "$ks"; then key_ok=1; break; fi; \
      echo "keyserver $ks failed, trying next..."; \
    done; \
    if [ "$key_ok" = 0 ]; then \
      curl -fsSL "https://raw.githubusercontent.com/CachyOS/CachyOS-PKGBUILDS/master/cachyos-keyring/cachyos.gpg" \
        | pacman-key --add -; \
    fi; \
    pacman-key --lsign-key "$CACHY_KEY"
RUN printf '\n[cachyos]\nSigLevel = Required DatabaseOptional\nServer = https://mirror.cachyos.org/repo/$arch/$repo\n' \
      >> /etc/pacman.conf \
 && pacman -Syy --noconfirm \
 && pacman -S --noconfirm --needed cachyos-keyring cachyos-mirrorlist \
 && pacman -S --noconfirm --needed archiso git tar
COPY --from=calamares /tmp/out/ /var/local-repo/
RUN repo-add /var/local-repo/frog-local.db.tar.zst /var/local-repo/*.pkg.tar.zst
WORKDIR /build
ENTRYPOINT ["/bin/bash"]
CMD ["/build/scripts/build-in-container.sh"]
