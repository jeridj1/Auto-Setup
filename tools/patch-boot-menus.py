#!/usr/bin/env python3
"""Insert the guarded N.O.M.A.D. option into Debian 13 installer boot menus."""
from __future__ import annotations
import re
import sys
from pathlib import Path

MARKER = "N.O.M.A.D. AUTOMATED INSTALL"

GRUB_ENTRY = """# N.O.M.A.D. AUTOMATED INSTALL (all disk changes gated by one approval)
menuentry 'N.O.M.A.D. Automated install (one approval, erases target disk)' {
    set background_color=black
    linux /install.amd/vmlinuz auto=true priority=critical preseed/file=/cdrom/preseed.cfg locale=en_US.UTF-8 keyboard-configuration/xkb-keymap=us netcfg/get_hostname=nomad-e93z ---
    initrd /install.amd/initrd.gz
}
"""

ISOLINUX_ENTRY = """# N.O.M.A.D. AUTOMATED INSTALL (all disk changes gated by one approval)
label nomad
    menu label ^N.O.M.A.D. Automated install (one approval, erases target disk)
    kernel /install.amd/vmlinuz
    append auto=true priority=critical preseed/file=/cdrom/preseed.cfg locale=en_US.UTF-8 keyboard-configuration/xkb-keymap=us netcfg/get_hostname=nomad-e93z initrd=/install.amd/initrd.gz ---
"""

def patch_grub(text: str) -> str:
    if MARKER in text:
        return text
    timeout = re.search(r"(?m)^set timeout=[^\n]*$", text)
    if timeout:
        text = text[:timeout.start()] + "set timeout=-1" + text[timeout.end():]
        pos = text.find("\n", timeout.start())
        if pos < 0:
            pos = len(text)
        else:
            pos += 1
        return text[:pos] + GRUB_ENTRY + text[pos:]
    return "set timeout=-1\n" + GRUB_ENTRY + text

def patch_isolinux(text: str) -> str:
    if MARKER in text:
        return text
    match = re.search(r"(?m)^label\s+", text)
    if match:
        return text[:match.start()] + ISOLINUX_ENTRY + text[match.start():]
    return ISOLINUX_ENTRY + text

def main() -> int:
    if len(sys.argv) != 3:
        print("usage: patch-boot-menus.py grub.cfg isolinux-txt.cfg", file=sys.stderr)
        return 2
    grub = Path(sys.argv[1])
    isolinux = Path(sys.argv[2])
    for path in (grub, isolinux):
        if not path.is_file():
            print(f"required boot menu not found: {path}", file=sys.stderr)
            return 3
    grub.write_text(patch_grub(grub.read_text(encoding="utf-8")), encoding="utf-8")
    isolinux.write_text(patch_isolinux(isolinux.read_text(encoding="utf-8")), encoding="utf-8")
    for path in (grub, isolinux):
        data = path.read_text(encoding="utf-8")
        if MARKER not in data:
            print(f"failed to insert N.O.M.A.D. entry into {path}", file=sys.stderr)
            return 4
        if "preseed/file=/cdrom/preseed.cfg" not in data:
            print(f"missing preseed path in {path}", file=sys.stderr)
            return 5
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
