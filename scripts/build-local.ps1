$ErrorActionPreference = 'Stop'

$repo  = Split-Path -Parent $PSScriptRoot
$image = 'frog-linux-build'

Write-Host "==> Repo:   $repo"
Write-Host "==> Output: $repo\output"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "docker not on PATH. Install Docker Desktop and enable WSL2."
}

Write-Host "==> Building toolchain image ($image)"
docker build --platform linux/amd64 -t $image "$repo\docker"
if ($LASTEXITCODE -ne 0) { throw "Toolchain image build failed with exit code $LASTEXITCODE" }

$pacCache = 'frog-pacman-cache'
docker volume create $pacCache 2>&1 | Out-Null

Write-Host "==> Building ISO"
docker run --rm --privileged `
    --platform linux/amd64 `
    --security-opt seccomp=unconfined `
    --security-opt apparmor=unconfined `
    -v "${repo}:/build" `
    -v "${pacCache}:/var/cache/pacman/pkg" `
    -w /build `
    $image `
    /build/scripts/build-in-container.sh

if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "==> ISO(s) in $repo\output"
$isos = Get-ChildItem "$repo\output\*.iso" -ErrorAction SilentlyContinue
if ($isos) { $isos | Format-Table Name, Length, LastWriteTime }
else { Write-Host "(none, build produced no ISO)" }
