# Introduction

The purpose of this project is to facilitate automatic testing of enabled boards.

# Boards supported:
Hamoa
Monza2

Monza2 is supported by Ubuntu Noble (24.04), while Hamoa is only supported by Ubuntu Resolute (26.04)


# Board control
To turn board on or off or enter EDL mode, there is a tool in:

~/qualcomm/carmel-tools 
To turn the board on:
sudo ~/qualcomm/carmel-tools/alpaca.py on

To turn the board off:
sudo ~/qualcomm/carmel-tools/alpaca.py off

To enter EDL mode:
~/qualcomm/carmel-tools/alpaca.py edl

# Flashing images
The images are here:
~/qualcomm/images

Directories inside are structured in such a way that 26.04 and 24.04 contain directories pointing to specific releases (like x02, x07, x11 etc).

## Flashing Monza2

Download nhlos artifact:
```
wget https://artifacts.codelinaro.org/artifactory/qli-ci/flashable-binaries/ubuntu-fw/QCS8300/QLI.1.7-Ver.1.3/QLI.1.7-Ver.1.3-ubuntu-QCS8300-nhlos-bins.tar.gz
```

extract it and remove the artifacts:
```
tar xf QLI.1.7-Ver.1.3-ubuntu-QCS8300-nhlos-bins.tar.gz && rm QLI.1.7-Ver.1.3-ubuntu-QCS8300-nhlos-bins.tar.gz && cd QLI.1.7-Ver.1.3-ubuntu-QCS8300-nhlos-bins
```

create support directories:
```
mkdir cdt_monza && cd cdt_monz
```

download more boot artifacts:
```
wget https://artifacts.codelinaro.org/artifactory/codelinaro-le/Qualcomm_Linux/QCS8300/cdt/qcs8275-Monza_v1.zip
```

unzip them and get rid of the arfchive:
```
unzip qcs8275-Monza_v1.zip && rm qcs8275-Monza_v1.zip
```

put device in EDL mode:
```
use `alpaca.py edl` to enter EDL mode, wait a few seconds
```

flash boot artifacts:
```
qdl --storage emmc prog_firehose_ddr.elf rawprogram1.xml patch1.xml
```

go up one directory:
```
cd ..
```

copy ubuntu image files to this directory (paths are just an example, use proper images 
```
cp /path/to/ubuntu.img .
cp /path/to/dtb.bin .
cp /path/to/rawprogram0_emmc.xml partition_emmc/
```

put device in EDL mode using alpaca.py script and flash the image:
```
sudo qdl --storage emmc --include=partition_emmc prog_firehose_ddr.elf partition_emmc/rawprogram*.xml partition_emmc/patch*.xml
```


