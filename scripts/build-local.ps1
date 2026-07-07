# Frog Linux — local ISO build in Docker
# Uses named volumes so pacman package cache and gnupg keyring persist across runs.
# First run: cold pacman fetch (slow). Subsequent runs: near-instant deps, ISO in ~1-2 min.
#
# Requires Docker Desktop (WSL2 backend, privileged containers enabled).
# Usage:  .\scripts\build-local.ps1

$ErrorActionPreference = 'Stop'

# Resolve repo root (this script lives in scripts/)
$repo = Split-Path -Parent $PSScriptRoot
Write-Host "==> Repo:   $repo"
Write-Host "==> Output: $repo\output"

# Sanity check
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "docker not on PATH. Install Docker Desktop and enable WSL2."
}

# Persistent volumes for pacman package cache and pacman-key GnuPG state.
# These survive across container runs and repo rebuilds.
# `docker volume create` is idempotent — safe to call every run.
$pacCache = 'frog-pacman-cache'
$pacGnupg = 'frog-pacman-gnupg'
docker volume create $pacCache 2>&1 | Out-Null
docker volume create $pacGnupg 2>&1 | Out-Null

# Force linux/amd64 — Arch only publishes x86_64 images, and Docker on
# Windows-on-ARM (or with a mismatched default platform) will otherwise try
# to pull an arm64 manifest and fail.
docker run --rm --privileged `
    --platform linux/amd64 `
    --security-opt seccomp=unconfined `
    --security-opt apparmor=unconfined `
    -v "${repo}:/build" `
    -v "${pacCache}:/var/cache/pacman/pkg" `
    -v "${pacGnupg}:/etc/pacman.d/gnupg" `
    -w /build `
    archlinux:latest `
    bash /build/scripts/build-in-container.sh

if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "==> ISO(s) in $repo\output"
Get-ChildItem "$repo\output\*.iso" | Format-Table Name, Length, LastWriteTime
