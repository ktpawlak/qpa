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

BOARD_IP=192.168.1.185
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

# After a reflash the board regenerates its SSH host keys, so any cached entry
# in known_hosts will no longer match. StrictHostKeyChecking=no only auto-accepts
# brand-new keys, NOT changed ones, so a stale entry makes ssh refuse to connect
# and the password change silently fails. Drop any stale entry and never persist
# the new one.
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10)
ssh-keygen -R "$BOARD_IP" >/dev/null 2>&1 || true

# Try new password first (re-flash case: password already set)
if sshpass -p "$NEW_PASS" ssh "${SSH_OPTS[@]}" \
        ubuntu@"$BOARD_IP" true 2>/dev/null; then
    echo "Password already set to '${NEW_PASS}'. Skipping password change."
else
    echo "Changing default password..."
    # The board often accepts SSH connections before multi-user boot completes.
    # During that window pam_nologin refuses unprivileged logins with
    # "System is booting up. Unprivileged users are not permitted to log in yet"
    # and closes the session, which would otherwise look like a silent stall.
    # Retry (exit code 8) until the system finishes booting.
    NOLOGIN_RETRIES=30
    NOLOGIN_WAIT=10
    pw_changed=0
    for attempt in $(seq 1 $NOLOGIN_RETRIES); do
        set +e
        expect <<EXPECT_EOF
            set timeout 60
            spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 ubuntu@${BOARD_IP}
            # Initial login password prompt
            expect {
                -re {not permitted to log in yet} { puts "\nEXPECT: system still booting (pam_nologin)"; exit 8 }
                -re {[Pp]assword:} { send "${DEFAULT_PASS}\r" }
                timeout { puts "\nEXPECT: timed out waiting for login password prompt"; exit 2 }
                eof     { puts "\nEXPECT: connection closed before login prompt"; exit 3 }
            }
            # Forced password-change dialog (order-independent, loops via exp_continue)
            expect {
                -re {not permitted to log in yet} { puts "\nEXPECT: system still booting (pam_nologin)"; exit 8 }
                -re {[Cc]urrent.*password:}      { send "${DEFAULT_PASS}\r"; exp_continue }
                -re {Retype new password:}       { send "${NEW_PASS}\r";     exp_continue }
                -re {[Nn]ew password:}           { send "${NEW_PASS}\r";     exp_continue }
                -re {updated successfully}       { puts "\nEXPECT: password updated"; exit 0 }
                -re {password unchanged}         { puts "\nEXPECT: password unchanged"; exit 4 }
                -re {Authentication token manipulation error} { puts "\nEXPECT: passwd token error"; exit 5 }
                -re {BAD PASSWORD}               { puts "\nEXPECT: new password rejected as weak"; exit 6 }
                -re {Permission denied}          { puts "\nEXPECT: authentication failed"; exit 7 }
                timeout { puts "\nEXPECT: timed out during password change"; exit 2 }
                eof     { exit 0 }
            }
EXPECT_EOF
        rc=$?
        set -e
        if [ "$rc" -eq 8 ]; then
            echo "System still booting (pam_nologin); retrying in ${NOLOGIN_WAIT}s... (attempt ${attempt}/${NOLOGIN_RETRIES})"
            sleep "$NOLOGIN_WAIT"
            continue
        fi
        [ "$rc" -eq 0 ] || die "Failed to change password on ${BOARD_IP} (expect exit ${rc})."
        pw_changed=1
        break
    done
    [ "$pw_changed" -eq 1 ] \
        || die "System on ${BOARD_IP} never finished booting (pam_nologin still active after $((NOLOGIN_RETRIES * NOLOGIN_WAIT))s)."
    echo "Password change dialog completed."

    # Verify the new password actually works before declaring success.
    echo "Verifying new password..."
    verified=0
    for i in $(seq 1 30); do
        if sshpass -p "$NEW_PASS" ssh "${SSH_OPTS[@]}" \
                ubuntu@"$BOARD_IP" true 2>/dev/null; then
            verified=1
            break
        fi
        sleep 2
    done
    [ "$verified" -eq 1 ] || die "Password change did not take effect on ${BOARD_IP}."
    echo "Password changed to '${NEW_PASS}'."
fi

echo ""
echo "=== Flashing complete ==="
