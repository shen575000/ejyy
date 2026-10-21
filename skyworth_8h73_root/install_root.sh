#!/usr/bin/env bash
# install_root.sh - one-time root tooling installer for Skyworth 8H73 / E6000
#
# Prerequisite: boot_root.img has been flashed to the "kernel" partition and the TV booted.
# adbd runs as root on this image; if the TV is on the LAN, pass its IP:
#   ./install_root.sh 192.168.1.50
set -euo pipefail

ADB=${ADB:-adb}
HERE=$(cd "$(dirname "$0")" && pwd)

if [ $# -ge 1 ]; then
    echo "== adb connect $1:5555 =="
    $ADB connect "$1:5555" >/dev/null || true
    sleep 2
fi

echo "== waiting for device =="
$ADB wait-for-device

echo "== checking device and root state =="
MODEL=$($ADB shell getprop ro.build.skymodel | tr -d '\r')
TYPE=$($ADB shell getprop ro.build.skytype | tr -d '\r')
UID=$($ADB shell id -u | tr -d '\r')
echo "model=$MODEL type=$TYPE uid=$UID"
[ "$MODEL" = "8H73" ] || { echo "unexpected model, abort"; exit 1; }
[ "$UID" = "0" ] || { echo "adbd is not root; boot_root.img is not active, abort"; exit 1; }

echo "== remount /system rw =="
$ADB shell 'mount -o rw,remount /system 2>/dev/null || true'

echo "== install skyupd =="
$ADB push "$HERE/skyupd.sh" /data/local/tmp/skyupd >/dev/null
$ADB shell 'cp /data/local/tmp/skyupd /system/bin/skyupd && chown 0:2000 /system/bin/skyupd && chmod 0755 /system/bin/skyupd && rm -f /data/local/tmp/skyupd'

echo "== busybox + compatibility tools =="
$ADB shell 'chown 0:2000 /system/bin/busybox; chmod 0755 /system/bin/busybox'
APPLETS="vi wget tar unzip telnetd nc find xargs less more top ps grep egrep fgrep sed awk dd cp mv rm mkdir rmdir ln chmod chown sleep sync mount umount sha256sum sha1sum md5sum gzip gunzip zcat bzip2 bunzip2 hexdump od httpd crond crontab ifconfig route ping netstat ip arp nslookup traceroute cut sort uniq head tail wc tr diff patch du df free uptime whoami id env kill killall pgrep pkill nohup timeout watch expr seq printf tee touch date hostname uname strings lzop unlzma dos2unix unix2dos stat readlink realpath mktemp sh ash hush"
$ADB shell "for a in $APPLETS; do ln -sf /system/bin/busybox /system/xbin/\$a; done"

echo "== install su wrapper =="
$ADB push "$HERE/su.sh" /data/local/tmp/su >/dev/null
$ADB shell 'cp /data/local/tmp/su /system/xbin/su && chown 0:2000 /system/xbin/su && chmod 0755 /system/xbin/su && rm -f /data/local/tmp/su'

echo "== verify =="
$ADB shell 'ls -l /system/bin/skyupd /system/xbin/su; /system/bin/busybox sha256sum /system/bin/skyupd; /system/xbin/vi --help 2>&1 | head -n 2'

echo "== sync =="
$ADB shell 'sync'

cat <<'TIP'
done.
  root shell : adb shell            (uid 0, over TCP 5555 or USB adb)
  UART shell : root console on ttyAMA0, 115200 8N1
  USB update : put the skyupd/ folder at the root of a USB drive, then reboot
  USB adb    : setprop sys.usb.config adb   (switches the port to device mode)
TIP
