#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ISO="${1:-}"
OUT="${2:-NOMAD-Debian13.7-E93z.iso}"

if [[ -z "$ISO" || ! -f "$ISO" ]]; then
  echo "Usage: $0 /path/to/debian-13.7.0-amd64-DVD-1.iso [output.iso]" >&2
  exit 2
fi
for tool in xorriso python3 sha512sum grub-script-check; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing required tool: $tool" >&2
    exit 3
  }
done
ISO="$(realpath "$ISO")"
OUT="$(realpath -m "$OUT")"
[[ "$ISO" != "$OUT" ]] || { echo "Output must not overwrite the source ISO." >&2; exit 4; }

SIZE="$(stat -c '%s' "$ISO")"
if (( SIZE < 2000000000 )); then
  echo "This is too small to be Debian DVD-1. Use the full amd64 DVD-1 image for offline XFCE installation." >&2
  exit 5
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/nomad"

echo "Checking that the source ISO is a bootable Debian installer image..."
xorriso -indev "$ISO" -report_el_torito plain >"$WORK/boot-report.txt" 2>&1
grep -qi 'El Torito' "$WORK/boot-report.txt" || {
  cat "$WORK/boot-report.txt" >&2
  echo "Source ISO does not expose an El Torito boot catalog." >&2
  exit 6
}

echo "Extracting the existing BIOS/UEFI boot menus and installer kernel..."
xorriso -osirrox on -indev "$ISO" \
  -extract /boot/grub/grub.cfg "$WORK/grub.cfg" \
  -extract /isolinux/txt.cfg "$WORK/txt.cfg" \
  -extract /install.amd/vmlinuz "$WORK/vmlinuz.check" \
  -extract /install.amd/initrd.gz "$WORK/initrd.check" \
  >"$WORK/extract.log" 2>&1 || {
    cat "$WORK/extract.log" >&2
    echo "The ISO layout did not match the expected Debian 13 amd64 DVD-1 structure." >&2
    exit 7
  }

chmod u+w "$WORK/grub.cfg" "$WORK/txt.cfg"
python3 "$ROOT/tools/patch-boot-menus.py" "$WORK/grub.cfg" "$WORK/txt.cfg"
grub-script-check "$WORK/grub.cfg"
cp "$ROOT/installer/preseed.cfg" "$WORK/preseed.cfg"
cp "$ROOT/installer/nomad-confirm-target.sh" "$WORK/nomad/nomad-confirm-target.sh"
cp "$ROOT/installer/late-command.sh" "$WORK/nomad/late-command.sh"
cp "$ROOT/installer/nomad-firstboot-password.sh" "$WORK/nomad/nomad-firstboot-password.sh"
cp "$ROOT/installer/nomad-firstboot-password.service" "$WORK/nomad/nomad-firstboot-password.service"
cp "$ROOT/linux/nomad-audit.sh" "$WORK/nomad/nomad-audit.sh"
cp "$ROOT/linux/nomad-propose.sh" "$WORK/nomad/nomad-propose.sh"
chmod 0755 "$WORK/nomad/"*.sh

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
echo "Building remastered ISO. The original boot catalog is being preserved..."
xorriso -indev "$ISO" -outdev "$OUT" \
  -map "$WORK/grub.cfg" /boot/grub/grub.cfg \
  -map "$WORK/txt.cfg" /isolinux/txt.cfg \
  -map "$WORK/preseed.cfg" /preseed.cfg \
  -map "$WORK/nomad" /nomad \
  -boot_image any replay \
  -compliance no_emul_toc \
  -padding included

echo "Verifying the resulting ISO boot catalog and embedded N.O.M.A.D. files..."
xorriso -indev "$OUT" -report_el_torito plain >"$WORK/output-boot-report.txt" 2>&1
grep -qi 'El Torito' "$WORK/output-boot-report.txt"
xorriso -indev "$OUT" -find / -name preseed.cfg -exec echo >"$WORK/output-files.txt" 2>&1
grep -q 'preseed.cfg' "$WORK/output-files.txt"
xorriso -indev "$OUT" -find / -name nomad-confirm-target.sh -exec echo >>"$WORK/output-files.txt" 2>&1
grep -q 'nomad-confirm-target.sh' "$WORK/output-files.txt"

# Verify the final ISO, not merely the temporary source configs, contains both
# boot-menu entries and their preseed paths after xorriso remastering.
xorriso -osirrox on -indev "$OUT" \
  -extract /boot/grub/grub.cfg "$WORK/final-grub.cfg" \
  -extract /isolinux/txt.cfg "$WORK/final-isolinux.cfg" \
  >"$WORK/final-menu-extract.log" 2>&1
grep -q "N.O.M.A.D. Automated install" "$WORK/final-grub.cfg"
grep -q "N.O.M.A.D. Automated install" "$WORK/final-isolinux.cfg"
grep -q "preseed/file=/cdrom/preseed.cfg" "$WORK/final-grub.cfg"
grub-script-check "$WORK/final-grub.cfg"
grep -q "preseed/file=/cdrom/preseed.cfg" "$WORK/final-isolinux.cfg"

sha512sum "$OUT" | awk -v name="$(basename "$OUT")" '{print $1 "  " name}' > "$OUT.sha512"

echo
echo "N.O.M.A.D. installer ISO created:"
echo "  $OUT"
echo "  $OUT.sha512"
echo "Boot mode: BIOS + UEFI structures preserved from the official ISO."
echo "Install mode: offline Debian 13 DVD-1 package source; explicit approval required."
echo "IMPORTANT: first boot requires setting the nomad account password once."
