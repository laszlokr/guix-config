# Installing Guix System on the Reform's NVMe

Target: MNT Reform, Banana Pi CM4 module (Amlogic A311D, aarch64).
Starting point: MNT's Debian booted from the SD card, with Guix installed as a
foreign-distro package manager.
End state: Guix System (`hosts/reform.scm`) on the NVMe, Debian SD kept as a
working fallback.

Everything is built on the x86_64 box and downloaded — see
[reform-build-box.md](reform-build-box.md).  Set that up first; the Reform
cannot build its own kernel.

Work through this in order.  Steps 1–3 are cheap and reversible; nothing is
destroyed before step 4.

---

## 1. Record the current system

On the Reform, before changing anything:

```sh
findmnt /                       # expect the SD card (/dev/mmcblk*)
cat /proc/cmdline               # note console=, root=, any extra args
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT
sudo blkid
uname -r
```

Keep this output. `/proc/cmdline` in particular tells you the console
arguments MNT's Debian boots with; if the Guix system comes up without a
console later, that is the list to compare against and add to
`#:kernel-arguments` in `hosts/reform.scm`.

## 2. Confirm U-Boot can actually boot the NVMe

**This is the prerequisite the whole plan rests on.** U-Boot lives on the CM4
module and Guix never touches it. If it cannot see the NVMe, an installed Guix
System on the NVMe will simply never boot.

Reboot, interrupt U-Boot at the serial/console prompt, and check:

```
=> printenv boot_targets
=> nvme scan
=> nvme info
=> ls nvme 0:1 /
```

`ls` must list the partition's contents. If `nvme` is not in `boot_targets`,
put it first, keeping every entry that is already there:

```
=> setenv boot_targets "nvme0 <the rest of the existing list, unchanged>"
=> saveenv
=> printenv boot_targets
```

Order matters: with `mmc` first, the module keeps booting the Debian SD card
and you will think the install failed when it merely was not tried.

If U-Boot on your module has no NVMe support at all, stop here — none of the
rest applies, and the layout would have to change (Guix root on SD/eMMC
instead). Ask before improvising.

## 3. Pull the pinned channels on the Reform

```sh
cd ~/guix-config
guix pull -C rde/channels-lock.scm -p target/profiles/guix
```

With the box authorized and in `substitute-urls` (step 5 of
reform-build-box.md) this should be mostly downloads. If it starts compiling
Guile modules locally, stop it — the box has not published the aarch64 channel
instances yet (see §7 there).

## 4. Partition and format the NVMe — destructive from here

> Everything on `/dev/nvme0n1` is erased. Confirm the device name from step 1's
> `lsblk` output; do not assume it.

One partition, GPT, whole disk:

```sh
sudo sgdisk --zap-all /dev/nvme0n1
sudo sgdisk -n 1:0:0 -t 1:8300 -c 1:guix-root /dev/nvme0n1
sudo partprobe /dev/nvme0n1
```

**No separate /boot partition.** `extlinux.conf` refers to the kernel and
initrd by absolute `/gnu/store/...` path, and U-Boot resolves those paths on
the same partition it read `extlinux.conf` from. A separate /boot would send
U-Boot looking for `/gnu/store` on a partition that does not have it.

Format with feature flags U-Boot's ext4 driver can read — recent `e2fsprogs`
enables `metadata_csum_seed` and `orphan_file` by default and U-Boot chokes on
them:

```sh
sudo mkfs.ext4 -L guix-root -O ^metadata_csum_seed,^orphan_file /dev/nvme0n1p1
```

Then check it from U-Boot's side before spending an hour installing into it
(reboot to the U-Boot prompt, `ls nvme 0:1 /` — an empty ext4 lists
`lost+found`).

## 5. Fill in the real UUID

```sh
sudo blkid /dev/nvme0n1p1
```

Edit `src/configs/hosts/reform.scm` and replace the placeholder in
`%reform-root-uuid`:

```scheme
(define %reform-root-uuid
  (uuid "00000000-0000-0000-0000-000000000001"))   ;<- the UUID from blkid
```

Commit it. The placeholder evaluates and builds fine — that is deliberate, so
the config can be checked on the box — and `guix system init` run as root
refuses to install it (`check-file-system-availability` resolves every UUID
against real devices first), so a forgotten placeholder fails loudly here
rather than at boot.

## 6. Mount at /mnt

```sh
sudo mkdir -p /mnt
sudo mount /dev/nvme0n1p1 /mnt
findmnt /mnt
```

**Do not start `cow-store`.** `herd start cow-store /mnt` belongs to the Guix
*installer image*, where the root filesystem is a read-only squashfs in RAM and
the store has to be overlaid onto the target disk. This is a normal writable
Debian root: `/gnu/store` is a real directory on the SD card, `guix system
init` populates it there and then copies the closure to `/mnt/gnu/store`.
There is no shepherd on Debian for the command to talk to anyway. The repo's
`make cow-store` target is for installer media — not for this.

Check there is room on **both** sides — the store on the SD, and /mnt:

```sh
df -h /gnu/store /mnt
```

Several GB each for a desktop closure. If the SD is tight, garbage-collect
(`sudo guix gc -F 5G`) before starting.

## 7. `guix system init`

```sh
cd ~/guix-config
sudo RDE_TARGET=reform-system \
     GUILE_LOAD_PATH="$PWD/src" \
     ./target/profiles/guix/bin/guix system init \
     --substitute-urls='http://box.lan:3000 https://ci.guix.gnu.org https://bordeaux.guix.gnu.org https://substitutes.nonguix.org' \
     src/configs/configs.scm /mnt
```

Notes:

- `RDE_TARGET=reform-system` is what makes `configs.scm` return `reform-os`;
  without it you get `box-he` and the command fails.
- `GUILE_LOAD_PATH="$PWD/src"` is what `./pre-inst-env` does — needed for the
  `(configs …)` modules to resolve. `sudo` drops the environment, so both are
  set on the `sudo` line rather than exported.
- Put the box first in `--substitute-urls` so it is preferred.
- **Do not pass `--no-bootloader`.** There is no bootloader *installer* for
  this host, but that flag also skips writing `/mnt/boot/extlinux/extlinux.conf`,
  which is the one thing that has to happen.
- Expect downloads, not builds. If it starts building the kernel, kill it: the
  box has not published what this machine is asking for, and the A311D does not
  have the RAM to finish.

Afterwards, sanity-check what it wrote:

```sh
sudo cat /mnt/boot/extlinux/extlinux.conf
```

You should see `LABEL`, a `KERNEL /gnu/store/…-linux-libre-arm64-mnt-reform-…/Image`,
`FDTDIR …/lib/dtbs`, `INITRD …`, and an `APPEND` line with
`--root=UUID=<your UUID>`. Confirm the store paths under `/mnt/gnu/store`
exist:

```sh
sudo ls -d /mnt$(awk '/KERNEL/ {print $2}' /mnt/boot/extlinux/extlinux.conf | head -1 | xargs dirname)
```

## 8. First boot — SD card stays in

Reboot with the SD card still inserted. U-Boot should try `nvme0` first
(step 2) and fall back to the SD if the NVMe boot fails, which is exactly the
safety net you want.

On the machine that comes up:

```sh
findmnt /                  # /dev/nvme0n1p1, type ext4 — NOT mmcblk
cat /proc/cmdline          # --root=UUID=<your UUID>, init=/gnu/store/…-system/boot
uname -a                   # …-arm64-mnt-reform
```

If `findmnt /` still shows the SD, you booted Debian again: re-check
`boot_targets` order in U-Boot, and that `extlinux.conf` landed on the NVMe.

Log in as `laszlokr` with the initial password hashed in
`users/laszlokr.scm`, and change it (`passwd`) before anything else.

## 9. Keep the SD card

- **Never pull the SD while the Reform is running** — it hard-powers-off.
- Leave the Debian SD in place as the fallback boot path indefinitely. It costs
  nothing and it is the only way back in if a Guix generation fails to boot.
- Do not reformat or reuse it until the NVMe system has survived several
  reboots *and* a `guix system reconfigure`.
- To get back to Debian deliberately: at the U-Boot prompt, boot the mmc target
  directly (`run bootcmd_mmc1` / whatever step 2 showed), without touching the
  saved `boot_targets`.

## 10. Afterwards

Reconfigure from the Reform, still fetching everything from the box:

```sh
cd ~/guix-config
sudo RDE_TARGET=reform-system GUILE_LOAD_PATH="$PWD/src" \
     ./target/profiles/guix/bin/guix system reconfigure \
     --substitute-urls='http://box.lan:3000 …' \
     src/configs/configs.scm
```

Rolling back a bad generation is a U-Boot-menu affair here rather than a GRUB
menu: `extlinux.conf` carries the previous generations as extra `LABEL`
entries, and U-Boot's `sysboot` shows them with `MENU`/`TIMEOUT 3`.
