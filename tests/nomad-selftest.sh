#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "SELF-TEST FAILED at line $LINENO (command: $BASH_COMMAND)" >&2' ERR

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for script in "$ROOT"/linux/*.sh "$ROOT"/installer/*.sh "$ROOT"/tests/*.sh; do
  bash -n "$script"
done
sh -n "$ROOT/installer/nomad-audit-installer.sh"

if ! bash -x "$ROOT/linux/nomad-audit.sh" "$TMP/audit" >"$TMP/audit.log" 2>&1; then cat "$TMP/audit.log"; exit 1; fi
test -s "$TMP/audit/nomad-hardware-report.txt"
grep -q "READ-ONLY AUDIT" "$TMP/audit/nomad-hardware-report.txt"

# Exercise the POSIX-shell audit intended for Debian Installer, without disk writes.
sh "$ROOT/installer/nomad-audit-installer.sh" "$TMP/installer-audit.txt" >"$TMP/installer-audit.log"
grep -q "N.O.M.A.D. E93z PRE-INSTALL HARDWARE AUDIT" "$TMP/installer-audit.txt"
grep -q "READ-ONLY AUDIT COMPLETE" "$TMP/installer-audit.txt"

if command -v python3 >/dev/null 2>&1 && test -s "$TMP/audit/nomad-hardware-report.json"; then
  python3 - "$TMP/audit/nomad-hardware-report.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    report = json.load(f)
assert report.get("read_only") is True
assert isinstance(report.get("blockdevices"), list)
assert "system" in report and "cpu" in report and "memory" in report
assert isinstance(report.get("pci_sysfs"), list)
assert isinstance(report.get("usb_sysfs"), list)
print("JSON report: valid")
PY
fi

# Force the no-pciutils/no-usbutils paths and prove the text audit falls back to sysfs.
if ! NOMAD_FORCE_SYSFS_PCI=1 NOMAD_FORCE_SYSFS_USB=1 bash "$ROOT/linux/nomad-audit.sh" "$TMP/audit-sysfs" >"$TMP/audit-sysfs.log" 2>&1; then
  cat "$TMP/audit-sysfs.log"
  exit 1
fi
grep -q 'raw PCI IDs and bound drivers from sysfs' "$TMP/audit-sysfs/nomad-hardware-report.txt"
grep -q 'USB IDs from sysfs' "$TMP/audit-sysfs/nomad-hardware-report.txt"

grep -q 'This utility will not partition, format, erase, or install anything' "$ROOT/linux/nomad-propose.sh"
grep -q 'No target will be guessed' "$ROOT/linux/nomad-propose.sh"

bash "$ROOT/tests/nomad-installer-selftest.sh"
echo "N.O.M.A.D. self-test passed."
