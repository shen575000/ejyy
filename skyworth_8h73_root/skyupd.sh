#!/system/bin/sh
# skyupd - Skyworth 8H73 root-side USB updater
# Runs as root from init (on property:sys.boot_completed=1), oneshot.
# Package layout on the USB drive:
#   <usb>/skyupd/manifest.txt
#   <usb>/skyupd/<image or tar.gz files>
# manifest.txt:
#   platform=Hi3751V500
#   model=8H73
#   type=E6000
#   sha256 <file> <64-hex>
#   flash <partition> <file>
#   copy <mountpoint> <file>
#   reboot=1

LOG=/cache/skyupd.log
BYNAME=/dev/block/platform/hi_mci.1/by-name
PKGNAME=skyupd
BB=/system/bin/busybox

mkdir -p /cache 2>/dev/null
exec >>"$LOG" 2>&1
echo "==== $(date) skyupd start ===="

if [ ! -x "$BB" ]; then
    echo "FATAL: $BB is not executable"
    exit 1
fi
BB="$BB"

MODEL=$(getprop ro.product.model)
DEVICE=$(getprop ro.product.device)
echo "device: model=$MODEL device=$DEVICE"

find_pkg() {
    for m in /mnt/usb /mnt/usbhost /mnt/usb0 /mnt/usb1 /mnt/udisk \
             /storage/usb0 /storage/usb1 /storage/usbdisk0 \
             /mnt/media_rw/usb0 /mnt/sda1 /mnt/sdb1; do
        [ -d "$m/$PKGNAME" ] && { echo "$m/$PKGNAME"; return 0; }
        # vold mounts removable media one level below the mount root
        # (e.g. /mnt/usb/sda1, /mnt/usb/USBDRIVE)
        for d in "$m"/*; do
            [ -d "$d/$PKGNAME" ] && { echo "$d/$PKGNAME"; return 0; }
        done
    done
    return 1
}

PKG=""
i=0
while [ $i -lt 20 ]; do
    PKG=$(find_pkg) && break
    PKG=""
    $BB sleep 2
    i=$((i + 1))
done
if [ -z "$PKG" ]; then
    echo "no USB package found, nothing to do"
    exit 0
fi
echo "package: $PKG"

MAN="$PKG/manifest.txt"
if [ ! -f "$MAN" ]; then
    echo "FATAL: manifest.txt missing"
    exit 1
fi

MH=$($BB sha256sum "$MAN" | $BB cut -d' ' -f1)
if [ -f /cache/skyupd.applied ]; then
    if [ "$(cat /cache/skyupd.applied)" = "$MH" ]; then
        echo "package $MH already applied, skip"
        exit 0
    fi
fi

# ---------- pass 1: model + hash validation ----------
REBOOT=0
while IFS= read -r line; do
    case "$line" in
        ''|\#*) continue ;;
        model=*) m=${line#model=}
                 case "$MODEL" in
                     *"$m"*) ;;
                     *) echo "FATAL: model mismatch ($m not in $MODEL)"; exit 2 ;;
                 esac ;;
        platform=*) p=${line#platform=}
                 if [ "$p" != "$DEVICE" ]; then echo "FATAL: platform mismatch ($p != $DEVICE)"; exit 2; fi ;;
        type=*)  echo "tag: type=${line#type=}" ;;
        reboot=*) REBOOT=${line#reboot=} ;;
        sha256\ *)
                 set -- $line
                 f=$2; h=$3
                 if [ ! -f "$PKG/$f" ]; then echo "FATAL: missing $f"; exit 2; fi
                 a=$($BB sha256sum "$PKG/$f" | $BB cut -d' ' -f1)
                 if [ "$a" != "$h" ]; then echo "FATAL: hash mismatch $f"; echo "  want $h"; echo "  got  $a"; exit 2; fi
                 echo "hash ok: $f ($a)" ;;
    esac
done < "$MAN"

# ---------- pass 2: apply ----------
while IFS= read -r line; do
    case "$line" in
        ''|\#*) continue ;;
        flash\ *)
            set -- $line
            PART=$2; FILE=$3
            case "$PART" in
                kernel|recovery|system|skydir|skyota|logo|atv|bootargs|baseparam|panelparam) ;;
                *) echo "skip: partition '$PART' not allowed"; continue ;;
            esac
            [ -f "$PKG/$FILE" ] || { echo "skip: $FILE missing"; continue; }
            echo "flash $PART <- $FILE"
            if ! $BB dd if="$PKG/$FILE" of="$BYNAME/$PART" bs=1048576; then
                echo "FATAL: dd failed for $PART"; exit 3
            fi
            ;;
        copy\ *)
            set -- $line
            DEST=$2; FILE=$3
            [ -f "$PKG/$FILE" ] || { echo "skip: $FILE missing"; continue; }
            case "$DEST" in
                /system) mount -o rw,remount /system 2>/dev/null ;;
            esac
            echo "copy $FILE -> $DEST"
            if ! $BB tar -C "$DEST" -xzf "$PKG/$FILE"; then
                echo "FATAL: extract failed for $FILE"; exit 4
            fi
            ;;
    esac
done < "$MAN"

$BB sync
echo "$MH" > /cache/skyupd.applied
chmod 0644 /cache/skyupd.applied
echo "apply done at $(date)"

if [ "$REBOOT" = "1" ]; then
    echo "rebooting"
    setprop sys.powerctl reboot
fi
exit 0
