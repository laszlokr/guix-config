# box's bootloader: why the menu goes stale, and how to refresh it safely

## The situation

`box/system/reconfigure` passes `--no-bootloader`. That was added deliberately
in commit `7b74d0b` (2026-05-16) because guix's own bootloader install was
reported to drop the cryptodisk modules this LUKS-encrypted root needs,
breaking boot.

The cost of that flag is larger than it looks. `guix`'s install-bootloader
step does **two** things (see `install-bootloader-program` in
`guix/scripts/system/reconfigure.scm`):

1. `install-boot-config` — writes `/boot/grub/grub.cfg`, i.e. **the menu
   entries**, including which generation boots by default.
2. the bootloader installer — writes the GRUB EFI binary.

`--no-bootloader` skips **both**. Meanwhile `make box/system/install-bootloader`
only ever did (2). So nothing in the normal workflow updates the menu at all.

`switch-to-system` (which always runs on reconfigure) updates
`/var/guix/profiles/system` and runs the activation script, so reconfigures
*do* take effect on the live, running system immediately. But each GRUB menu
entry points at a specific frozen generation — so on the next boot you land on
whatever generation `grub.cfg` last recorded, not what you have been running.

Confirmed on 2026-08-12: the live system was generation 14 (kernel 7.0.14,
Aug 02) while `grub.cfg`'s newest entry was kernel 6.18.28 from mid-May. A
reboot at that point would have silently come back three months out of date.

Compounding it, `box/system/install-bootloader` had never once succeeded since
it was written: it used `$(find ...)` in a make recipe, which *make* expands
(no such make function) rather than the shell, so the recipe began with
`--target=x86_64-efi` and always died with "command not found". Fixed since,
along with adding `--removable` to match box's configured
`grub-efi-removable-bootloader` — without it grub-install writes `EFI/Guix`
plus an NVRAM entry instead of the `EFI/BOOT/BOOTX64.EFI` path the firmware
actually boots.

## Refreshing the menu — the part that carries real risk

There is no way to regenerate `grub.cfg` without letting guix run its
bootloader step. The safe sequence is to let guix do both halves, then
immediately re-install the GRUB binary by hand with explicit cryptodisk
modules, since `grub-install` does not touch `grub.cfg`.

**Have working rescue media to hand before starting.** This is the one
procedure here that can leave the machine unbootable.

1. Back up what currently works, so there is something to restore from:

   ```sh
   sudo cp -a /boot/grub/grub.cfg /boot/grub/grub.cfg.bak
   sudo cp -a /boot/efi/EFI /boot/efi/EFI.bak
   ```

2. Reconfigure *without* `--no-bootloader`, letting guix write a current
   `grub.cfg` and install its own GRUB. Note guix's EFI installer does set
   `GRUB_ENABLE_CRYPTODISK=y` itself (see `install-grub-efi` in
   `gnu/bootloader/grub.scm`), which is what should pull in the cryptodisk
   modules — so the May failure may already be moot, but do not assume it:

   ```sh
   sudo -E guix system reconfigure -L ./src src/configs/configs.scm
   ```

   (using `RDE_TARGET=box-system` as the Makefile targets do)

3. Immediately re-install the GRUB binary with the modules named explicitly.
   This overwrites only the EFI binary; the `grub.cfg` from step 2 stays:

   ```sh
   sudo make box/system/install-bootloader
   ```

4. **Verify before rebooting.** The menu should now list the current
   generation's kernel:

   ```sh
   grep -c menuentry /boot/grub/grub.cfg
   grep -A5 'menuentry "GNU with Linux' /boot/grub/grub.cfg | head -20
   sudo guix system list-generations | tail -30
   ```

   Cross-check the kernel store path in the newest menu entry against the
   current generation's. If they match, the gap is closed.

5. Reboot only once step 4 checks out, and only with rescue media available.

If it fails to boot: from rescue media, mount the ESP and restore
`/boot/efi/EFI.bak` over `/boot/efi/EFI`, and `grub.cfg.bak` over
`grub.cfg`. That returns you to the previously-working (if stale) state.

## Keeping it from drifting again

Whichever way step 2 turns out, decide explicitly:

- If guix's own installer works fine now (likely, given it sets
  `GRUB_ENABLE_CRYPTODISK=y`), **drop `--no-bootloader` from
  `box/system/reconfigure`** so the menu simply stays current, and keep
  `box/system/install-bootloader` only as a recovery tool.
- If it genuinely still breaks boot, keep the flag, but treat
  "reconfigure normally, then repair the binary" as the standing procedure
  after any batch of changes worth being able to boot into — and record
  *why* here, with the actual failure, rather than leaving it implicit.

Until that decision is made, assume the menu is stale and never reboot `box`
casually.
