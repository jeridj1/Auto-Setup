#!/bin/sh
# Read-only hardware snapshot for the Debian Installer shell.
# POSIX sh only: intended for the minimal installer environment.
set -eu
OUT="${1:-/tmp/NOMAD-E93z-audit.txt}"
{
  echo "N.O.M.A.D. E93z PRE-INSTALL HARDWARE AUDIT"
  date 2>/dev/null || true
  echo
  echo "=== SYSTEM / BIOS ==="
  for f in sys_vendor product_name product_version bios_version bios_date; do
    printf '%s: ' "$f"
    cat "/sys/class/dmi/id/$f" 2>/dev/null || echo unknown
  done
  if [ -d /sys/firmware/efi ]; then echo "Firmware mode: UEFI"; else echo "Firmware mode: Legacy BIOS"; fi
  echo
  echo "=== CPU ==="
  grep -m1 -E 'model name|Processor' /proc/cpuinfo 2>/dev/null || true
  echo
  echo "=== MEMORY ==="
  grep -E 'MemTotal|MemAvailable' /proc/meminfo 2>/dev/null || true
  echo
  echo "=== PCI DEVICES (including Wi-Fi and graphics IDs) ==="
  for d in /sys/bus/pci/devices/*; do
    [ -d "$d" ] || continue
    driver=unbound
    [ ! -L "$d/driver" ] || driver=$(basename "$(readlink -f "$d/driver")")
    printf '%s vendor=%s device=%s class=%s driver=%s\n' "${d##*/}" \
      "$(cat "$d/vendor" 2>/dev/null || echo '?')" \
      "$(cat "$d/device" 2>/dev/null || echo '?')" \
      "$(cat "$d/class" 2>/dev/null || echo '?')" "$driver"
  done
  echo
  echo "=== USB DEVICES ==="
  for d in /sys/bus/usb/devices/*; do
    [ -r "$d/idVendor" ] || continue
    printf '%s vendor=%s product=%s manufacturer=%s name=%s\n' "${d##*/}" \
      "$(cat "$d/idVendor" 2>/dev/null || echo '?')" \
      "$(cat "$d/idProduct" 2>/dev/null || echo '?')" \
      "$(cat "$d/manufacturer" 2>/dev/null || echo '?')" \
      "$(cat "$d/product" 2>/dev/null || echo '?')"
  done
  echo
  echo "=== STORAGE (IDENTIFICATION ONLY, NO CHANGES) ==="
  if command -v lsblk >/dev/null 2>&1; then
    lsblk -e 7 -o NAME,PATH,TYPE,SIZE,MODEL,SERIAL,TRAN,RM,RO,FSTYPE,MOUNTPOINTS
  else
    for d in /sys/block/*; do
      [ -d "$d" ] || continue
      printf '%s sectors=%s removable=%s model=%s\n' "${d##*/}" \
        "$(cat "$d/size" 2>/dev/null || echo '?')" \
        "$(cat "$d/removable" 2>/dev/null || echo '?')" \
        "$(cat "$d/device/model" 2>/dev/null || echo '?')"
    done
  fi
  echo
  echo "=== NETWORK INTERFACES ==="
  for d in /sys/class/net/*; do
    [ -d "$d" ] || continue
    printf '%s' "${d##*/}"
    [ ! -L "$d/device/driver" ] || printf ' driver=%s' "$(basename "$(readlink -f "$d/device/driver")")"
    echo
  done
  echo
  echo "READ-ONLY AUDIT COMPLETE. No disk, partition, or firmware settings were changed."
} | tee "$OUT"
echo
echo "Report saved to: $OUT"
