# Skills

All commands are run from the root of this repository (`qrap/`).

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
