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
   `grub.cfg` and install its own GRUB.

   **This is the step that has already broken this machine once.** A
   reconfigure with guix's bootloader install left box at a `grub rescue`
   prompt, and recovery took USB rescue media plus a manual `grub-install`
   with explicit `--modules`. Guix's EFI installer *does* set
   `GRUB_ENABLE_CRYPTODISK=y` itself (see `install-grub-efi` in
   `gnu/bootloader/grub.scm`), so on paper it should carry the cryptodisk
   modules — but the observed behaviour on this hardware says otherwise, and
   the observation wins. Expect the binary guix installs here to be
   unbootable, and treat step 3 as mandatory, not belt-and-braces:

   ```sh
   sudo -E guix system reconfigure -L ./src src/configs/configs.scm
   ```

   (using `RDE_TARGET=box-system` as the Makefile targets do)

3. **Immediately** re-install the GRUB binary with the modules named
   explicitly — before rebooting, in the same sitting. This overwrites only
   the EFI binary; the `grub.cfg` from step 2 stays. This is the same command
   that recovered the machine from USB last time, so it is known to produce a
   bootable binary here:

   ```sh
   sudo make box/system/install-bootloader
   ```

   The previous grub-rescue incident happened because the machine was
   rebooted between steps 2 and 3. Do not reboot in that window.

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

## Run log

**2026-08-12** — ran successfully, first time. `guix system reconfigure`
without `--no-bootloader`, then `sudo make box/system/install-bootloader`
immediately after with no reboot in the window. `grub-install` reported
"Installation finished. No error reported." Verification passed: the default
menu entry's `gnu.system=/gnu/store/91r9ivkvpv3bz94cbha1r5xx1qizp5zg-system`
matched generation 22's canonical path exactly, and the menu went from 13
entries (newest May, kernel 6.18.28) to 23, closing a three-month gap. The
procedure below works as written; the earlier grub-rescue incident really was
caused by rebooting between the two steps.

## Keeping it from drifting again

Given the confirmed grub-rescue incident, `--no-bootloader` stays on
`box/system/reconfigure` — it is load-bearing, not cruft.

That makes "reconfigure normally, then immediately repair the binary" the
standing procedure whenever you want the menu to catch up to reality, rather
than something to do only in emergencies. It is worth running after any batch
of changes you actually want to be able to boot into — otherwise the gap just
grows again, silently, exactly as it did between May and August.

The properly declarative fix would be to make guix's own bootloader install
carry the cryptodisk modules, so no manual repair step is needed. Guix's
`bootloader-configuration` has no field for extra `grub-install` modules, so
that likely means a custom `<bootloader>` record wrapping
`grub-efi-removable-bootloader` with its own installer gexp. Real work, not
attempted yet — but it is the thing that would actually retire this document.

Until then: assume the menu is stale, and never reboot `box` casually.
