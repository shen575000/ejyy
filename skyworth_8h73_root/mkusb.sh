#!/usr/bin/env bash
# mkusb.sh - build a skyupd USB package for Skyworth 8H73 / E6000
#
# usage:
#   ./mkusb.sh <usb_root> [--kernel boot_root.img] [--recovery recovery.img]
#               [--system system_patch.tar.gz] [--reboot 1]
#
# Result: <usb_root>/skyupd/{manifest.txt, copied files}
set -euo pipefail

DEST=${1:?usage: mkusb.sh <usb_root> [--kernel f] [--recovery f] [--system f] [--reboot 1]}
shift || true
KERNEL=""; RECOVERY=""; SYSTEM=""; REBOOT=1
while [ $# -gt 0 ]; do
    case "$1" in
        --kernel) KERNEL=$2; shift 2 ;;
        --recovery) RECOVERY=$2; shift 2 ;;
        --system) SYSTEM=$2; shift 2 ;;
        --reboot) REBOOT=$2; shift 2 ;;
        *) echo "unknown option $1"; exit 1 ;;
    esac
done

PKG="$DEST/skyupd"
rm -rf "$PKG"
mkdir -p "$PKG"

{
    echo "# skyupd manifest - Skyworth 8H73 / E6000"
    echo "platform=Hi3751V500"
    echo "model=8H73"
    echo "type=E6000"
    echo "reboot=$REBOOT"
} > "$PKG/manifest.txt"

add_file() {  # $1=src $2=name
    cp "$1" "$PKG/$2"
}

if [ -n "$KERNEL" ]; then
    add_file "$KERNEL" kernel.img
    echo "sha256 kernel.img $(sha256sum "$PKG/kernel.img" | cut -d' ' -f1)" >> "$PKG/manifest.txt"
    echo "flash kernel kernel.img" >> "$PKG/manifest.txt"
fi
if [ -n "$RECOVERY" ]; then
    add_file "$RECOVERY" recovery.img
    echo "sha256 recovery.img $(sha256sum "$PKG/recovery.img" | cut -d' ' -f1)" >> "$PKG/manifest.txt"
    echo "flash recovery recovery.img" >> "$PKG/manifest.txt"
fi
if [ -n "$SYSTEM" ]; then
    add_file "$SYSTEM" system_patch.tar.gz
    echo "sha256 system_patch.tar.gz $(sha256sum "$PKG/system_patch.tar.gz" | cut -d' ' -f1)" >> "$PKG/manifest.txt"
    echo "copy /system system_patch.tar.gz" >> "$PKG/manifest.txt"
fi

echo "package written to $PKG"
cat "$PKG/manifest.txt"
