#!/usr/bin/env bash
# Frog Linux: local ISO build in Docker (Linux port of build-local.ps1).
# Uses named volumes so pacman package cache and gnupg keyring persist across
# runs. First run: cold pacman fetch. Subsequent runs: near-instant deps.

# Usage:    ./scripts/build-local.sh

set -euo pipefail

# Resolve repo root (this script lives in scripts/)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO="$(dirname -- "$SCRIPT_DIR")"

echo "==> Repo:   $REPO"
echo "==> Output: $REPO/output"

# Sanity check
if ! command -v docker >/dev/null 2>&1; then
    echo "docker not on PATH. Install docker and make sure your user can run it" >&2
    echo "(add to the 'docker' group, or use rootless docker)." >&2
    exit 127
fi

# Persistent volumes for pacman package cache and pacman-key GnuPG state.
# These survive across container runs and repo rebuilds.
# `docker volume create` is idempotent — safe to call every run.
PAC_CACHE=frog-pacman-cache
PAC_GNUPG=frog-pacman-gnupg
docker volume create "$PAC_CACHE" >/dev/null
docker volume create "$PAC_GNUPG" >/dev/null

# Force linux/amd64
# Arch only publishes x86_64 images. 
# On x86_64 hosts this is a no-op; on ARM (Raspberry Pi, Ampere, Graviton) it triggers binfmt/QEMU emulation so the build still works, just slower.
docker run --rm --privileged \
    --platform linux/amd64 \
    --security-opt seccomp=unconfined \
    --security-opt apparmor=unconfined \
    -v "$REPO:/build" \
    -v "$PAC_CACHE:/var/cache/pacman/pkg" \
    -v "$PAC_GNUPG:/etc/pacman.d/gnupg" \
    -w /build \
    archlinux:latest \
    bash /build/scripts/build-in-container.sh

echo
echo "==> ISO(s) in $REPO/output"
ls -lh "$REPO/output"/*.iso 2>/dev/null || echo "(none — build produced no ISO)"
