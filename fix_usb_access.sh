#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# fix_usb_access.sh
#
# On WSL2, two things commonly block openFPGALoader from reaching an
# FT2232-based JTAG cable (like the one on Tang Nano boards), even after
# `usbipd attach` succeeds:
#
#   1. Linux's own ftdi_sio driver auto-claims both FT2232 interfaces as
#      /dev/ttyUSB0 / /dev/ttyUSB1, blocking libftdi from opening the
#      device directly.
#   2. WSL2 usually doesn't run a live udev daemon (unless systemd is
#      explicitly enabled), so the /dev/bus/usb/* device node never gets
#      the permissions a udev rule would normally set, leaving it
#      accessible to root only.
#
# This script finds the cable by VID:PID (robust against bus/device
# numbers changing between replugs), fixes both issues, and is silent/
# no-op if there's nothing to fix. It's called automatically by the
# Makefile's flash targets, so normal usage shouldn't need this directly.
#
# Usage:
#   ./fix_usb_access.sh                  # uses default VID:PID (0403:6010)
#   ./fix_usb_access.sh 0403 6010        # explicit VID PID
#   CABLE_VID=0403 CABLE_PID=6010 ./fix_usb_access.sh
# ---------------------------------------------------------------------------
set -uo pipefail

VID="${1:-${CABLE_VID:-0403}}"
PID="${2:-${CABLE_PID:-6010}}"

MATCH=""
for devpath in /sys/bus/usb/devices/*; do
    [ -f "$devpath/idVendor" ] || continue
    [ -f "$devpath/idProduct" ] || continue
    v=$(cat "$devpath/idVendor" 2>/dev/null || echo "")
    p=$(cat "$devpath/idProduct" 2>/dev/null || echo "")
    if [ "$v" = "$VID" ] && [ "$p" = "$PID" ]; then
        MATCH="$devpath"
        break
    fi
done

if [ -z "$MATCH" ]; then
    echo "fix_usb_access.sh: no USB device ${VID}:${PID} found under /sys/bus/usb/devices."
    echo "  Is the board plugged in and 'usbipd attach'ed? Check with 'lsusb'."
    exit 1
fi

KERNEL_ID=$(basename "$MATCH")
echo "fix_usb_access.sh: found ${VID}:${PID} at ${KERNEL_ID}"

# --- 1. Unbind ftdi_sio from any interfaces of this device -----------------
if [ -d /sys/bus/usb/drivers/ftdi_sio ]; then
    for iface in /sys/bus/usb/drivers/ftdi_sio/"${KERNEL_ID}":*; do
        [ -e "$iface" ] || continue
        ifname=$(basename "$iface")
        echo "fix_usb_access.sh: unbinding ${ifname} from ftdi_sio"
        echo -n "$ifname" | sudo tee /sys/bus/usb/drivers/ftdi_sio/unbind >/dev/null 2>&1 || \
            echo "  (unbind failed or already unbound, continuing)"
    done
fi

# --- 2. Grant access to the /dev/bus/usb device node -----------------------
if [ -f "$MATCH/busnum" ] && [ -f "$MATCH/devnum" ]; then
    BUSNUM=$(printf "%03d" "$(cat "$MATCH/busnum")")
    DEVNUM=$(printf "%03d" "$(cat "$MATCH/devnum")")
    DEVNODE="/dev/bus/usb/${BUSNUM}/${DEVNUM}"
    if [ -e "$DEVNODE" ]; then
        echo "fix_usb_access.sh: granting access to ${DEVNODE}"
        sudo chmod 666 "$DEVNODE"
    else
        echo "fix_usb_access.sh: warning - expected device node ${DEVNODE} not found"
    fi
fi

echo "fix_usb_access.sh: done."
