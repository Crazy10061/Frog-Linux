#!/usr/bin/env bash
set -euo pipefail

strip_ansi() {
    sed $'s/\033\\[[0-9;]*m//g'
}

# shellcheck disable=SC2317
cleanup() {
    if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
        kill "$QEMU_PID"
        wait "$QEMU_PID" 2>/dev/null || true
    fi
    chmod -R u+w "$SMOKE_DIR" 2>/dev/null || true
    rm -rf -- "$SMOKE_DIR"
}

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 0
fi

ISO_PATH="${1:-}"
if [ -z "$ISO_PATH" ] || [ ! -f "$ISO_PATH" ]; then
    echo "Usage: $0 /path/to/frog.iso" >&2
    exit 2
fi

SMOKE_DIR="$(mktemp -d)"
QEMU_PID=""

trap cleanup EXIT

BOOT_REPORT="$(xorriso -indev "$ISO_PATH" -report_el_torito plain 2>&1)"
grep -q 'BIOS' <<< "$BOOT_REPORT"
grep -q 'UEFI' <<< "$BOOT_REPORT"

xorriso -osirrox on -indev "$ISO_PATH" \
    -extract /arch/boot/x86_64/vmlinuz-linux-cachyos "$SMOKE_DIR/vmlinuz" \
    -extract /arch/boot/x86_64/initramfs-linux-cachyos.img "$SMOKE_DIR/initramfs.img" \
    -extract /boot "$SMOKE_DIR/iso-boot" >/dev/null 2>&1

shopt -s nullglob
UUID_FILES=("$SMOKE_DIR"/iso-boot/*.uuid)
if [ "${#UUID_FILES[@]}" -ne 1 ]; then
    echo "ERROR: expected one Archiso UUID marker, found ${#UUID_FILES[@]}." >&2
    exit 1
fi
ISO_UUID="$(basename "${UUID_FILES[0]}" .uuid)"
SERIAL_LOG="$SMOKE_DIR/serial.log"
NORMALIZED_SERIAL_LOG="$SMOKE_DIR/serial-plain.log"
QEMU_LOG="$SMOKE_DIR/qemu.log"

qemu-system-x86_64 \
    -machine q35,accel=tcg \
    -cpu max \
    -smp 2 \
    -m 4096 \
    -kernel "$SMOKE_DIR/vmlinuz" \
    -initrd "$SMOKE_DIR/initramfs.img" \
    -append "archisobasedir=arch archisosearchuuid=$ISO_UUID console=tty0 console=ttyS0,115200n8 systemd.show_status=1 rd.systemd.show_status=1 systemd.unit=graphical.target" \
    -drive "file=$ISO_PATH,format=raw,media=cdrom,readonly=on" \
    -display none \
    -serial "file:$SERIAL_LOG" \
    -monitor none \
    -no-reboot >"$QEMU_LOG" 2>&1 &
QEMU_PID=$!

DEADLINE=$((SECONDS + 480))
while [ "$SECONDS" -lt "$DEADLINE" ]; do
    if [ -f "$SERIAL_LOG" ]; then
        strip_ansi < "$SERIAL_LOG" > "$NORMALIZED_SERIAL_LOG"
    fi

    if grep -q 'Started Simple Desktop Display Manager' "$NORMALIZED_SERIAL_LOG" 2>/dev/null; then
        echo "Live ISO reached SDDM."
        exit 0
    fi

    if grep -Eq 'Kernel panic|Entering emergency mode' "$NORMALIZED_SERIAL_LOG" 2>/dev/null; then
        echo "ERROR: live ISO entered a fatal boot state." >&2
        tail -n 100 "$SERIAL_LOG" >&2
        exit 1
    fi

    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
        wait "$QEMU_PID" || true
        echo "ERROR: QEMU exited before SDDM started." >&2
        tail -n 100 "$SERIAL_LOG" >&2 || true
        tail -n 100 "$QEMU_LOG" >&2 || true
        exit 1
    fi

    sleep 2
done

echo "ERROR: live ISO did not reach SDDM within 480 seconds." >&2
tail -n 100 "$SERIAL_LOG" >&2 || true
exit 1
