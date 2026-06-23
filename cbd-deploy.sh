#!/bin/bash
# cbd-deploy.sh — Push the kernel tree to CBD, wait for the build to complete,
# download the artifacts, and install them on the target board.
#
# Run from the kernel tree root (~/qualcomm/linux).
#
# Usage:
#   ./cbd-deploy.sh [options]
#
# Options:
#   --flavour  qcom|qcom-rt|all   What to build (default: qcom)
#                                   qcom      → -o native              (~200 MB)
#                                   qcom-rt   → -o native -o binary-qcom-rt
#                                   all       → -o native -o binary    (~400 MB)
#   --install  qcom|qcom-rt|all   Which debs to install (default: matches --flavour)
#   --board    HOST                SSH target (default: ubuntu@192.168.1.123)
#   --password PASS                SSH password (default: changeme12)
#   --no-reboot                    Skip the final reboot
#   --no-push                      Skip git push (use existing build ID with --build-id)
#   --build-id ID                  Use this existing build ID instead of pushing
#   --poll-interval N              Seconds between status polls (default: 60)
#   --timeout N                    Max seconds to wait for build (default: 7200 = 2h)
#
# Examples:
#   ./cbd-deploy.sh                          # build qcom, install on default board
#   ./cbd-deploy.sh --flavour qcom-rt        # build and install RT kernel
#   ./cbd-deploy.sh --flavour all --install qcom-rt   # build all, install only RT
#   ./cbd-deploy.sh --no-push --build-id kpawlak-resolute-abc123-1234  # re-use build

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
FLAVOUR="qcom"
INSTALL=""
BOARD="ubuntu@192.168.1.123"
BOARD_PASS="changeme12"
DO_REBOOT=1
DO_PUSH=1
BUILD_ID=""
POLL_INTERVAL=60
TIMEOUT=7200
KERNEL_DIR="$(pwd)"

# ── Helpers ───────────────────────────────────────────────────────────────────
die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "[$(date '+%H:%M:%S')] $*"; }

ssh_board() {
    sshpass -p "$BOARD_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=15 \
        "$BOARD" "$@"
}

scp_board() {
    sshpass -p "$BOARD_PASS" scp \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$@"
}

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --flavour)    FLAVOUR="$2";        shift 2 ;;
        --install)    INSTALL="$2";        shift 2 ;;
        --board)      BOARD="$2";          shift 2 ;;
        --password)   BOARD_PASS="$2";     shift 2 ;;
        --no-reboot)  DO_REBOOT=0;         shift   ;;
        --no-push)    DO_PUSH=0;           shift   ;;
        --build-id)   BUILD_ID="$2"; DO_PUSH=0; shift 2 ;;
        --poll-interval) POLL_INTERVAL="$2"; shift 2 ;;
        --timeout)    TIMEOUT="$2";        shift 2 ;;
        -h|--help)    sed -n '2,40p' "$0"; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
done

# Default install flavour matches build flavour
[ -z "$INSTALL" ] && INSTALL="$FLAVOUR"

# Validate flavour
case "$FLAVOUR" in
    qcom|qcom-rt|all) ;;
    *) die "--flavour must be one of: qcom qcom-rt all" ;;
esac
case "$INSTALL" in
    qcom|qcom-rt|all) ;;
    *) die "--install must be one of: qcom qcom-rt all" ;;
esac

# ── Pre-flight checks ─────────────────────────────────────────────────────────
command -v sshpass >/dev/null || die "sshpass not found (apt install sshpass)"
[ -d "$KERNEL_DIR/.git" ] || die "Not a git repository: $KERNEL_DIR"
[ -n "$(git -C "$KERNEL_DIR" remote get-url cbd 2>/dev/null)" ] || \
    die "'cbd' git remote not configured"

# ── Step 1: Push to CBD ───────────────────────────────────────────────────────
if [ "$DO_PUSH" -eq 1 ]; then
    SHA=$(git -C "$KERNEL_DIR" rev-parse --short=12 HEAD)
    info "Pushing to CBD (HEAD: $SHA, flavour: $FLAVOUR)..."

    case "$FLAVOUR" in
        qcom)    PUSH_OPTS="-o native" ;;
        qcom-rt) PUSH_OPTS="-o native -o binary-qcom-rt" ;;
        all)     PUSH_OPTS="-o native -o binary" ;;
    esac

    git -C "$KERNEL_DIR" push cbd $PUSH_OPTS 2>&1 | tail -6

    # Find the new build job (SHA may appear in multiple jobs; take newest)
    info "Locating build job for $SHA..."
    sleep 5
    BUILD_ID=$(ssh cbd.kernel ls 2>/dev/null \
        | grep "kpawlak-resolute-${SHA}" \
        | grep -v "receipt\|build\.log\|\.deb" \
        | awk '{print $NF}' | sed 's|/arm64/.*||' | sort -u | tail -1)
    [ -n "$BUILD_ID" ] || die "Could not find build job for $SHA on CBD"
    info "Build job: $BUILD_ID/arm64"
fi

[ -n "$BUILD_ID" ] || die "No build ID (use --build-id or run with git push)"

# ── Step 2: Poll until BUILD-OK or BUILD-FAILED ───────────────────────────────
info "Polling build status (interval: ${POLL_INTERVAL}s, timeout: ${TIMEOUT}s)..."
elapsed=0
while true; do
    STATUS=$(ssh cbd.kernel ls "${BUILD_ID}/arm64" 2>/dev/null \
        | grep -oE "BUILD-OK|BUILD-FAILED|BUILDING|QUEUED" | head -1)
    info "${BUILD_ID}/arm64: ${STATUS:-unknown}"

    case "$STATUS" in
        BUILD-OK)     break ;;
        BUILD-FAILED)
            info "Downloading build log..."
            ssh cbd log "${BUILD_ID}/arm64" > /tmp/cbd_build_fail.log 2>&1 || true
            tail -30 /tmp/cbd_build_fail.log
            die "Build FAILED. Full log: /tmp/cbd_build_fail.log"
            ;;
    esac

    [ "$elapsed" -ge "$TIMEOUT" ] && die "Build timed out after ${TIMEOUT}s"
    sleep "$POLL_INTERVAL"
    elapsed=$(( elapsed + POLL_INTERVAL ))
done
info "Build complete: BUILD-OK"

# ── Step 3: Download tarball ──────────────────────────────────────────────────
TARBALL="$(mktemp /tmp/cbd_kernel_XXXXXX.tgz)"
info "Downloading artifacts → $TARBALL ..."
ssh cbd tarball "${BUILD_ID}/arm64" > "$TARBALL"
TARBALL_SIZE=$(du -sh "$TARBALL" | cut -f1)
info "Downloaded: $TARBALL_SIZE"

# ── Step 4: SCP to board ──────────────────────────────────────────────────────
info "Copying tarball to $BOARD:/tmp/ ..."
scp_board "$TARBALL" "${BOARD}:/tmp/cbd_kernel.tgz"
rm -f "$TARBALL"

# ── Step 5: Unpack and install on board ───────────────────────────────────────
info "Unpacking and installing (flavour: $INSTALL) on $BOARD ..."

case "$INSTALL" in
    qcom)    DEB_GLOB="arm64/linux-image-*[^t].deb arm64/linux-modules-*[^t].deb" ;;
    qcom-rt) DEB_GLOB="arm64/linux-image-*qcom-rt*.deb arm64/linux-modules-*qcom-rt*.deb" ;;
    all)     DEB_GLOB="arm64/linux-image-*.deb arm64/linux-modules-*.deb" ;;
esac

ssh_board "
    set -e
    cd /tmp
    rm -rf cbd_kernel_unpack
    mkdir cbd_kernel_unpack
    tar xzf cbd_kernel.tgz -C cbd_kernel_unpack
    cd cbd_kernel_unpack
    echo '--- debs to install ---'
    ls $DEB_GLOB 2>/dev/null || { echo 'No matching debs found!'; exit 1; }
    sudo dpkg -i $DEB_GLOB 2>&1 | grep -v '^$'
    echo '--- installation complete ---'
    uname -r
"

# ── Step 6: Reboot ────────────────────────────────────────────────────────────
if [ "$DO_REBOOT" -eq 1 ]; then
    info "Rebooting $BOARD ..."
    ssh_board "sudo reboot" || true

    info "Waiting for board to come back (up to 3 min)..."
    sleep 20
    for i in $(seq 1 36); do
        if ssh_board "echo UP; uname -r; uname -v" 2>/dev/null; then
            info "Board is back."
            break
        fi
        sleep 5
    done
else
    info "--no-reboot: skipping reboot"
fi

info "Done. Build: $BUILD_ID"
