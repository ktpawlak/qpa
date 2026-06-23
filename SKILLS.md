# Skills

All commands are run from the root of this repository (`qrap/`).

## CBD Remote Kernel Build (Hamoa / Resolute)

CBD is the Canonical remote kernel build system for the `resolute` (Ubuntu 26.04)
series. Builds are triggered by pushing to the `cbd` remote from the kernel tree
at `~/qualcomm/linux`.

### Build options

Full CBD option list: `ssh cbd help`

```bash
# Build only the qcom (non-RT) flavour — fast, ~35 min warm cache
git push cbd -o native

# Build only the qcom-rt (PREEMPT_RT) flavour
git push cbd -o native -o binary-qcom-rt

# Build ALL flavours (qcom + qcom-rt) — tarball is ~400 MB
git push cbd -o native -o binary
```

**Important:** `-o native` alone only builds `qcom`. To get the RT kernel you
must add `-o binary-qcom-rt` or `-o binary`.

### Build ID format

`kpawlak-resolute-<SHORT_SHA>-<4DIGITS>/arm64`

The ID is printed by the push. Check status:

```bash
ssh cbd.kernel ls kpawlak-resolute-<ID>          # list files + status
ssh cbd.kernel ls kpawlak-resolute-<ID>/arm64 | grep -oE "BUILD-OK|BUILD-FAILED|BUILDING|QUEUED"
```

### Download artifacts

**Must redirect to a file** — the tarball is streamed to stdout:

```bash
ssh cbd tarball kpawlak-resolute-<ID>/arm64 > tarball.tgz   # ~200 MB (qcom only)
                                                              # ~400 MB (all flavours)
ssh cbd log     kpawlak-resolute-<ID>/arm64 > log.txt        # build log
```

### Install on device (Hamoa, ubuntu@192.168.1.123, password: changeme12)

```bash
sshpass -p 'changeme12' scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    tarball.tgz ubuntu@192.168.1.123:/tmp/

sshpass -p 'changeme12' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ubuntu@192.168.1.123 '
  cd /tmp && tar xzf tarball.tgz
  # Install specific flavour (e.g. RT):
  sudo dpkg -i arm64/linux-image-*qcom-rt*.deb arm64/linux-modules-*qcom-rt*.deb
  # Or install all flavours:
  sudo dpkg -i arm64/linux-image-*.deb arm64/linux-modules-*.deb
  sudo reboot
'
```

`flash-kernel` and GRUB update automatically; wait ~2 min for the board to come
back, then verify with `uname -r`.

### Automated push → build → deploy

`cbd-deploy.sh` (in this repo) does the full pipeline in one command:

```bash
cd ~/qualcomm/linux

# Build qcom (non-RT) and deploy to board
~/qualcomm/qpa/cbd-deploy.sh

# Build and deploy RT kernel
~/qualcomm/qpa/cbd-deploy.sh --flavour qcom-rt

# Build all flavours, install only RT
~/qualcomm/qpa/cbd-deploy.sh --flavour all --install qcom-rt

# Skip push, re-use existing build ID
~/qualcomm/qpa/cbd-deploy.sh --build-id kpawlak-resolute-<SHA>-<N> --no-reboot
```

---

## Flash Hamoa

Flashing is a single-phase process (no CDT step). One EDL cycle flashes the full Ubuntu OS image.

### One-time setup: download NHLOS artifacts

Skip this if `boards/hamoa/nhlos/` already contains the artifacts.

```bash
wget -P /tmp https://artifacts.codelinaro.org/artifactory/qli-ci/flashable-binaries/ubuntu-fw/X1E80100/IQ-X.1.7-Ver.1.1/IQ-X.1.7-Ver.1.1-ubuntu-X1E80100-nhlos-bins.tar.gz
tar xf /tmp/IQ-X.1.7-Ver.1.1-ubuntu-X1E80100-nhlos-bins.tar.gz \
    --strip-components=1 -C boards/hamoa/nhlos/
rm /tmp/IQ-X.1.7-Ver.1.1-ubuntu-X1E80100-nhlos-bins.tar.gz
```

### Flash (automated)

```bash
./flash-hamoa.sh ~/qualcomm/images/26.04/x02
```

The script copies the image and XML files, enters EDL, flashes, and power-cycles.
The final `qdl: firehose operation timed out` is expected and not an error.

### Manual steps

#### Copy image and partition files

Run this when changing to a new release (e.g. `x02`). Adjust the `IMG` path as needed.

```bash
IMG=~/qualcomm/images/26.04/x02   # adjust release tag as needed

cp $IMG/ubuntu-*.img          boards/hamoa/nhlos/
cp $IMG/rawprogram0.xml       boards/hamoa/nhlos/
cp $IMG/rawprogram0_emmc.xml  boards/hamoa/nhlos/
```

#### Flash Ubuntu OS image

New layout (image dir contains `partition_ufs/` subdirectory):

```bash
sudo ~/qualcomm/carmel-tools/alpaca.py off && sleep 2 && sudo ~/qualcomm/carmel-tools/alpaca.py edl
sleep 3
cd boards/hamoa/nhlos
# Note: patch0.xml is intentionally excluded — it modifies the partition table
# and must NOT be applied when flashing a pre-partitioned UFS image.
sudo qdl --storage ufs xbl_s_devprg_ns.melf \
    partition_ufs/rawprogram[0-9].xml \
    partition_ufs/patch[1-9].xml \
    --include partition_ufs/
cd -
```

Legacy layout (image dir contains only `rawprogram0.xml` at root, e.g. x02/x03):

```bash
sudo ~/qualcomm/carmel-tools/alpaca.py off && sleep 2 && sudo ~/qualcomm/carmel-tools/alpaca.py edl
sleep 3
cd boards/hamoa/nhlos
sudo qdl --storage ufs xbl_s_devprg_ns.melf rawprogram0.xml
cd -
```

The automated `flash-hamoa.sh` script detects the layout automatically.

Power cycle for a clean boot:

```bash
sudo ~/qualcomm/carmel-tools/alpaca.py off
sudo ~/qualcomm/carmel-tools/alpaca.py on
```

#### First login: change default password

```bash
ssh ubuntu@192.168.1.123
# Password prompt: ubuntu
# Current password: ubuntu
# New password: changeme12
# Retype new password: changeme12
```

After the password change the session closes automatically — log in again:

```bash
ssh ubuntu@192.168.1.123   # password: changeme12
```

## Flash Monza2

Flashing is a two-phase process. Each phase requires the board to be in EDL mode.

### One-time setup: download NHLOS artifacts

Skip this if `boards/monza2/nhlos/` already contains the artifacts.

```bash
# Download and extract NHLOS binaries into boards/monza2/nhlos/
wget -P /tmp https://artifacts.codelinaro.org/artifactory/qli-ci/flashable-binaries/ubuntu-fw/QCS8300/QLI.1.7-Ver.1.3/QLI.1.7-Ver.1.3-ubuntu-QCS8300-nhlos-bins.tar.gz
tar xf /tmp/QLI.1.7-Ver.1.3-ubuntu-QCS8300-nhlos-bins.tar.gz \
    --strip-components=1 -C boards/monza2/nhlos/
rm /tmp/QLI.1.7-Ver.1.3-ubuntu-QCS8300-nhlos-bins.tar.gz

# Download CDT boot artifacts
mkdir -p boards/monza2/nhlos/cdt_monza && cd boards/monza2/nhlos/cdt_monza
wget https://artifacts.codelinaro.org/artifactory/codelinaro-le/Qualcomm_Linux/QCS8300/cdt/qcs8275-Monza_v1.zip
unzip qcs8275-Monza_v1.zip && rm qcs8275-Monza_v1.zip
cd -
```

### One-time setup: link Ubuntu image

Run this when changing to a new release (e.g. `x11`). Adjust the `IMG` path to the release you want to flash.

```bash
IMG=~/qualcomm/images/24.04/x11   # adjust release tag as needed

# Symlink image files into the project (avoids copying large files)
ln -sf $IMG/ubuntu-*.img boards/monza2/nhlos/
ln -sf $IMG/dtb.bin      boards/monza2/nhlos/
cp $IMG/rawprogram0_emmc.xml boards/monza2/nhlos/partition_emmc/
```

### Phase 1: flash CDT boot artifacts

Power cycle the board into EDL, then:

```bash
sudo ~/qualcomm/carmel-tools/alpaca.py off && sleep 2 && sudo ~/qualcomm/carmel-tools/alpaca.py edl
sleep 3
cd boards/monza2/nhlos/cdt_monza
sudo qdl --storage emmc prog_firehose_ddr.elf rawprogram1.xml patch1.xml
cd -
```

The board resets automatically when done. Confirm success by checking for `[PROGRAM] flashed`
lines and `bsp_target_reset()` in the output. The final `qdl: firehose operation timed out`
after the reset is expected and not an error.

### Phase 2: flash Ubuntu OS image

Power cycle the board into EDL again, then flash:

```bash
sudo ~/qualcomm/carmel-tools/alpaca.py off && sleep 2 && sudo ~/qualcomm/carmel-tools/alpaca.py edl
sleep 3
cd boards/monza2/nhlos
sudo qdl --storage emmc \
    --include=partition_emmc \
    prog_firehose_ddr.elf \
    partition_emmc/rawprogram*.xml \
    partition_emmc/patch*.xml
cd -
```

The board resets and boots Ubuntu when done. The final timeout message is expected.

Power cycle to ensure a clean boot:

```bash
sudo ~/qualcomm/carmel-tools/alpaca.py off
sudo ~/qualcomm/carmel-tools/alpaca.py on
```

### First login: change default password

Ubuntu's default password (`ubuntu`) is expired on first boot and must be changed immediately. The `flash-monza2.sh` script handles this automatically, but if doing it manually:

```bash
# Wait for the board to be reachable (check with ping), then:
ssh ubuntu@192.168.1.185
# Password prompt: ubuntu
# Current password: ubuntu
# New password: changeme12
# Retype new password: changeme12
```

After the password change the session is closed automatically — log in again with the new password:

```bash
ssh ubuntu@192.168.1.185   # password: changeme12
```

## Board First-Boot Setup (Hamoa)

### Fix WiFi not scanning (regulatory domain)

After a fresh flash the regulatory domain is `country 00` (world roaming),
which flags all 2.4GHz channels as `PASSIVE-SCAN` and causes `nmcli device
wifi list` to return empty.

```bash
# On the board — set country code and make persistent
echo "options cfg80211 ieee80211_regdom=PL" | sudo tee /etc/modprobe.d/cfg80211.conf
# Takes effect on next reboot; or immediately:
sudo nmcli device wifi rescan
```

Replace `PL` with your country code (GB, DE, US, etc.).
