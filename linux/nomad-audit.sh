#!/usr/bin/env bash
set -Eeuo pipefail

OUT="${1:-./NOMAD-REPORT}"
mkdir -p "$OUT"
REPORT="$OUT/nomad-hardware-report.txt"
JSON="$OUT/nomad-hardware-report.json"

have() { command -v "$1" >/dev/null 2>&1; }
read_sys() { cat "$1" 2>/dev/null || printf 'unknown'; }

{
  echo "N.O.M.A.D. HARDWARE SURVEY"
  echo "Generated: $(date -Is 2>/dev/null || date)"
  echo
  echo "=== SYSTEM ==="
  echo "Manufacturer: $(read_sys /sys/class/dmi/id/sys_vendor)"
  echo "Product: $(read_sys /sys/class/dmi/id/product_name)"
  echo "Product version: $(read_sys /sys/class/dmi/id/product_version)"
  echo "BIOS version: $(read_sys /sys/class/dmi/id/bios_version)"
  echo "BIOS date: $(read_sys /sys/class/dmi/id/bios_date)"
  echo "Firmware mode: $([ -d /sys/firmware/efi ] && echo UEFI || echo Legacy-BIOS)"
  echo
  echo "=== CPU ==="
  if have lscpu; then lscpu; else cat /proc/cpuinfo; fi
  echo
  echo "=== MEMORY ==="
  if have free; then free -h; else cat /proc/meminfo; fi
  echo
  echo "=== PCI DEVICES ==="
  if have lspci; then lspci -nnk; else echo "lspci unavailable (pciutils not installed)"; fi
  echo
  echo "=== STORAGE ==="
  if have lsblk; then lsblk -e 7 -o NAME,PATH,TYPE,SIZE,MODEL,SERIAL,TRAN,RM,RO,FSTYPE,MOUNTPOINTS; fi
  echo
  echo "=== NETWORK ==="
  if have ip; then ip -brief link; ip -brief address; fi
  if have nmcli; then nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status; fi
  echo
  echo "=== USB ==="
  if have lsusb; then lsusb; fi
  echo
  echo "=== NOTES ==="
  echo "READ-ONLY AUDIT: no partitions, filesystems, or settings were changed."
} | tee "$REPORT"

if have python3 && have lsblk; then
python3 - "$JSON" <<'PY'
import json, os, platform, subprocess, sys
out=sys.argv[1]
def cmd(args):
    try: return subprocess.check_output(args,text=True,stderr=subprocess.DEVNULL).strip()
    except Exception: return ""
def rd(path):
    try:
        with open(path) as f: return f.read().strip()
    except Exception: return "unknown"
try:
    block=json.loads(cmd(["lsblk","-J","-b","-o","NAME,PATH,TYPE,SIZE,MODEL,SERIAL,TRAN,RM,RO,FSTYPE,MOUNTPOINTS"]))
except Exception:
    block={}
data={
 "generated":cmd(["date","-Is"]),
 "hostname":platform.node(),
 "system":{"manufacturer":rd("/sys/class/dmi/id/sys_vendor"),
           "product":rd("/sys/class/dmi/id/product_name"),
           "product_version":rd("/sys/class/dmi/id/product_version"),
           "bios_version":rd("/sys/class/dmi/id/bios_version"),
           "bios_date":rd("/sys/class/dmi/id/bios_date"),
           "firmware_mode":"UEFI" if os.path.isdir("/sys/firmware/efi") else "Legacy-BIOS"},
 "cpu":cmd(["lscpu"]),
 "memory":cmd(["free","-b"]),
 "pci":cmd(["lspci","-nnk"]),
 "blockdevices":block.get("blockdevices",[]),
 "network_links":cmd(["ip","-brief","link"]),
 "network_addresses":cmd(["ip","-brief","address"]),
 "read_only":True
}
with open(out,"w") as f: json.dump(data,f,indent=2)
PY
fi

echo
echo "Audit complete: $REPORT"
[ -f "$JSON" ] && echo "JSON report: $JSON"
