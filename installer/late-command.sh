#!/bin/sh
# Runs from Debian Installer after the target system has been installed.
set -eu
MEDIA=/cdrom
[ -d "$MEDIA/nomad" ] || {
    echo "N.O.M.A.D. support files not found at /cdrom/nomad." >&2
    exit 30
}
TARGET_ROOT=/target
[ -d "$TARGET_ROOT/etc" ] || exit 31

# Network configuration is skipped in the installer to guarantee a fully offline
# install. Set the installed hostname directly.
printf '%s\\n' "nomad-e93z" > "$TARGET_ROOT/etc/hostname"
if ! grep -q '^127\\.0\\.1\\.1[[:space:]]' "$TARGET_ROOT/etc/hosts"; then
    printf '%s\\n' "127.0.1.1 nomad-e93z.local nomad-e93z" >> "$TARGET_ROOT/etc/hosts"
fi

mkdir -p "$TARGET_ROOT/usr/local/share/nomad" "$TARGET_ROOT/usr/local/bin" "$TARGET_ROOT/usr/local/sbin"
cp "$MEDIA/nomad/nomad-audit.sh" "$TARGET_ROOT/usr/local/share/nomad/nomad-audit.sh"
cp "$MEDIA/nomad/nomad-propose.sh" "$TARGET_ROOT/usr/local/share/nomad/nomad-propose.sh"
cp "$MEDIA/nomad/nomad-firstboot-password.sh" "$TARGET_ROOT/usr/local/sbin/nomad-firstboot-password"
chmod 0755 "$TARGET_ROOT/usr/local/share/nomad/nomad-audit.sh"
chmod 0755 "$TARGET_ROOT/usr/local/share/nomad/nomad-propose.sh"
chmod 0755 "$TARGET_ROOT/usr/local/sbin/nomad-firstboot-password"
ln -sf ../share/nomad/nomad-audit.sh "$TARGET_ROOT/usr/local/bin/nomad-audit"
ln -sf ../share/nomad/nomad-propose.sh "$TARGET_ROOT/usr/local/bin/nomad-propose"

mkdir -p "$TARGET_ROOT/etc/systemd/system"
cp "$MEDIA/nomad/nomad-firstboot-password.service" "$TARGET_ROOT/etc/systemd/system/"
chmod 0644 "$TARGET_ROOT/etc/systemd/system/nomad-firstboot-password.service"

# Keep the installation fully offline. Configure official repositories for updates
# and additional packages after first boot, when networking is available.
mkdir -p "$TARGET_ROOT/etc/apt/sources.list.d"
cat > "$TARGET_ROOT/etc/apt/sources.list.d/debian.sources" <<'EOF'
Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://security.debian.org/debian-security
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
if [ -f "$TARGET_ROOT/etc/apt/sources.list" ]; then
    sed -i '/^[[:space:]]*deb[[:space:]]\+cdrom:/d' "$TARGET_ROOT/etc/apt/sources.list"
fi

mkdir -p "$TARGET_ROOT/var/lib/nomad"
if [ -r /var/log/nomad-target-approval.txt ]; then
    cp /var/log/nomad-target-approval.txt "$TARGET_ROOT/root/NOMAD_INSTALL_REPORT.txt"
fi
cat >> "$TARGET_ROOT/root/NOMAD_INSTALL_REPORT.txt" <<'EOF'

Installed configuration:
- Debian GNU/Linux 13 (Trixie), 64-bit
- XFCE desktop
- Local N.O.M.A.D. read-only audit and disk proposal commands
- First-boot password setup for user 'nomad'
- Official Debian network repositories configured for later updates
- No network downloads required during the base installation
EOF

in-target systemctl enable nomad-firstboot-password.service
echo "N.O.M.A.D. late-install setup completed."
