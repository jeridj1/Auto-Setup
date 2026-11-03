# N.O.M.A.D. Forge

## First deployment target

Lenovo ThinkCentre E93z, machine type 10B8, model 0007US.

Known hardware: Intel Core i5-4430S (x86-64), 4 GB RAM, Intel HD Graphics 4600, roughly 186 GB usable internal storage, wired Ethernet and Wi-Fi. One suspect USB port is physically damaged; do not use it.

## What this project is building

N.O.M.A.D. is an offline-first deployment and maintenance system. The first deliverable is a bootable Debian installer configured for this E93z. The longer-term project is a reusable deployment drive that can audit different computers, prepare machine-specific installs, preserve hardware profiles and logs, and support multiple nodes.

The current E93z installer is the first deployment tool, **not yet the complete multi-machine N.O.M.A.D. headquarters environment**.

## Current installer design

- Debian GNU/Linux 13.7 amd64, built from the official DVD-1 installer image.
- XFCE desktop, intended to run reasonably on the E93z's 4 GB RAM.
- Offline base installation from the DVD image. Network configuration and NTP are disabled inside the installer, so it does not wait for DHCP or require internet access.
- Debian firmware loading enabled. The included firmware still needs to be checked against the E93z's actual Wi-Fi chipset.
- BIOS/legacy and UEFI boot-menu entries are retained from the official Debian image.
- Installer is deliberately locked to Lenovo ThinkCentre E93z DMI identity.
- Disk selection requires exactly one eligible internal, non-removable, non-USB disk of at least 64 GiB. Multiple candidates, a mounted candidate, or no candidate cause a hard stop.
- Before partitioning, the installer displays the selected disk's device path, vendor, model, serial when available, capacity, existing partitions and filesystems, plus the detected UEFI/legacy boot mode.
- The approval screen also states the rough 30-60 minute installation estimate, lack of backup/preservation, unknown Wi-Fi chipset, wired-Ethernet fallback, and the one first-boot password action.
- Destructive work requires the exact phrase `ERASE AND INSTALL NOMAD`. The approval authorizes deleting the target drive's partition table and all its partitions. This is not a secure data-wipe operation.
- The installed `nomad` account starts locked; first boot prompts once to set its password.
- Official Debian repositories are configured for updates after installation when networking is available.

The installer does not silently choose between multiple disks. Do not connect additional internal-style storage devices during installation. External USB drives are excluded from target selection. The screen's 30-60 minute figure is only an estimate.

## Getting the installer

The GitHub Actions workflow downloads Debian's official DVD-1 image, verifies Debian's signed SHA-512 checksum list, remasters the image with the N.O.M.A.D. boot entry and installer files, then publishes the finished ISO as a GitHub Release.

The full ISO is not uploaded as one GitHub asset because it exceeds GitHub's 2 GiB per-asset limit. It is split into three pieces smaller than that limit. Download every `NOMAD-Debian13.7-E93z.iso.partNN` segment, the matching `.sha512` file, and `reassemble-nomad-iso.ps1` into one folder. In PowerShell, from that folder:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\reassemble-nomad-iso.ps1
```

The script joins the numbered parts and verifies the finished ISO with SHA-512. Do not try to write the individual part files to USB.

Use Rufus or another USB image-writing tool to write the completed ISO to a USB drive. Writing the image erases the selected USB drive. Use a known-good USB port on the E93z; avoid the damaged port. A 16 GB USB stick is sufficient for this installer image. Do not use a data drive unless it is intended to be completely erased.

At boot, select **N.O.M.A.D. Automated install**. The standard Debian installer entries remain available, but they are not the N.O.M.A.D. workflow.

## Building locally (optional)

A Linux system with `xorriso`, `python3`, and `sha512sum` can build the ISO directly:

```bash
bash installer/build-nomad-iso.sh /path/to/debian-13.7.0-amd64-DVD-1.iso NOMAD-Debian13.7-E93z.iso
```

No local build environment is required when using the GitHub Release workflow.

## Development checks

Run:

```bash
bash tests/nomad-selftest.sh
```

GitHub Actions runs the automated checks on pushes and pull requests. Tests cover shell syntax, report generation and JSON validity, simulated disk discovery, USB/removable-device exclusion, ambiguous and mounted disk rejection, the E93z-only restriction, partition and boot-mode reporting, repeated disk-identity checks, and idempotent boot-menu patching with an indented Debian-style GRUB entry. A Windows runner also tests segmented ISO reassembly and SHA-512 verification.

## What is not yet physically verified

The automated tests are synthetic safety tests; they do not prove a complete install on the actual E93z. Before treating the installer as production-ready, the ISO must boot in both firmware modes where supported, pass an installation test on a disposable virtual disk, and then be tested on the actual E93z only after its internal drive identity and condition are known.

The actual E93z storage model/health, Wi-Fi chipset and firmware requirement, BIOS mode, and memory configuration remain to be collected. Do not treat the install as fully validated until those checks and a successful test installation are recorded.

## Repository layout

- `config/e93z.ini`: known reference-machine profile
- `windows/collect-e93z.ps1`: read-only Windows hardware collector
- `linux/nomad-audit.sh`: Linux live-session hardware report
- `linux/nomad-propose.sh`: read-only candidate-disk proposal
- `installer/`: Debian preseed, approval gate, first-boot setup and ISO builder
- `tools/patch-boot-menus.py`: adds N.O.M.A.D. entries to BIOS and UEFI menus
- `tests/`: automated safety and build-logic checks
- `.github/workflows/`: automated checks and ISO-release build

