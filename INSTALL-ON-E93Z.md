# First boot: audit the E93z before installing

**Do not choose the N.O.M.A.D. Automated install entry on the first boot.** The first session is for identification only.

1. Write the verified ISO to a spare USB stick with Rufus. This erases that USB stick. Do not use your external data HDD as the installer stick unless you intend to erase it.
2. Connect the installer stick to a known-good USB port on the E93z. Avoid the physically damaged port.
3. Start the E93z and open its one-time boot menu. Choose the USB device. If the boot menu key is unclear, check the on-screen prompt during startup rather than guessing.
4. At the Debian boot menu, choose the ordinary **Install** entry, not the N.O.M.A.D. Automated install entry. This starts the normal interactive Debian Installer. Do not proceed to partitioning.
5. Once the installer screen appears, press **Ctrl+Alt+F2** to open its shell. If that key combination is intercepted by the computer, try **Alt+F2**.
6. At the shell prompt, run:

   ```sh
   sh /cdrom/nomad/nomad-audit-installer.sh /tmp/NOMAD-E93z-audit.txt
   ```

7. The report is printed on screen and saved in the installer’s temporary memory at `/tmp/NOMAD-E93z-audit.txt`. Photograph the report or copy it to a separate writable USB drive. Do not save it to the E93z internal disk.
8. Return to the installer with **Ctrl+Alt+F1**, then power off or reboot. Do not start installation yet.

The audit records the exact Lenovo/BIOS identity, firmware mode, CPU and memory, PCI hardware IDs (including the Wi-Fi adapter and graphics), USB devices, and storage model/serial/capacity/partitions. It does not partition, format, or write to any disk.

After the report is reviewed, the next step is to confirm the internal drive’s identity and condition, then decide whether the automated installation is appropriate. The install approval screen is a separate destructive step and requires the exact phrase `ERASE AND INSTALL NOMAD`.
