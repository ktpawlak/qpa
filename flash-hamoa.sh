#!/bin/bash
# flash-hamoa.sh - Flash Ubuntu image to a Hamoa board
#
# Usage: ./flash-hamoa.sh <image-dir>
#   image-dir: path to release directory containing ubuntu-*.img and
#              rawprogram0.xml / rawprogram0_emmc.xml
#              (e.g. ~/qualcomm/images/26.04/x02)
#
# Must be run from the root of the qrap repository.

set -euo pipefail

REAL_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
ALPACA="${REAL_HOME}/qualcomm/carmel-tools/alpaca.py"
NHLOS=boards/hamoa/nhlos
EDL_USB_ID="05c6:9008"
EDL_TIMEOUT=15  # seconds to wait for EDL device to enumerate

BOARD_IP=192.168.1.123
DEFAULT_PASS=ubuntu
NEW_PASS=changeme12
SSH_TIMEOUT=120  # seconds to wait for SSH after boot

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
command -v expect >/dev/null        || die "expect not found in PATH (install with: apt install expect)"
command -v sshpass >/dev/null       || die "sshpass not found in PATH (install with: apt install sshpass)"
[ -f "$NHLOS/partition_ufs/xbl_s_devprg_ns.melf" ] \
    || die "NHLOS artifacts missing. Run one-time setup first (see SKILLS.md)."

IMG_FILE=$(ls "$IMG"/ubuntu-*.img 2>/dev/null | head -1)
[ -n "$IMG_FILE" ]                  || die "No ubuntu-*.img found in $IMG"
[ -f "$IMG/rawprogram0.xml" ]       || die "rawprogram0.xml not found in $IMG"
[ -f "$IMG/rawprogram0_emmc.xml" ]  || die "rawprogram0_emmc.xml not found in $IMG"

echo "=== Flash Hamoa ==="
echo "Image:  $IMG_FILE"
echo ""

# --- copy image and XML files into NHLOS dir ---------------------------------

echo "--- Copying image and partition files ---"
cp "$IMG_FILE"                "$NHLOS"/
cp "$IMG/rawprogram0.xml"     "$NHLOS"/
cp "$IMG/rawprogram0_emmc.xml" "$NHLOS"/

# --- flash Ubuntu OS image ---------------------------------------------------

echo ""
echo "--- Flashing Ubuntu OS image ---"
enter_edl

(cd "$NHLOS" && sudo qdl --storage ufs \
    partition_ufs/xbl_s_devprg_ns.melf \
    rawprogram0.xml)

echo "Flash complete."

# --- power cycle -------------------------------------------------------------

echo ""
echo "--- Power cycling for clean boot ---"
sudo "$ALPACA" off
sleep 2
sudo "$ALPACA" on

# --- wait for SSH and change default password --------------------------------

echo ""
echo "--- Waiting for SSH on ${BOARD_IP} (${SSH_TIMEOUT}s) ---"
ssh_ready=0
for i in $(seq 1 $SSH_TIMEOUT); do
    if nc -z -w1 "$BOARD_IP" 22 2>/dev/null; then
        ssh_ready=1
        break
    fi
    sleep 1
done
[ "$ssh_ready" -eq 1 ] || die "SSH on ${BOARD_IP} did not become available after ${SSH_TIMEOUT}s."

echo "SSH port open."

# Try new password first (re-flash case: password already set)
if sshpass -p "$NEW_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        ubuntu@"$BOARD_IP" true 2>/dev/null; then
    echo "Password already set to '${NEW_PASS}'. Skipping password change."
else
    echo "Changing default password..."
    expect -c "
        spawn ssh -o StrictHostKeyChecking=no ubuntu@${BOARD_IP}
        expect \"password:\"
        send \"${DEFAULT_PASS}\r\"
        expect {
            \"Current password:\" { send \"${DEFAULT_PASS}\r\"; exp_continue }
            \"New password:\"     { send \"${NEW_PASS}\r\";     exp_continue }
            \"Retype new\"        { send \"${NEW_PASS}\r\";     exp_continue }
            eof                  {}
        }
    " || die "Failed to change password on ${BOARD_IP}."
    echo "Password changed to '${NEW_PASS}'."
fi

echo ""
echo "=== Flashing complete ==="
