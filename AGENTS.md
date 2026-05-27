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

# Images

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
to be downloaded once. They do not change between Ubuntu releases.

# Skills

See SKILLS.md for step-by-step procedures.
