#!/system/bin/sh
# su wrapper: only works when already root (adbd root / UART console).
if [ "$(id -u)" = "0" ]; then
    exec /system/bin/sh "$@"
fi
echo "su: not available for app UID $(id -u); use adb shell (root) or the UART console"
exit 1
