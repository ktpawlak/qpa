# Skills

## Flash Monza2

Flashing is a two-phase process. Each phase requires the board to be in EDL mode.

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
sudo ~/qualcomm/carmel-tools/alpaca.py edl
sleep 3
cd ~/qualcomm/monza2/QLI.1.7-Ver.1.3-ubuntu-QCS8300-nhlos-bins/cdt_monza
sudo qdl --storage emmc prog_firehose_ddr.elf rawprogram1.xml patch1.xml
```

The board resets automatically when done. Confirm success by checking for `[PROGRAM] flashed`
lines and `bsp_target_reset()` in the output. The final `qdl: firehose operation timed out`
after the reset is expected and not an error.

### Phase 2: flash Ubuntu OS image

Prepare image symlinks (avoids copying the large image file):

```bash
NHLOS=~/qualcomm/monza2/QLI.1.7-Ver.1.3-ubuntu-QCS8300-nhlos-bins
IMG=~/qualcomm/images/24.04/x11   # adjust release tag as needed

ln -sf $IMG/ubuntu-*.img $NHLOS/
ln -sf $IMG/dtb.bin $NHLOS/
cp $IMG/rawprogram0_emmc.xml $NHLOS/partition_emmc/
```

Physically unplug the board from power again, then flash:

```bash
sudo ~/qualcomm/carmel-tools/alpaca.py edl
sleep 3
cd ~/qualcomm/monza2/QLI.1.7-Ver.1.3-ubuntu-QCS8300-nhlos-bins
sudo qdl --storage emmc --include=partition_emmc prog_firehose_ddr.elf partition_emmc/rawprogram*.xml partition_emmc/patch*.xml
```

The board resets and boots Ubuntu when done. The final timeout message is expected.

Power cycle to ensure a clean boot:

```bash
sudo ~/qualcomm/carmel-tools/alpaca.py off
sudo ~/qualcomm/carmel-tools/alpaca.py on
```
