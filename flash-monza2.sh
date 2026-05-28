#!/bin/bash
# flash-monza2.sh - Flash Ubuntu image to a Monza2 board
#
# Usage: ./flash-monza2.sh <image-dir>
#   image-dir: path to release directory containing ubuntu-*.img, dtb.bin,
#              and rawprogram0_emmc.xml (e.g. ~/qualcomm/images/24.04/x11)
#
# Must be run from the root of the qrap repository.

set -euo pipefail

REAL_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
ALPACA="${REAL_HOME}/qualcomm/carmel-tools/alpaca.py"
NHLOS=boards/monza2/nhlos
EDL_USB_ID="05c6:9008"
EDL_TIMEOUT=15  # seconds to wait for EDL device to enumerate

# --- helpers -----------------------------------------------------------------

die() { echo "ERROR: $*" >&2; exit 1; }

wait_for_edl() {
    echo "Waiting for EDL device (${EDL_TIMEOUT}s)..."
    for i in $(seq 1 $EDL_TIMEOUT); do
        if lsusb 2>/dev/null | grep -q "$EDL_USB_ID"; then
            echo "EDL device found."
            return 0
        fi
        sleep 1
    done
    die "EDL device (${EDL_USB_ID}) did not appear after ${EDL_TIMEOUT}s."
}

enter_edl() {
    echo "Power cycling into EDL mode..."
    sudo "$ALPACA" off
    sleep 2
    sudo "$ALPACA" edl
    sleep 2
    wait_for_edl
}

# --- preflight checks --------------------------------------------------------

[ $# -eq 1 ] || die "Usage: $0 <image-dir>"
IMG=$(realpath "$1")

[ -d "$IMG" ]                       || die "Image directory not found: $IMG"
[ -f "$ALPACA" ]                    || die "alpaca.py not found: $ALPACA"
command -v qdl >/dev/null           || die "qdl not found in PATH"
[ -f "$NHLOS/prog_firehose_ddr.elf" ] || die "NHLOS artifacts missing. Run one-time setup first (see SKILLS.md)."
[ -d "$NHLOS/cdt_monza" ]           || die "CDT artifacts missing. Run one-time setup first (see SKILLS.md)."

IMG_FILE=$(ls "$IMG"/ubuntu-*.img 2>/dev/null | head -1)
[ -n "$IMG_FILE" ] || die "No ubuntu-*.img found in $IMG"
[ -f "$IMG/dtb.bin" ]               || die "dtb.bin not found in $IMG"
[ -f "$IMG/rawprogram0_emmc.xml" ]  || die "rawprogram0_emmc.xml not found in $IMG"

echo "=== Flash Monza2 ==="
echo "Image:  $IMG_FILE"
echo "Board:  $(basename "$IMG_FILE")"
echo ""

# --- setup image symlinks ----------------------------------------------------

echo "--- Linking image files ---"
ln -sf "$IMG"/ubuntu-*.img "$NHLOS"/
ln -sf "$IMG/dtb.bin"      "$NHLOS"/
cp     "$IMG/rawprogram0_emmc.xml" "$NHLOS/partition_emmc/"

# --- phase 1: CDT boot artifacts ---------------------------------------------

echo ""
echo "--- Phase 1: CDT boot artifacts ---"
enter_edl

(cd "$NHLOS/cdt_monza" && sudo qdl --storage emmc \
    prog_firehose_ddr.elf rawprogram1.xml patch1.xml)

echo "Phase 1 complete."

# --- phase 2: Ubuntu OS image ------------------------------------------------

echo ""
echo "--- Phase 2: Ubuntu OS image ---"
enter_edl

(cd "$NHLOS" && sudo qdl --storage emmc \
    --include=partition_emmc \
    prog_firehose_ddr.elf \
    partition_emmc/rawprogram*.xml \
    partition_emmc/patch*.xml)

echo "Phase 2 complete."

# --- power cycle -------------------------------------------------------------

echo ""
echo "--- Power cycling for clean boot ---"
sudo "$ALPACA" off
sleep 2
sudo "$ALPACA" on

echo ""
echo "=== Flashing complete ==="
