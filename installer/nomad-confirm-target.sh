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

# A repeated partman callback must re-use the already approved device, not ask again.
APPROVAL_FILE="$TMP_ROOT/nomad-target-approved"
if [ -r "$APPROVAL_FILE" ]; then
    APPROVED=$(sed -n '1p' "$APPROVAL_FILE")
    [ "$APPROVED" = "$TARGET" ] || {
        echo "STOP: the detected disk changed after approval. No changes made." >&2
        exit 22
    }
    command -v debconf-set >/dev/null 2>&1 || exit 23
    debconf-set partman-auto/disk "$TARGET"
    debconf-set grub-installer/bootdev "$TARGET"
    exit 0
fi

if [ "${NOMAD_TEST_MODE:-0}" = "1" ]; then
    echo "TEST-ONLY DISCOVERY RESULT: $TARGET | $VENDOR $MODEL | $SERIAL | $GIB"
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
printf 'Computer: Lenovo ThinkCentre E93z (reference profile)\n' >&3
printf 'Target device: %s\n' "$TARGET" >&3
printf 'Drive: %s %s\n' "$VENDOR" "$MODEL" >&3
printf 'Serial: %s\n' "$SERIAL" >&3
printf 'Capacity: %s\n' "$GIB" >&3
printf 'Connection: internal, non-removable, non-USB\n' >&3
printf '\nTHIS WILL ERASE THE ENTIRE TARGET DRIVE, ALL PARTITIONS, AND ALL DATA.\n' >&3
printf 'It will install Debian 13 with the XFCE desktop.\n' >&3
printf 'No other detected internal disk will be touched.\n' >&3
printf '\nAfter installation, first boot will ask you to create the nomad account password once.\n' >&3
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
printf '%s\n' "$TARGET" > "$APPROVAL_FILE"
printf '\nApproval accepted. Debian Installer may now partition the named drive.\n' >&3
exit 0
