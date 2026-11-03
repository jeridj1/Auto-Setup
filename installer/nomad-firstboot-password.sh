#!/bin/sh
set -eu
echo
echo "N.O.M.A.D. first boot: create the password for account 'nomad'."
echo "This is done once. The password will not be displayed or stored in a text file."
while ! passwd nomad; do
    echo "Password setup did not complete. Please try again."
done
mkdir -p /var/lib/nomad
{ date -Is 2>/dev/null || date; } > /var/lib/nomad/initial-password-set
