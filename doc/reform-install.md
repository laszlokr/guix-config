# Installing Guix System on the Reform's NVMe

Target: MNT Reform, Banana Pi CM4 module (Amlogic A311D, aarch64).
Starting point: MNT's Debian booted from the SD card, with Guix installed as a
foreign-distro package manager.
End state: Guix System (`hosts/reform.scm`) on the NVMe, Debian SD kept as a
working fallback.

The Reform builds this itself.  The MNT Reform kernel is fully substitutable
for aarch64, so the one thing a 4 GB A311D cannot afford — compiling a kernel
— never happens; what builds locally is this host's own service glue.  The
x86_64 box is optional and only worth setting up if `make reform/system/dry-run`
shows something expensive would be built: see
[reform-build-box.md](reform-build-box.md).

Work through this in order.  Steps 1–3 are cheap and reversible; nothing is
destroyed before step 4.

---

## 1. Record the current system

On the Reform, before changing anything:

```sh
findmnt /                       # where does Debian root live today?
cat /proc/cmdline               # note console=, root=, any extra args
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT
sudo blkid
uname -r
```

Keep this output. `/proc/cmdline` in particular tells you the console
arguments MNT's Debian boots with; if the Guix system comes up without a
console later, that is the list to compare against and add to
`#:kernel-arguments` in `hosts/reform.scm`.

## 2. Get to the U-Boot prompt and fix the boot order

U-Boot lives on the CM4 module and Guix never touches it.  Two things need
doing here, and both need the `=>` prompt.

**Reaching the prompt.**  On motherboard v3.0 and newer the serial console
comes out of the USB-C power connector: set DIP switch SW4 positions 3 and 4
ON (that routes S2) and the port appears as `ttyACM1` on the machine you
plug into.  On **v1 and v2 boards there is no USB-to-UART chip**, so wire a
3.3 V USB-to-UART adapter to header **J20 (S2)** — pin 1 `UART_TXD` to the
adapter's RX, pin 2 `UART_RXD` to its TX, pin 3 GND.  Either way:

```sh
tio /dev/ttyACM1 -b 115200      # or /dev/ttyUSB0 for a wired adapter
```

For the A311D the console is **S2 at 115200** — other modules differ, and the
RK3588 even uses a different baud rate.  Power on and press a key during the
autoboot countdown.  Use serial rather than the built-in keyboard; USB
keyboard support at the U-Boot stage is unreliable on these machines.

**Then check the NVMe and fix the order:**

```
=> printenv boot_targets
=> nvme scan
=> nvme info
=> ls nvme 0:1 /
```

On a stock 2024.04 `bpi-cm4-mnt-reform2` build the default is:

```
boot_targets=romusb mmc0 mmc1 mmc2 usb0 nvme0 pxe dhcp
```

`nvme0` is present — this U-Boot does have the full nvme command set, PCIe
enumeration and `bootcmd_nvme0` — but it sits behind every mmc target, so the
SD card wins every time.  Move it to the front, keeping the rest intact:

```
=> setenv boot_targets "nvme0 mmc0 mmc1 mmc2 usb0 romusb pxe dhcp"
=> saveenv
=> printenv boot_targets
```

Leaving the mmc targets in place is what keeps the SD card as a fallback: if
the NVMe has no bootable config, U-Boot falls through to it.

`ls nvme 0:1 /` failing at this stage is expected before step 4 — there is no
filesystem yet.  What matters is that `nvme scan` finds the drive at all.

## 3. Pull the pinned channels on the Reform

```sh
cd ~/guix-config
guix pull -C rde/channels-lock.scm -p target/profiles/guix
```

With the box authorized and in `substitute-urls` (step 5 of
reform-build-box.md) this should be mostly downloads. If it starts compiling
Guile modules locally, stop it — the box has not published the aarch64 channel
instances yet (see §7 there).

## 4. Partition and format the new NVMe — destructive from here

> Confirm the device name from step 1's `lsblk`; do not assume `nvme0n1`.
> If the old Debian drive is still in the machine, stop and swap it first —
> everything below erases the target.

Two partitions: an unencrypted root, and a LUKS container for everything
private.

```sh
sudo sgdisk --zap-all /dev/nvme0n1
sudo sgdisk -n 1:0:+120G -t 1:8300 -c 1:guix-root  /dev/nvme0n1
sudo sgdisk -n 2:0:0     -t 2:8309 -c 2:guix-crypt /dev/nvme0n1
sudo partprobe /dev/nvme0n1
```

Size p1 for the store: a desktop closure is roughly 8–10 GB, and every
generation you keep adds to it. 120 GB is generous; do not go below ~40 GB.

**No separate /boot partition, and the root is deliberately unencrypted.**
`extlinux.conf` names the kernel and initrd by absolute `/gnu/store/...`
path, and U-Boot resolves those on the partition it read the config from.
U-Boot cannot decrypt LUKS. So kernel, initrd and store must share one
partition it can read. See the header comment in `hosts/reform.scm`.

Format the root with feature flags U-Boot's ext4 driver can read — recent
`e2fsprogs` enables `metadata_csum_seed` and `orphan_file` by default and
U-Boot chokes on them:

```sh
sudo mkfs.ext4 -L guix-root -O ^metadata_csum_seed,^orphan_file /dev/nvme0n1p1
```

Now the encrypted half. LUKS2 with its default Argon2id KDF is fine here —
nothing in the boot path has to read it, only the running kernel:

```sh
sudo cryptsetup luksFormat --type luks2 /dev/nvme0n1p2
sudo cryptsetup open /dev/nvme0n1p2 reformdata-crypt

sudo pvcreate /dev/mapper/reformdata-crypt
sudo vgcreate reformdata /dev/mapper/reformdata-crypt
sudo lvcreate -L 8G  -n swap reformdata
sudo lvcreate -l 100%FREE -n home reformdata

sudo mkfs.ext4 -L guix-home /dev/mapper/reformdata-home
sudo mkswap -L guix-swap /dev/mapper/reformdata-swap
```

The VG name `reformdata` and the LV names `home`/`swap` are not cosmetic —
`hosts/reform.scm` names the resulting mappings `reformdata-home` and
`reformdata-swap`. Change one, change the other.

Then check the root from U-Boot's side before spending an hour installing
into it (reboot to the U-Boot prompt, `ls nvme 0:1 /` — an empty ext4 lists
`lost+found`).

## 5. Fill in the real UUIDs

Two of them, and they come from different devices:

```sh
sudo blkid /dev/nvme0n1p1      # ext4  -> %reform-root-uuid
sudo blkid /dev/nvme0n1p2      # crypto_LUKS -> %reform-luks-uuid
```

For the LUKS one use the UUID of the **container partition itself**, not of
the ext4 inside it. Edit `src/configs/hosts/reform.scm`:

```scheme
(define %reform-root-uuid
  (uuid "00000000-0000-0000-0000-000000000001"))   ;<- from nvme0n1p1

(define %reform-luks-uuid
  (uuid "00000000-0000-0000-0000-000000000002"))   ;<- from nvme0n1p2
```

Commit it. The placeholders evaluate and build fine — that is deliberate, so
the config can be checked before the disk exists — and `guix system init` run
as root refuses to install them (`check-file-system-availability` resolves
every UUID against real devices first), so a forgotten placeholder fails
loudly here rather than at boot.

## 6. Mount at /mnt

```sh
sudo mkdir -p /mnt
sudo mount /dev/nvme0n1p1 /mnt
sudo mkdir -p /mnt/home
sudo mount /dev/mapper/reformdata-home /mnt/home
findmnt /mnt /mnt/home
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

Check what it will do *before* committing to it:

```sh
cd ~/guix-config
make reform/system/dry-run
```

The kernel must say "would be downloaded". If it says "would be built", stop
and fix substitutes — that build does not fit on this machine. Everything
that legitimately builds here is this host's own service glue (shepherd
`.go` files, `etc`, activation scripts): Guile compilation, a few hundred
small derivations, fine on 4 GB.

Then:

```sh
make reform/system/init
```

which runs, with `ROOT_MOUNT_POINT=/mnt`:

```sh
sudo RDE_TARGET=reform-system ./pre-inst-env target/profiles/guix/bin/guix system \
     --substitute-urls='http://box.lan:3001 …' \
     init ./src/configs/configs.scm /mnt
```

Notes:

- `RDE_TARGET=reform-system` is what makes `configs.scm` return `reform-os`;
  without it you get `box-he` and the command fails.
- `./pre-inst-env` sets `GUILE_LOAD_PATH` so the `(configs …)` modules
  resolve. It runs under `sudo`, so the load path is set on the root side —
  don't try to export it beforehand, `sudo` drops it.
- Edit `REFORM_SUBSTITUTE_URLS` in the Makefile once `box.lan:3001` is real,
  or override per-invocation:
  `make reform/system/init REFORM_SUBSTITUTE_URLS=--substitute-urls='…'`.
- **Do not pass `--no-bootloader`.** There is no bootloader *installer* for
  this host, but that flag also skips writing `/mnt/boot/extlinux/extlinux.conf`,
  which is the one thing that has to happen.
- **Do not `make cow-store` first.** See step 6.

### If it stops on initrd modules

`guix system init` runs two checks as root that never fire on the box.
`check-file-system-availability` catches a forgotten placeholder UUID
(step 5). The other, `check-device-initrd-modules`, is the one that can
mislead you:

```
you may need these modules in the initrd for /dev/nvme0n1p1: …
```

It walks the sysfs chain of the device **on the running Debian**, so the
names it suggests come from *Debian's* kernel. They are not necessarily
module names in the Guix MNT Reform kernel — that kernel has much of this
built in, and naming a built-in module makes the initrd build fail with
`kernel module not found`. So do not paste the suggestions into
`initrd-modules` reflexively.

Check first whether the Guix kernel actually ships it as a module:

```sh
find $(guix build -e '(@ (gnu packages linux) linux-libre-arm64-mnt-reform)') \
     -name '<module>.ko*'
```

If it does, add it to `%reform-initrd-modules` in `hosts/reform.scm`. If it
does not, the module is built in and the check is wrong for this kernel —
re-run with `--skip-checks` (the error message says so itself):

```sh
make reform/system/init REFORM_EXTRA_OPTIONS=--skip-checks
```

`--skip-checks` disables the file-system availability check too, so only
reach for it once you have confirmed the root UUID is real.

Afterwards, sanity-check what it wrote:

```sh
sudo cat /mnt/boot/extlinux/extlinux.conf
```

It should look like this (verified by generating it on the build host):

```
UI menu.c32
MENU TITLE GNU Guix Boot Options
PROMPT 1
TIMEOUT 30
LABEL GNU with Linux-Libre-Arm64-Mnt-Reform 7.0.14
  KERNEL /gnu/store/...-linux-libre-arm64-mnt-reform-7.0.14/Image
  FDTDIR /gnu/store/...-linux-libre-arm64-mnt-reform-7.0.14/lib/dtbs
  INITRD /gnu/store/...-raw-initrd/initrd.cpio.gz
  APPEND root=<your root UUID> gnu.system=/gnu/store/...-system \
         gnu.load=/gnu/store/...-system/boot console=ttyAML0,115200 ... quiet
```

Check three things:

- `root=` carries **your** UUID, not the placeholder.  (Note the spelling:
  Guix emits a bare `root=<uuid>`, not `--root=UUID=...`.)
- `KERNEL` and `INITRD` are absolute store paths — and they must exist under
  `/mnt`, because U-Boot resolves them on this same partition:

  ```sh
  sudo ls -l /mnt$(awk '/KERNEL/ {print $2}' /mnt/boot/extlinux/extlinux.conf | head -1)
  sudo ls -l /mnt$(awk '/INITRD/ {print $2}' /mnt/boot/extlinux/extlinux.conf | head -1)
  ```

- `TIMEOUT 30` means three seconds, not thirty — the unit is tenths.

`UI menu.c32` refers to a syslinux module that will not be present, because
this host installs no bootloader code.  That is expected and harmless: every
upstream Guix ARM image generates the same line, and U-Boot ignores it.

If the first boot is opaque, drop `quiet` from the kernel arguments — it comes
from rde's defaults and hides exactly the messages you want when a LUKS prompt
or a root-device failure is the thing you are diagnosing.

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
     --substitute-urls='http://box.lan:3001 …' \
     src/configs/configs.scm
```

Rolling back a bad generation is a U-Boot-menu affair here rather than a GRUB
menu: `extlinux.conf` carries the previous generations as extra `LABEL`
entries, and U-Boot's `sysboot` shows them with `MENU`/`TIMEOUT 3`.
