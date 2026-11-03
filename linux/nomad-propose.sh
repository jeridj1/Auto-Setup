#!/usr/bin/env bash
set -Eeuo pipefail

echo "N.O.M.A.D. INSTALLATION PROPOSAL — READ ONLY"
echo "This utility will not partition, format, erase, or install anything."
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo for full device details."; exit 1; }
command -v lsblk >/dev/null || { echo "lsblk is required."; exit 1; }

echo
echo "All detected disks:"
lsblk -dpno NAME,SIZE,MODEL,SERIAL,TRAN,RM,RO,TYPE | awk '$7=="disk" || $8=="disk" {print}'

mapfile -t CANDIDATES < <(
  lsblk -dpno PATH,TRAN,RM,TYPE |
  awk '$4=="disk" && $3=="0" && $2!="usb" {print $1}'
)
echo
if [ "${#CANDIDATES[@]}" -ne 1 ]; then
  echo "STOP: found ${#CANDIDATES[@]} plausible internal disks."
  echo "No target will be guessed. A human-readable proposal needs exact device identity."
  exit 2
fi

TARGET="${CANDIDATES[0]}"
echo "Single plausible internal-disk candidate:"
lsblk -dnpo PATH,SIZE,MODEL,SERIAL,TRAN,RM,RO "$TARGET"
echo
echo "PROPOSED (not executed):"
echo "- Debian Stable 64-bit with XFCE candidate desktop"
echo "- GPT partitioning, EFI system partition if booted in UEFI mode"
echo "- ext4 root filesystem"
echo "- zram rather than a fixed swap partition for the initial 4 GB RAM profile"
echo
echo "Any future destructive installer must re-identify the disk by model + serial + capacity,"
echo "show its current partitions, and obtain one explicit approval before changing it."
echo "STATUS: proposal only; no changes made."
