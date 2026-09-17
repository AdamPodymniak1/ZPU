#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# setup_toolchain.sh
#
# Installs the full open-source FPGA toolchain needed for the Tang Nano 20K
# inside WSL2 (Ubuntu), using the prebuilt "oss-cad-suite" bundle from
# YosysHQ. This single bundle ships matching, tested versions of:
#   - yosys            (synthesis)
#   - nextpnr-himbaechel (place & route, Gowin backend)
#   - gowin_pack        (bitstream packing, via project Apicula)
#   - openFPGALoader    (flashing/programming)
#   - iverilog + gtkwave (simulation, optional but handy for "testing")
#
# Building these individually from source is possible but unnecessary and
# much slower/flakier than using the prebuilt releases, so that's what this
# script does.
# ---------------------------------------------------------------------------
set -euo pipefail

INSTALL_DIR="${HOME}/oss-cad-suite"
TMP_TAR="/tmp/oss-cad-suite.tgz"

echo "==> Installing base dependencies"
sudo apt-get update
sudo apt-get install -y \
    curl jq tar xz-utils \
    libusb-1.0-0 libftdi1-2 \
    make git

echo "==> Fetching latest oss-cad-suite release info"
LATEST_JSON=$(curl -s https://api.github.com/repos/YosysHQ/oss-cad-suite-build/releases/latest)
ASSET_URL=$(echo "$LATEST_JSON" | jq -r '.assets[] | select(.name | test("linux-x64.*\\.tgz$")) | .browser_download_url')
ASSET_NAME=$(echo "$LATEST_JSON" | jq -r '.assets[] | select(.name | test("linux-x64.*\\.tgz$")) | .name')

if [ -z "$ASSET_URL" ] || [ "$ASSET_URL" = "null" ]; then
    echo "Could not resolve latest oss-cad-suite linux-x64 asset URL."
    echo "Go to https://github.com/YosysHQ/oss-cad-suite-build/releases"
    echo "and download the linux-x64 .tgz manually, then re-run with:"
    echo "  ASSET_URL=<url> $0"
    exit 1
fi

echo "==> Downloading ${ASSET_NAME}"
curl -L -o "$TMP_TAR" "$ASSET_URL"

echo "==> Extracting to ${INSTALL_DIR}"
rm -rf "${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"
tar -xzf "$TMP_TAR" -C "$(dirname "${INSTALL_DIR}")"
# archive extracts to a folder named "oss-cad-suite"; make sure it lands where we want
if [ -d "$(dirname "${INSTALL_DIR}")/oss-cad-suite" ] && [ "$(dirname "${INSTALL_DIR}")/oss-cad-suite" != "${INSTALL_DIR}" ]; then
    rm -rf "${INSTALL_DIR}"
    mv "$(dirname "${INSTALL_DIR}")/oss-cad-suite" "${INSTALL_DIR}"
fi
rm -f "$TMP_TAR"

echo "==> Adding environment sourcing to ~/.bashrc"
SOURCE_LINE="source \"${INSTALL_DIR}/environment\""
if ! grep -qxF "$SOURCE_LINE" "${HOME}/.bashrc" 2>/dev/null; then
    echo "" >> "${HOME}/.bashrc"
    echo "# Tang Nano 20K / oss-cad-suite toolchain" >> "${HOME}/.bashrc"
    echo "$SOURCE_LINE" >> "${HOME}/.bashrc"
fi

echo "==> Installing openFPGALoader udev rules (used if WSL udev is active)"
source "${INSTALL_DIR}/environment"
UDEV_SRC=$(find "${INSTALL_DIR}" -iname "*openfpgaloader*rules" 2>/dev/null | head -n1 || true)
if [ -n "${UDEV_SRC}" ]; then
    sudo cp "${UDEV_SRC}" /etc/udev/rules.d/99-openfpgaloader.rules
fi

# Belt-and-suspenders: also write our own rule specifically for the FT2232
# JTAG/UART cable used on Tang Nano boards (VID:PID 0403:6010), which both
# grants access AND stops ftdi_sio from claiming it as a serial port.
# This only takes effect if a udev daemon is actually running, which on
# WSL2 requires systemd to be enabled (see README.md) -- most WSL2 setups
# don't have this by default, which is why the Makefile's `fix-usb` target
# also handles this at flash-time regardless, as a fallback that always works.
sudo tee /etc/udev/rules.d/99-tangnano-jtag.rules >/dev/null <<'EOF'
# Tang Nano FT2232-based JTAG/UART cable: grant access and prevent ftdi_sio
# from claiming it as a serial port (which blocks openFPGALoader/libftdi).
SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="6010", MODE="0666"
SUBSYSTEM=="usb-serial", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6010", ATTR{port_number}=="*", RUN+="/bin/sh -c 'echo -n $kernel > /sys/bus/usb/drivers/ftdi_sio/unbind 2>/dev/null || true'"
EOF

sudo udevadm control --reload-rules 2>/dev/null || true
sudo udevadm trigger 2>/dev/null || true

if ! pgrep -x udevd >/dev/null 2>&1 && ! pgrep -x systemd-udevd >/dev/null 2>&1; then
    echo "  Note: no udev daemon appears to be running in this WSL2 instance,"
    echo "  so the rules above won't apply automatically yet. That's fine --"
    echo "  the Makefile's 'fix-usb' target (run automatically by 'make flash')"
    echo "  handles the same problem without needing udev. If you want the"
    echo "  udev rules to work properly instead, enable systemd in WSL2:"
    echo "  add 'systemd=true' under [boot] in /etc/wsl.conf, then run"
    echo "  'wsl --shutdown' from PowerShell and reopen your terminal."
fi

echo ""
echo "==> Verifying tools"
source "${INSTALL_DIR}/environment"
for tool in yosys nextpnr-himbaechel gowin_pack openFPGALoader iverilog; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "  [OK] $tool -> $(command -v "$tool")"
    else
        echo "  [MISSING] $tool"
    fi
done

echo ""
echo "Done. Open a new shell (or 'source ~/.bashrc') so the toolchain is on PATH."
echo "Next: set up USB passthrough from Windows -> WSL2 (see README.md),"
echo "then use the provided Makefile to build/flash a project."
