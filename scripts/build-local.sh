#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO="$(dirname -- "$SCRIPT_DIR")"

IMAGE=frog-linux-build

echo "==> Repo:   $REPO"
echo "==> Output: $REPO/output"

if command -v docker >/dev/null 2>&1; then
    ENGINE=docker
elif command -v podman >/dev/null 2>&1; then
    ENGINE=podman
    echo "==> docker not on PATH, using podman"
else
    echo "Neither docker nor podman is on PATH. Install one and make sure your" >&2
    echo "user can run it (add to the 'docker' group, or use rootless)." >&2
    exit 127
fi

MOUNT_SUFFIX=""
if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce 2>/dev/null || true)" = "Enforcing" ]; then
    MOUNT_SUFFIX=":z"
    echo "==> SELinux is enforcing, relabelling the bind mount"
fi

echo "==> Building toolchain image ($IMAGE)"
"$ENGINE" build --platform linux/amd64 -t "$IMAGE" "$REPO/docker"

PAC_CACHE=frog-pacman-cache
"$ENGINE" volume create "$PAC_CACHE" >/dev/null

echo "==> Building ISO"
"$ENGINE" run --rm --privileged \
    --platform linux/amd64 \
    --security-opt seccomp=unconfined \
    --security-opt apparmor=unconfined \
    -v "$REPO:/build$MOUNT_SUFFIX" \
    -v "$PAC_CACHE:/var/cache/pacman/pkg" \
    -w /build \
    "$IMAGE" \
    /build/scripts/build-in-container.sh

echo
echo "==> ISO(s) in $REPO/output"
ls -lh "$REPO/output"/*.iso 2>/dev/null || echo "(none, build produced no ISO)"
