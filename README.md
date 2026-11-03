# N.O.M.A.D. Forge

**First target:** Lenovo ThinkCentre E93z (machine type 10B8, model 0007US).

This repository is the working source for the N.O.M.A.D. offline-first deployment project. The first milestone is a verified hardware audit and a machine-specific installation proposal. The eventual goal is a reusable bootable external deployment drive that can assess a computer, show one complete installation proposal, receive one approval, and then complete the installation without repeated prompts.

## Known E93z hardware

- Intel Core i5-4430S, 4th-generation Haswell, x86-64
- 4 GB RAM
- Intel HD Graphics 4600
- Approximately 186 GB reported usable storage
- Wired Ethernet and Wi-Fi
- One suspect USB port; do not use that port

## Current milestone: read-only assessment

The scripts in this repository **do not partition, format, erase, or install anything**. They collect system information and produce reports. The disk proposal script deliberately stops if it cannot identify exactly one plausible internal disk.

### Linux live-session audit

From a Debian/Ubuntu live session, run:

```bash
chmod +x linux/*.sh
sudo ./linux/nomad-audit.sh
sudo ./linux/nomad-propose.sh
```

### Windows audit

Open PowerShell as Administrator in this repository directory:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\windows\collect-e93z.ps1
```

## Planned deployment architecture

- Debian Stable, 64-bit, with XFCE as the initial lightweight desktop candidate.
- Hardware-specific firmware and drivers, verified against the actual E93z devices.
- Offline package cache/repository with checksums and resumable acquisition.
- Persistent audit reports, hardware profiles, and installation logs.
- Reusable external-drive deployment media, separate from the target computer's internal disk.
- One approval screen showing the exact target disk identity, capacity, serial, partitions, intended changes, expected duration, and any required human intervention.
- After approval, unattended installation with logging, failure recovery, and a final completion report.

## Developer self-test

Run the non-destructive local checks with:

```bash
bash tests/nomad-selftest.sh
```

GitHub Actions runs the same checks on pushes and pull requests. The self-test validates shell syntax, runs the read-only audit into a temporary directory, and checks the JSON report when Python and `lsblk` are available.

## Important build gates

This repository is **not yet a bootable installer**. Before enabling destructive installation, we must verify the exact storage device and health, Wi-Fi chipset/firmware, BIOS boot mode, package set, recovery method, and the installer in a VM and on a recoverable test disk. Do not run destructive commands from an unreviewed branch or commit.

The first objective is to make the E93z work reliably. Generalized multi-machine deployment comes after that reference machine passes testing.
