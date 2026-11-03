#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'echo "INSTALLER SELF-TEST FAILED at line $LINENO (command: $BASH_COMMAND)" >&2' ERR
trap 'rm -rf "$TMP"' EXIT

SYS="$TMP/sys"
MOUNTS="$TMP/mounts"
mkdir -p "$SYS/class/dmi/id" "$SYS/block"
printf '%s\n' "LENOVO" > "$SYS/class/dmi/id/sys_vendor"
printf '%s\n' "ThinkCentre E93z" > "$SYS/class/dmi/id/product_name"
printf '%s\n' "0007US" > "$SYS/class/dmi/id/product_version"
mkdir -p "$SYS/devices/pci0/ata0/sda" "$SYS/devices/pci0/ata1/sdd" \
  "$SYS/devices/pci0/usb1/host1/sdb" "$SYS/devices/pci0/usb2/host2/sdc"
: > "$MOUNTS"

make_disk() {
  local name="$1" removable="$2" sectors="$3" path="$4" model="$5" serial="$6"
  mkdir -p "$SYS/block/$name"
  printf '%s\n' "$removable" > "$SYS/block/$name/removable"
  printf '%s\n' "$sectors" > "$SYS/block/$name/size"
  printf '%s\n' "$model" > "$SYS/devices/$path/model"
  printf '%s\n' "TESTVENDOR" > "$SYS/devices/$path/vendor"
  printf '%s\n' "$serial" > "$SYS/devices/$path/serial"
  ln -s "$SYS/devices/$path" "$SYS/block/$name/device"
}

make_disk sda 0 500000000 pci0/ata0/sda "E93Z TEST SSD" "SERIAL-ABC"
mkdir -p "$SYS/block/sda/sda1"
printf '%s\n' "1" > "$SYS/block/sda/sda1/partition"
printf '%s\n' "300000000" > "$SYS/block/sda/sda1/size"
make_disk sdb 1 500000000 pci0/usb1/host1/sdb "USB INSTALLER" "USB-001"
make_disk sdc 0 500000000 pci0/usb2/host2/sdc "USB HDD" "USB-002"

# Exactly one internal drive should be detected; removable and USB drives are excluded.
OUT="$(NOMAD_TMP_ROOT="$TMP" NOMAD_SYSFS_ROOT="$SYS" NOMAD_PROC_MOUNTS="$MOUNTS" \
  NOMAD_TEST_DISKS="/dev/sda /dev/sdb /dev/sdc" NOMAD_TEST_MODE=1 \
  sh "$ROOT/installer/nomad-confirm-target.sh")"
grep -q '/dev/sda' <<<"$OUT"
grep -q 'E93Z TEST SSD' <<<"$OUT"
grep -q 'SERIAL-ABC' <<<"$OUT"
grep -q 'sda1' <<<"$OUT"
grep -q 'partitions:' <<<"$OUT"
grep -q 'filesystem unknown' <<<"$OUT"
grep -q 'Legacy BIOS' <<<"$OUT"
! grep -q '/dev/sdb' <<<"$OUT"
! grep -q '/dev/sdc' <<<"$OUT"

# Two eligible internal disks must stop rather than guess.
make_disk sdd 0 500000000 pci0/ata1/sdd "SECOND INTERNAL" "SERIAL-SECOND"
if NOMAD_TMP_ROOT="$TMP" NOMAD_SYSFS_ROOT="$SYS" NOMAD_PROC_MOUNTS="$MOUNTS" \
  NOMAD_TEST_DISKS="/dev/sda /dev/sdd" NOMAD_TEST_MODE=1 \
  sh "$ROOT/installer/nomad-confirm-target.sh" >"$TMP/multiple.out" 2>&1; then RC=0; else RC=$?; fi
[[ "$RC" -eq 21 ]]
grep -q 'found 2 eligible internal disks' "$TMP/multiple.out"

# Any mounted partition makes the drive ineligible.
printf '/dev/sda1 / ext4 rw 0 0\n' > "$MOUNTS"
if NOMAD_TMP_ROOT="$TMP" NOMAD_SYSFS_ROOT="$SYS" NOMAD_PROC_MOUNTS="$MOUNTS" \
  NOMAD_TEST_DISKS="/dev/sda" NOMAD_TEST_MODE=1 \
  sh "$ROOT/installer/nomad-confirm-target.sh" >"$TMP/mounted.out" 2>&1; then RC=0; else RC=$?; fi
[[ "$RC" -eq 21 ]]
grep -q 'found 0 eligible internal disks' "$TMP/mounted.out"

# GRUB boot entry must be inserted after Debian's media-root setup, at top level.
cat > "$TMP/grub.cfg" <<'EOF'
set default=0
search --no-floppy --set=root --label Debian
if [ x$feature_timeout_style = xy ]; then
  set timeout_style=menu
  set timeout=5
else
  set timeout=5
fi
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
SEARCH_LINE=$(grep -n '^search --no-floppy' "$TMP/grub.cfg" | cut -d: -f1)
CUSTOM_LINE=$(grep -n 'N.O.M.A.D. Automated install' "$TMP/grub.cfg" | head -n1 | cut -d: -f1)
ORIGINAL_LINE=$(grep -n "menuentry 'Install'" "$TMP/grub.cfg" | cut -d: -f1)
[[ "$SEARCH_LINE" -lt "$CUSTOM_LINE" ]]
[[ "$CUSTOM_LINE" -lt "$ORIGINAL_LINE" ]]
grep -q '^fi$' "$TMP/grub.cfg"
grep -q 'preseed/file=/cdrom/preseed.cfg' "$TMP/grub.cfg"
grep -q 'preseed/file=/cdrom/preseed.cfg' "$TMP/txt.cfg"

# The preseed must run the target gate and must not contain a fixed disk path.
grep -q 'partman/early_command' "$ROOT/installer/preseed.cfg"
! grep -Eq 'partman-auto/disk string /dev/' "$ROOT/installer/preseed.cfg"
grep -q 'Existing partitions: %s' "$ROOT/installer/nomad-confirm-target.sh"
grep -q 'This is not a secure data-wipe operation' "$ROOT/installer/nomad-confirm-target.sh"

# Installer must refuse a different manufacturer.
printf '%s\n' "Dell Inc." > "$SYS/class/dmi/id/sys_vendor"
if NOMAD_TMP_ROOT="$TMP" NOMAD_SYSFS_ROOT="$SYS" NOMAD_PROC_MOUNTS="$MOUNTS" \
  NOMAD_TEST_DISKS="/dev/sda" NOMAD_TEST_MODE=1 \
  sh "$ROOT/installer/nomad-confirm-target.sh" >"$TMP/wrong-system.out" 2>&1; then RC=0; else RC=$?; fi
[[ "$RC" -eq 19 ]]
grep -q 'restricted to Lenovo ThinkCentre E93z' "$TMP/wrong-system.out"

# A second partman callback must match the complete approved drive identity.
: > "$MOUNTS"
printf '%s\n' "LENOVO" > "$SYS/class/dmi/id/sys_vendor"
mkdir -p "$TMP/bin"
cat > "$TMP/bin/debconf-set" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$NOMAD_DEBCONF_LOG"
EOF
chmod +x "$TMP/bin/debconf-set"
printf '%s\n' "/dev/sda" "TESTVENDOR" "E93Z TEST SSD" "SERIAL-ABC" "256000000000" > "$TMP/nomad-target-approved"
if NOMAD_TEST_DISKS="/dev/sda" NOMAD_TMP_ROOT="$TMP" NOMAD_SYSFS_ROOT="$SYS" \
  NOMAD_PROC_MOUNTS="$MOUNTS" NOMAD_DEBCONF_LOG="$TMP/debconf.log" \
  PATH="$TMP/bin:$PATH" sh "$ROOT/installer/nomad-confirm-target.sh"; then RC=0; else RC=$?; fi
[[ "$RC" -eq 0 ]]
grep -q 'partman-auto/disk /dev/sda' "$TMP/debconf.log"
grep -q 'grub-installer/bootdev /dev/sda' "$TMP/debconf.log"

# If the serial changes after approval, the repeated callback must stop.
printf '%s\n' "SERIAL-CHANGED" > "$SYS/devices/pci0/ata0/sda/serial"
if NOMAD_TEST_DISKS="/dev/sda" NOMAD_TMP_ROOT="$TMP" NOMAD_SYSFS_ROOT="$SYS" \
  NOMAD_PROC_MOUNTS="$MOUNTS" NOMAD_DEBCONF_LOG="$TMP/debconf.log" \
  PATH="$TMP/bin:$PATH" sh "$ROOT/installer/nomad-confirm-target.sh" \
  >"$TMP/identity-mismatch.out" 2>&1; then RC=0; else RC=$?; fi
[[ "$RC" -eq 22 ]]
grep -q 'approved disk identity changed' "$TMP/identity-mismatch.out"

echo "N.O.M.A.D. installer self-test passed."
