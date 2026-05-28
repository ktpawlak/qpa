# Copilot Instructions

This repository (`qrap`) automates flashing Ubuntu images onto Qualcomm development boards.

## Boards

| Board  | Ubuntu version   | SoC      |
|--------|------------------|----------|
| Monza2 | Noble (24.04)    | QCS8300  |
| Hamoa  | Resolute (26.04) | —        |

## Repository layout

```
qrap/
  flash-monza2.sh          # automated two-phase flash script
  boards/
    monza2/
      nhlos/               # NHLOS artifacts — gitignored, downloaded separately
        cdt_monza/         # CDT boot artifacts
        partition_emmc/    # rawprogram/patch XMLs (copied from image dir)
        prog_firehose_ddr.elf
        ubuntu-*.img       # symlinked from ~/qualcomm/images/
        dtb.bin            # symlinked from ~/qualcomm/images/
  SKILLS.md                # step-by-step procedures (source of truth for operations)
  AGENTS.md                # AI agent context (mirrors custom instructions)
```

`boards/<board>/nhlos/` and `boards/<board>/images/` are gitignored. Large binary artifacts (NHLOS tarballs, Ubuntu images) live outside the repo under `~/qualcomm/images/` and are symlinked in.

## Board control

Board power and mode are managed via `~/qualcomm/carmel-tools/alpaca.py` (requires `sudo`):

```bash
sudo ~/qualcomm/carmel-tools/alpaca.py on   # power on
sudo ~/qualcomm/carmel-tools/alpaca.py off  # power off
sudo ~/qualcomm/carmel-tools/alpaca.py edl  # signal EDL mode
```

**Critical EDL sequence:** `alpaca.py off` must come before `alpaca.py edl` to power-cycle the board. Without the power-off step, the USB flashing port (`05c6:9008`) won't enumerate. Confirm EDL with `lsusb | grep 05c6:9008`.

## Flashing workflow

Flashing is always two phases, each requiring EDL mode:

1. **Phase 1 — CDT boot artifacts** (`boards/monza2/nhlos/cdt_monza/`)
2. **Phase 2 — Ubuntu OS image** (`boards/monza2/nhlos/`)

The automated script handles both phases end-to-end:

```bash
# All commands from repo root
./flash-monza2.sh ~/qualcomm/images/24.04/x11
```

The script: symlinks image files, enters EDL, flashes CDT, re-enters EDL, flashes Ubuntu, power-cycles.

The final `qdl: firehose operation timed out` after each phase is **expected** — it means the board reset successfully.

## Key conventions

- All scripts must be run from the **repo root** (`qrap/`).
- Image directories are addressed by release tag (e.g. `x11`, `x07`) under `~/qualcomm/images/<os-version>/`.
- `rawprogram0_emmc.xml` is **copied** (not symlinked) into `boards/monza2/nhlos/partition_emmc/` because `qdl` reads it with relative paths.
- `ubuntu-*.img` and `dtb.bin` are **symlinked** to avoid duplicating large files.
- NHLOS artifacts must be downloaded once before first flash — see SKILLS.md for the exact `wget`/`tar` commands and artifact URLs.
- `qdl` is the Qualcomm flashing tool and must be in `PATH`.
