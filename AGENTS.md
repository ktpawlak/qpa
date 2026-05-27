# Introduction

The purpose of this project is to facilitate automatic testing of enabled boards.

# Boards supported

| Board  | Ubuntu version   |
|--------|------------------|
| Monza2 | Noble (24.04)    |
| Hamoa  | Resolute (26.04) |

# Board control

Board power and mode are managed via `~/qualcomm/carmel-tools/alpaca.py`:

```bash
sudo ~/qualcomm/carmel-tools/alpaca.py on   # power on
sudo ~/qualcomm/carmel-tools/alpaca.py off  # power off
sudo ~/qualcomm/carmel-tools/alpaca.py edl  # enter EDL (Emergency Download) mode
```

The script uses an FTDI USB interface to control the board. It requires `sudo` for all operations.

> **Note:** `alpaca.py edl` signals the board to enter EDL mode, but the board's USB flashing
> port will only enumerate on the host (as `05c6:9008`) if the board was **physically unplugged
> from power** before the command. A software power-off (`alpaca.py off`) is not sufficient.
> To confirm the board is in EDL mode, check: `lsusb | grep 05c6:9008`

# Flashing images

Images live in `~/qualcomm/images/`, organised by OS version then release tag:

```
~/qualcomm/images/
  24.04/
    x11/   ← ubuntu img, dtb.bin, rawprogram XMLs
    x07/
    ...
  26.04/
    ...
```

NHLOS artifacts (bootloader, firehose, CDT) are kept in `~/qualcomm/monza2/` and only need
to be downloaded once (see below). They do not change between Ubuntu releases.

## Flashing Monza2

Flashing is a two-phase process. Each phase requires the board to be in EDL mode.
Because the `sudo` password prompt adds latency, run both `alpaca.py edl` and `qdl` inside
a single `sudo bash -c` session to avoid the board timing out of EDL before `qdl` connects.
Use absolute paths inside `sudo bash -c` — `~` expands to `/root`, not your home directory.

### One-time setup: download NHLOS artifacts

Skip this if `~/qualcomm/monza2/` already contains the artifacts.

```bash
cd ~/qualcomm/monza2

# Download and extract NHLOS binaries
wget https://artifacts.codelinaro.org/artifactory/qli-ci/flashable-binaries/ubuntu-fw/QCS8300/QLI.1.7-Ver.1.3/QLI.1.7-Ver.1.3-ubuntu-QCS8300-nhlos-bins.tar.gz
tar xf QLI.1.7-Ver.1.3-ubuntu-QCS8300-nhlos-bins.tar.gz && rm QLI.1.7-Ver.1.3-ubuntu-QCS8300-nhlos-bins.tar.gz
cd QLI.1.7-Ver.1.3-ubuntu-QCS8300-nhlos-bins

# Download CDT boot artifacts
mkdir cdt_monza && cd cdt_monza
wget https://artifacts.codelinaro.org/artifactory/codelinaro-le/Qualcomm_Linux/QCS8300/cdt/qcs8275-Monza_v1.zip
unzip qcs8275-Monza_v1.zip && rm qcs8275-Monza_v1.zip
```

### Phase 1: flash CDT boot artifacts

Physically unplug the board from power, then:

```bash
sudo bash -c "
  /home/$USER/qualcomm/carmel-tools/alpaca.py edl
  sleep 3
  cd /home/$USER/qualcomm/monza2/QLI.1.7-Ver.1.3-ubuntu-QCS8300-nhlos-bins/cdt_monza
  qdl --storage emmc prog_firehose_ddr.elf rawprogram1.xml patch1.xml
"
```

The board resets automatically when done. Confirm success by checking for `[PROGRAM] flashed`
lines and `bsp_target_reset()` in the output. The final `qdl: firehose operation timed out`
after the reset is expected and not an error.

### Phase 2: flash Ubuntu OS image

Set `RELEASE` to the desired release directory (e.g. `x11`):

```bash
NHLOS=/home/$USER/qualcomm/monza2/QLI.1.7-Ver.1.3-ubuntu-QCS8300-nhlos-bins
IMG=/home/$USER/qualcomm/images/24.04/x11

# Use symlinks to avoid copying the large image file
ln -sf $IMG/ubuntu-*.img $NHLOS/
ln -sf $IMG/dtb.bin $NHLOS/
cp $IMG/rawprogram0_emmc.xml $NHLOS/partition_emmc/
```

Physically unplug the board from power again, then flash:

```bash
sudo bash -c "
  /home/$USER/qualcomm/carmel-tools/alpaca.py edl
  sleep 3
  cd /home/$USER/qualcomm/monza2/QLI.1.7-Ver.1.3-ubuntu-QCS8300-nhlos-bins
  qdl --storage emmc --include=partition_emmc prog_firehose_ddr.elf partition_emmc/rawprogram*.xml partition_emmc/patch*.xml
"
```

The board resets and boots Ubuntu when done. The final timeout message is expected.

After flashing completes, power cycle the board to ensure a clean boot:

```bash
sudo ~/qualcomm/carmel-tools/alpaca.py off
sudo ~/qualcomm/carmel-tools/alpaca.py on
```

