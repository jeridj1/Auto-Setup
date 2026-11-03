#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'echo "INSTALLER SELF-TEST FAILED at line $LINENO (command: $BASH_COMMAND)" >&2' ERR
trap 'rm -rf "$TMP"' EXIT
SYS="$TMP/sys"
MOUNTS="$TMP/mounts"
mkdir -p "$SYS/class/dmi/id"
printf "LENOVO\\n" > "$SYS/class/dmi/id/sys_vendor"
printf "ThinkCentre E93z\\n" > "$SYS/class/dmi/id/product_name"
printf "0007US\\n" > "$SYS/class/dmi/id/product_version"
mkdir -p "$SYS/block" "$SYS/devices/pci0/ata0/sda" "$SYS/devices/pci0/ata1/sdd" "$SYS/devices/pci0/usb1/host1/sdb" "$SYS/devices/pci0/usb2/host2/sdc"
: > "$MOUNTS"

make_disk() {
  name="$1"; removable="$2"; sectors="$3"; path="$4"; model="$5"; serial="$6"
  mkdir -p "$SYS/block/$name"
  printf '%s\n' "$removable" > "$SYS/block/$name/removable"
  printf '%s\n' "$sectors" > "$SYS/block/$name/size"
  printf '%s\n' "$model" > "$SYS/devices/$path/model"
  printf '%s\n' "TESTVENDOR" > "$SYS/devices/$path/vendor"
  printf '%s\n' "$serial" > "$SYS/devices/$path/serial"
  ln -s "$SYS/devices/$path" "$SYS/block/$name/device"
}
make_disk sda 0 500000000 pci0/ata0/sda "E93Z TEST SSD" "SERIAL-ABC"
make_disk sdb 1 500000000 pci0/usb1/host1/sdb "USB INSTALLER" "USB-001"
make_disk sdc 0 500000000 pci0/usb2/host2/sdc "USB HDD" "USB-002"

OUT="$(NOMAD_TMP_ROOT="$TMP" NOMAD_TMP_ROOT="$TMP" NOMAD_SYSFS_ROOT="$SYS" NOMAD_PROC_MOUNTS="$MOUNTS" NOMAD_TEST_DISKS="/dev/sda /dev/sdb /dev/sdc" NOMAD_TEST_MODE=1 sh "$ROOT/installer/nomad-confirm-target.sh")"
grep -q '/dev/sda' <<<"$OUT"
grep -q 'E93Z TEST SSD' <<<"$OUT"
grep -q 'SERIAL-ABC' <<<"$OUT"
! grep -q '/dev/sdb' <<<"$OUT"
! grep -q '/dev/sdc' <<<"$OUT"

make_disk sdd 0 500000000 pci0/ata1/sdd "SECOND INTERNAL" "SERIAL-SECOND"
set +e
NOMAD_SYSFS_ROOT="$SYS" NOMAD_PROC_MOUNTS="$MOUNTS" NOMAD_TEST_DISKS="/dev/sda /dev/sdd" NOMAD_TEST_MODE=1 sh "$ROOT/installer/nomad-confirm-target.sh" >"$TMP/multiple.out" 2>&1
RC=$?
set -e
[[ "$RC" -eq 21 ]]
grep -q 'found 2 eligible internal disks' "$TMP/multiple.out"

printf '/dev/sda1 / ext4 rw 0 0\n' > "$MOUNTS"
set +e
NOMAD_SYSFS_ROOT="$SYS" NOMAD_PROC_MOUNTS="$MOUNTS" NOMAD_TEST_DISKS="/dev/sda" NOMAD_TEST_MODE=1 sh "$ROOT/installer/nomad-confirm-target.sh" >"$TMP/mounted.out" 2>&1
RC=$?
set -e
[[ "$RC" -eq 21 ]]
grep -q 'found 0 eligible internal disks' "$TMP/mounted.out"

cat > "$TMP/grub.cfg" <<'EOF'
set default=0
set timeout=5
menuentry 'Install' { true }
EOF
cat > "$TMP/txt.cfg" <<'EOF'
default install
label install
  menu label Install
EOF
python3 "$ROOT/tools/patch-boot-menus.py" "$TMP/grub.cfg" "$TMP/txt.cfg"
cp "$TMP/grub.cfg" "$TMP/grub.once"
cp "$TMP/txt.cfg" "$TMP/txt.once"
python3 "$ROOT/tools/patch-boot-menus.py" "$TMP/grub.cfg" "$TMP/txt.cfg"
cmp "$TMP/grub.cfg" "$TMP/grub.once"
cmp "$TMP/txt.cfg" "$TMP/txt.once"
grep -q 'set timeout=-1' "$TMP/grub.cfg"
grep -q 'preseed/file=/cdrom/preseed.cfg' "$TMP/grub.cfg"
grep -q 'preseed/file=/cdrom/preseed.cfg' "$TMP/txt.cfg"

grep -q 'partman/early_command' "$ROOT/installer/preseed.cfg"
! grep -Eq 'partman-auto/disk string /dev/' "$ROOT/installer/preseed.cfg"

echo "N.O.M.A.D. installer self-test passed."
