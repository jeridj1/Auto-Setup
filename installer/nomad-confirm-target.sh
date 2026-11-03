#!/bin/sh
# N.O.M.A.D. destructive-action safety gate for Debian Installer.
# Selects exactly one non-removable, non-USB internal disk, shows its identity,
# requires an explicit phrase, then sets the Debian Installer disk variables.
set -eu

SYSFS_ROOT="${NOMAD_SYSFS_ROOT:-/sys}"
MOUNTS_FILE="${NOMAD_PROC_MOUNTS:-/proc/mounts}"
TMP_ROOT="${NOMAD_TMP_ROOT:-/tmp}"

# This first build is deliberately locked to the reference Lenovo E93z.
DMI_VENDOR=$(cat "$SYSFS_ROOT/class/dmi/id/sys_vendor" 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
DMI_PRODUCT=$(cat "$SYSFS_ROOT/class/dmi/id/product_name" 2>/dev/null || true)
DMI_VERSION=$(cat "$SYSFS_ROOT/class/dmi/id/product_version" 2>/dev/null || true)
DMI_LABEL=$(printf '%s %s' "$DMI_PRODUCT" "$DMI_VERSION" | tr '[:upper:]' '[:lower:]')
case "$DMI_VENDOR" in *lenovo*) ;; *)
    echo "STOP: this installer build is restricted to Lenovo ThinkCentre E93z." >&2
    echo "Detected manufacturer: ${DMI_VENDOR:-unknown}" >&2
    exit 19 ;;
esac
case "$DMI_LABEL" in *e93z*|*10b8*|*0007us*) ;; *)
    echo "STOP: this installer build is restricted to Lenovo ThinkCentre E93z (type 10B8 / model 0007US)." >&2
    echo "Detected product: ${DMI_PRODUCT:-unknown} / ${DMI_VERSION:-unknown}" >&2
    exit 19 ;;
esac
CANDIDATE_FILE="$TMP_ROOT/nomad-candidates.$$"
mkdir -p "$TMP_ROOT"
: > "$CANDIDATE_FILE"
trap 'rm -f "$CANDIDATE_FILE"' EXIT HUP INT TERM

if [ "${NOMAD_TEST_DISKS+x}" = x ]; then
    DISKS=$NOMAD_TEST_DISKS
else
    command -v list-devices >/dev/null 2>&1 || {
        echo "STOP: Debian Installer list-devices utility is unavailable." >&2
        exit 20
    }
    DISKS=$(list-devices disk 2>/dev/null || true)
fi

for DEV in $DISKS; do
    case "$DEV" in /dev/*) ;; *) continue ;; esac
    NAME=${DEV#/dev/}
    case "$NAME" in ""|*/*) continue ;; esac
    BLOCK="$SYSFS_ROOT/block/$NAME"
    [ -r "$BLOCK/removable" ] || continue
    [ "$(cat "$BLOCK/removable" 2>/dev/null || echo 1)" = "0" ] || continue

    DEVICE_PATH=$(readlink -f "$BLOCK/device" 2>/dev/null || true)
    case "$DEVICE_PATH" in
        */usb[0-9]*/*|*/usb/*) continue ;;
    esac

    SECTORS=$(cat "$BLOCK/size" 2>/dev/null || echo 0)
    case "$SECTORS" in ''|*[!0-9]*) continue ;; esac
    BYTES=$((SECTORS * 512))
    # Reject implausibly small devices; the reference E93z disk is ~186 GB usable.
    [ "$BYTES" -ge $((64 * 1024 * 1024 * 1024)) ] || continue

    # Never repartition a disk that currently contains a mounted filesystem.
    if [ -r "$MOUNTS_FILE" ] && awk -v d="$DEV" '
        $1 == d { found=1 }
        index($1,d)==1 && length($1)>length(d) {
            tail=substr($1,length(d)+1,1)
            if (tail ~ /[0-9p]/) found=1
        }
        END { exit !found }
    ' "$MOUNTS_FILE"; then
        continue
    fi

    MODEL=$(cat "$BLOCK/device/model" 2>/dev/null | tr '\n|' '  ' | sed 's/[[:space:]]*$//' || true)
    VENDOR=$(cat "$BLOCK/device/vendor" 2>/dev/null | tr '\n|' '  ' | sed 's/[[:space:]]*$//' || true)
    # Prefer the serial exposed through this disk's sysfs device path.
    # udevadm is a fallback only; this also keeps test fixtures isolated from host devices.
    SERIAL=$(cat "$BLOCK/device/serial" 2>/dev/null || true)
    if [ -z "$SERIAL" ] && command -v udevadm >/dev/null 2>&1; then
        SERIAL=$(udevadm info --query=property --name="$DEV" 2>/dev/null |
            sed -n 's/^ID_SERIAL_SHORT=//p' | head -n 1 || true)
        [ -n "$SERIAL" ] || SERIAL=$(udevadm info --query=property --name="$DEV" 2>/dev/null |
            sed -n 's/^ID_SERIAL=//p' | head -n 1 || true)
    fi
    [ -n "$MODEL" ] || MODEL="Model unavailable"
    [ -n "$VENDOR" ] || VENDOR="Vendor unavailable"
    [ -n "$SERIAL" ] || SERIAL="Serial unavailable"
    MODEL=$(printf '%s' "$MODEL" | tr '\n|' '  ')
    VENDOR=$(printf '%s' "$VENDOR" | tr '\n|' '  ')
    SERIAL=$(printf '%s' "$SERIAL" | tr '\n|' '  ')

    printf '%s|%s|%s|%s|%s\n' "$DEV" "$VENDOR" "$MODEL" "$SERIAL" "$BYTES" >> "$CANDIDATE_FILE"
done

COUNT=$(awk 'END {print NR+0}' "$CANDIDATE_FILE")
if [ "$COUNT" -ne 1 ]; then
    echo
    echo "N.O.M.A.D. STOP: found $COUNT eligible internal disks; exactly one is required."
    echo "No disk has been selected and no disk changes have been made."
    if [ -s "$CANDIDATE_FILE" ]; then
        echo "Eligible devices:"
        while IFS='|' read -r DEV VENDOR MODEL SERIAL BYTES; do
            GIB=$(awk -v b="$BYTES" 'BEGIN {printf "%.1f GiB", b/1073741824}')
            echo "  $DEV | $VENDOR $MODEL | $SERIAL | $GIB"
        done < "$CANDIDATE_FILE"
    fi
    exit 21
fi

IFS='|' read -r TARGET VENDOR MODEL SERIAL BYTES < "$CANDIDATE_FILE"
GIB=$(awk -v b="$BYTES" 'BEGIN {printf "%.1f GiB", b/1073741824}')
DISK_NAME=${TARGET#/dev/}
PARTITION_SUMMARY=""
for PART in "$SYSFS_ROOT/block/$DISK_NAME/"*; do
    [ -r "$PART/partition" ] || continue
    PART_NAME=${PART##*/}
    PART_SECTORS=$(cat "$PART/size" 2>/dev/null || echo 0)
    case "$PART_SECTORS" in ''|*[!0-9]*) PART_SECTORS=0 ;; esac
    PART_GIB=$(awk -v s="$PART_SECTORS" 'BEGIN {printf "%.1f GiB", (s*512)/1073741824}')
    PARTITION_SUMMARY="$PARTITION_SUMMARY $PART_NAME ($PART_GIB);"
done
[ -n "$PARTITION_SUMMARY" ] || PARTITION_SUMMARY=" none detected"

# A repeated partman callback must re-use the already approved device, not ask again.
APPROVAL_FILE="$TMP_ROOT/nomad-target-approved"
if [ -r "$APPROVAL_FILE" ]; then
    APPROVED_TARGET=$(sed -n '1p' "$APPROVAL_FILE")
    APPROVED_VENDOR=$(sed -n '2p' "$APPROVAL_FILE")
    APPROVED_MODEL=$(sed -n '3p' "$APPROVAL_FILE")
    APPROVED_SERIAL=$(sed -n '4p' "$APPROVAL_FILE")
    APPROVED_BYTES=$(sed -n '5p' "$APPROVAL_FILE")
    if [ "$APPROVED_TARGET" != "$TARGET" ] ||
       [ "$APPROVED_VENDOR" != "$VENDOR" ] ||
       [ "$APPROVED_MODEL" != "$MODEL" ] ||
       [ "$APPROVED_SERIAL" != "$SERIAL" ] ||
       [ "$APPROVED_BYTES" != "$BYTES" ]; then
        echo "STOP: the approved disk identity changed. No changes made." >&2
        exit 22
    fi
    command -v debconf-set >/dev/null 2>&1 || exit 23
    debconf-set partman-auto/disk "$TARGET"
    debconf-set grub-installer/bootdev "$TARGET"
    exit 0
fi

if [ "${NOMAD_TEST_MODE:-0}" = "1" ]; then
    echo "TEST-ONLY DISCOVERY RESULT: $TARGET | $VENDOR $MODEL | $SERIAL | $GIB | partitions:$PARTITION_SUMMARY"
    exit 0
fi

if command -v chvt >/dev/null 2>&1; then chvt 1 >/dev/null 2>&1 || true; fi
TTY="${NOMAD_TTY:-/dev/tty1}"
[ -c "$TTY" ] || TTY=/dev/console
[ -c "$TTY" ] || {
    echo "STOP: cannot access installer console for approval. No disk changes made." >&2
    exit 24
}
exec 3<> "$TTY" || {
    echo "STOP: cannot open installer console for approval. No disk changes made." >&2
    exit 24
}

printf '\n' >&3
printf '========== N.O.M.A.D. INSTALL APPROVAL ==========\n' >&3
printf 'Computer: %s %s %s\n' "$DMI_VENDOR" "$DMI_PRODUCT" "$DMI_VERSION" >&3
printf 'Target device: %s\n' "$TARGET" >&3
printf 'Drive: %s %s\n' "$VENDOR" "$MODEL" >&3
printf 'Serial: %s\n' "$SERIAL" >&3
printf 'Capacity: %s\n' "$GIB" >&3
printf 'Existing partitions: %s\n' "$PARTITION_SUMMARY" >&3
printf 'Connection: internal, non-removable, non-USB\n' >&3
printf '\nTHIS WILL DELETE THE EXISTING PARTITION TABLE AND ALL PARTITIONS ON THIS DRIVE.\n' >&3
printf 'All data on the target drive will be lost. This is not a secure data-wipe operation.\n' >&3
printf 'No backup is created and no existing operating system or files are preserved.\n' >&3
printf '\nInstall: Debian 13 with XFCE; fully offline, no network required.\n' >&3
printf 'Estimated time: roughly 30-60 minutes; actual time depends on drive and USB speed.\n' >&3
printf 'Known limitation: the exact Wi-Fi adapter is not yet identified.\n' >&3
printf 'If Wi-Fi firmware is missing after installation, use wired Ethernet for updates.\n' >&3
printf 'First boot requires setting the nomad account password once.\n' >&3
printf 'No other eligible internal disk will be touched.\n' >&3
printf '\nTo approve, type exactly: ERASE AND INSTALL NOMAD\n' >&3
printf 'Anything else cancels before partitioning.\n\nApproval: ' >&3
IFS= read -r APPROVAL <&3 || APPROVAL=""
if [ "$APPROVAL" != "ERASE AND INSTALL NOMAD" ]; then
    printf '\nCancelled. No disk changes have been made.\n' >&3
    exit 25
fi

command -v debconf-set >/dev/null 2>&1 || {
    printf '\nSTOP: debconf-set is unavailable. No disk changes made.\n' >&3
    exit 23
}
debconf-set partman-auto/disk "$TARGET"
debconf-set grub-installer/bootdev "$TARGET"

{
    echo "N.O.M.A.D. target approval"
    echo "Device: $TARGET"
    echo "Vendor: $VENDOR"
    echo "Model: $MODEL"
    echo "Serial: $SERIAL"
    echo "Capacity: $GIB"
    echo "Approved phrase: ERASE AND INSTALL NOMAD"
    date -Is 2>/dev/null || date
} > /var/log/nomad-target-approval.txt
{
    printf '%s\n' "$TARGET"
    printf '%s\n' "$VENDOR"
    printf '%s\n' "$MODEL"
    printf '%s\n' "$SERIAL"
    printf '%s\n' "$BYTES"
} > "$APPROVAL_FILE.tmp"
mv "$APPROVAL_FILE.tmp" "$APPROVAL_FILE"
printf '\nApproval accepted. Debian Installer may now partition the named drive.\n' >&3
exit 0
