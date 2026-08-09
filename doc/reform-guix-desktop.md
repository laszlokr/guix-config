# A Guix desktop on the MNT Reform (A311D): how we got here

This is the story of turning an MNT Reform's Debian-on-SD-card default into a
full Guix System on NVMe, running the same rde-based config as `box`. It
exists as a single narrative for future reference — the step-by-step
checklists it summarizes live in [reform-build-box.md](reform-build-box.md)
(serving builds from `box`) and [reform-install.md](reform-install.md) (the
`guix system init` procedure itself). Read this first for the *why*; read
those when you're about to actually run a command.

The machine: a Banana Pi CM4 module (Amlogic A311D, aarch64) in an MNT Reform
chassis, 4 GB RAM, no swap until we made some. That RAM ceiling is the thread
running through almost every decision below.

## The starting point

MNT ships the Reform with Debian on the SD card and Guix installed on top of
it as a foreign-distro package manager — `guix home` works from day one, but
there is no `operating-system` and no `guix system` anything. The goal was
Guix System proper, on the NVMe, with the SD card kept as a fallback boot
path forever.

Two hard constraints shaped everything:

- **The A311D cannot build a kernel, and shouldn't build much else either.**
  4 GB is enough to run a desktop, not to compile one.
- **U-Boot cannot decrypt LUKS**, and `extlinux.conf` names the kernel and
  initrd by absolute `/gnu/store/...` path on whatever partition U-Boot read
  the config from. So the store has to live somewhere U-Boot can read
  unencrypted — which is why root is a plain unencrypted ext4 partition, and
  only `/home` and swap sit behind LUKS+LVM. See the header comment in
  `hosts/reform.scm` for the full reasoning.

## Making `box` build for it

Since the Reform mostly can't build things itself, `box` (x86_64, full Guix
System, already running this config) became the build farm. The full
mechanics are in reform-build-box.md; the two things worth knowing without
reading that whole document:

1. **Cross-built store items are useless to the Reform.** `--target=aarch64-linux-gnu`
   and `--system=aarch64-linux` produce different derivations for the same
   package — the Reform's own `guix system init` only ever asks for the
   `--system=` hashes. Cross builds are good for a fast structural check
   (catch a wrong module import in seconds) and nothing else; the ones that
   matter run under QEMU binfmt on `box` (`--system=aarch64-linux`), slower
   but producing real substitutes.
2. **Measure before assuming a build is expensive.** `guix weather` showed
   the MNT Reform kernel itself is 100% substitutable for aarch64 — the one
   item everyone assumes is the killer download is actually a 31 MB fetch.
   The things that turned out to be genuinely unbuildable on aarch64 were
   different packages entirely (below).

`box` runs `guix publish` as a system service, the Reform's foreign-distro
`guix-daemon` gets a `systemctl edit` drop-in pointing `--substitute-urls` at
it, and the box's signing key gets into the Reform's `/etc/guix/acl`. After
that, `guix pull` and `guix system reconfigure` on the Reform are mostly
downloads from the LAN instead of hours of emulated compiling.

## Installing

Following reform-install.md end to end, in brief: reach the U-Boot prompt
over serial (S2 header, 115200 baud — on v1/v2 boards this needs a wired
3.3V USB-UART adapter, since there's no onboard USB-to-UART chip before
motherboard v3), reorder `boot_targets` so `nvme0` beats the SD card while
leaving the SD as a fallback, partition the NVMe (unencrypted root +
LUKS/LVM for home and swap), fill in the real UUIDs, mount at `/mnt`, and run
`guix system init` — `RDE_TARGET=reform-system` selects `reform-os` out of
`configs.scm`.

Three sharp edges got caught before or during first boot, all worth
recording because none of them would show up in a dry-run:

- **Kernel console ordering.** MNT's own `flash-kernel` config for this
  board carries a comment: `console=tty1` has to go *last* in the kernel
  command line, because "the luks passphrase prompt will show up on the last
  console which must not be the serial terminal." The Reform's kernel
  arguments had `console=ttyAML0` and `console=tty1` in the wrong relative
  order — a transcription slip from an earlier draft — which would have sent
  the `/home` LUKS prompt to the serial line, unusable without a UART cable
  plugged in. Fixed by re-reading `flash-kernel`'s own snippet
  (`/usr/share/flash-kernel/ubootenv.d/00reform2_ubootenv`) and matching its
  order exactly.
- **The graphical login died silently.** Every greetd/sway session failed
  immediately with `dbus-run-session: failed to execute message bus daemon
  'dbus-daemon': No such file or directory`. rde's greetd session wraps sway
  as `dbus-run-session ... -- sway`; `dbus-run-session` itself resolves by
  absolute store path, but it spawns the *session* bus by searching plain
  `$PATH` for the bare name `dbus-daemon` — nothing had put dbus's `bin/` on
  the system PATH. The system dbus service was unaffected (it references the
  package directly, no `$PATH` involved), which is exactly why networking
  and PolicyKit worked while every login attempt died. Fixed with a
  `simple-service` extending `profile-service-type` to put dbus on
  `/run/current-system/profile/bin`. Diagnosed from a video of the console —
  greetd re-grabs the VT in under a second, so the error flashes and is easy
  to miss entirely.
- **Placeholder UUIDs.** `hosts/reform.scm` ships with dummy UUIDs so the
  config parses and builds before the disk exists; `guix system init`
  refuses to install them for real (`check-file-system-availability`
  resolves every UUID against a real device first), so a forgotten
  placeholder fails loudly at install time rather than quietly at boot.

## Trimming the desktop to fit 4 GB and aarch64's substitute gaps

`box`'s full home/system config is not what ended up on the Reform. A
package-by-package `guix weather --system=aarch64-linux` sweep of the
resolved profile — not just what's named in `laszlokr.scm`, the full 275+
package closure — turned up several packages that are either impossible to
build for aarch64 or realistic OOM-kill candidates on 4 GB:

| Package/feature | Problem | Resolution |
| --- | --- | --- |
| `feature-qemu` (libvirt VM firmware) | `ovmf-x86-64` is hardcoded into `libvirt-service-type`'s default firmware list; EDK2 then compiles X64-only code with the native aarch64 gcc and dies on `-m64`/`-mno-red-zone`. Pointing it at `ovmf-aarch64` doesn't help — libvirt unions `<pkg>/share/qemu/firmware` and only `ovmf-x86-64` installs that directory. | Dropped entirely — a 4 GB machine isn't running VMs anyway. |
| `ungoogled-chromium` | 0% aarch64 substitute coverage on bordeaux; `guix home reconfigure` silently started compiling it from source, a many-hour build very likely to be OOM-killed first. | Dropped. `librewolf` (100% substitutable, already in rde-desktop) stays as the browser. |
| `firefox` | Same story — nongnu's package is a real source compile, 0% aarch64 substrate. | Dropped, for the same reason `librewolf` already covers it. |
| `libreoffice` | 0% aarch64 substrate, and one of the largest builds in the entire package set even when it *does* build. | Dropped; replaced with `abiword` + `gnumeric` (100% substitutable), covering word processing and spreadsheets without the build cost. |
| `openscad` | 0% aarch64 substrate, fails to build from source on this host. `kicad`, listed right next to it, is 100% substitutable and unaffected. | Dropped from the home profile only. |
| `feature-guile` (guile-ares-rs) | Not a substitute-coverage problem — a real, architecture-specific dependency conflict. `gnu/packages/admin.scm` deliberately pins `shepherd` to `guile-fibers@1.1.1` on ARM/RISC-V (a workaround for a real-time-clock issue on SBCs), while `guile-ares-rs` propagates the latest `guile-fibers@1.4.3`. Both land in the same home profile → "conflicting entries for guile-fibers." x86_64 doesn't hit this because both packages get the latest fibers there. | Dropped on reform only; costs the Guile nREPL workflow (`emacs-arei`) on this host. Guile itself is untouched. |

The `openscad` removal needed a different mechanism than everything else:
it's contributed to `home-profile-service-type` by a `simple-service` from
the *shared* `users/laszlokr.scm`, and that service type is only ever
instantiated once — every package-list contributor extending it, including
this one, is a separate anonymous service, so `modify-services` has nothing
named to target. `reform-home-environment` instead walks every user service
whose type extends `home-profile-service-type` and filters the unwanted
package out of its value by name, wherever it came from.

Two channel-plumbing bugs surfaced during this same stretch of work, both
now fixed for every host, not just the Reform:

- **The lock file was silently un-pinning itself.** `profiles.mk` had
  `rde/channels-lock.scm: rde/channels.scm` as a make prerequisite, which
  regenerates the lock from the *unpinned* channel list on any checkout
  where `channels.scm` happens to look newer — quietly pulling whatever
  `master` was that day instead of the pinned commits. This is what caused
  the guile-fibers conflict above to appear intermittently and look like a
  config bug rather than a pinning bug: it reproduces on current master, not
  at the actually-pinned commit.
- **`guix pull` rejected the channel files outright**, with `use-modules:
  unbound variable`. Current guix evaluates channel files in a sandbox that
  only exposes `%safe-channel-bindings` — `channel`, `channel-name`, and so
  on are pre-injected, and `use-modules` is deliberately not available.  A
  `(use-modules (guix channels))` header that used to be harmless is now
  fatal. Removed from all three channel files, and from the Makefile rule
  that regenerates them (which was re-emitting the same header every time).

## The `emacs-feature-loader` saga

This is the part worth telling in full, because the same underlying failure
was "fixed" three times before the actual bug was found, and each wrong fix
looked completely clean from the outside.

**Act 1 — the build crash.** rde generates one package,
`emacs-feature-loader`, whose `feature-loader.el` has a top-level
`;;;###autoload` cookie on a call to `(feature-loader)`. Autoload cookies get
copied verbatim into the package's generated `*-autoloads.el`, and Emacs's
`elisp-configuration-package` build system has a `validate-compiled-autoloads`
phase that loads that autoloads file in an isolated batch Emacs — whose load
path is *only that one package's own inputs* — to sanity-check it. Loading it
there executes `(feature-loader)` for real, which tries to require every
rde-* feature file, several of which need things outside that narrow load
path. Build failure. The first fix stripped every `;;;###autoload` cookie
from the generated source so the call would never appear in the autoloads
file at all. It built. It shipped.

**Act 2 — "upstream fixed it."** rde landed a real fix for the same crash
upstream. Channels were bumped past that commit and the local workaround was
deleted, on the reasoning that the underlying bug was gone. It was — for a
while, and then a later channel bump reintroduced the same class of build
failure, and the same cookie-stripping fix went back in, unremarked, as
routine maintenance.

**Act 3 — this session.** With the Reform up, the running config was checked
against what it was supposed to be doing, and it wasn't: evil-mode, vertico,
consult, `rde-appearance` — every single rde-configured feature was inert in
a live Emacs daemon, with `init.el` unchanged and *no errors anywhere*. The
autoload cookie is not just what triggered the build-time crash — it's the
*only* mechanism that makes rde's per-feature elisp self-activate at real
startup via Emacs's normal package-autoloads loading. Stripping it had fixed
the build by silently disabling every feature it was supposed to load,
system-wide, with nothing anywhere reporting failure. "Builds clean" and
"works" had quietly stopped being the same claim.

The actual fix: leave the autoload cookie alone, and instead skip just the
`validate-compiled-autoloads` phase — a load-only sanity check with no build
output of its own, so nothing is lost by not running it in an
unrepresentatively narrow environment. Verified by building
`emacs-feature-loader` directly and confirming the generated
`*-autoloads.el` still carries the real `(feature-loader)` call.

That surfaced a second, genuinely separate bug, previously invisible because
nothing had ever actually run rde's autoloaded activation code end to end.
`rde-modus-themes.el` installs `(advice-add 'enable-theme :after
'rde-modus-themes-run-after-enable-theme-hook)` unconditionally and
immediately at load time, but only loads the actual `modus-themes` library
— which defines the function that advice calls,
`modus-themes-get-current-theme` — via a `load-theme` deferred to
`after-init-hook`. `rde-fonts.el` *also* defers its own
`enable-theme`-triggering call (`fontaine-set-preset`) to the same hook.
Emacs's `add-hook` prepends by default, and `feature-loader` requires
`rde-fonts` after `rde-modus-themes`, so fontaine's hook entry ends up
running *first* — triggering the advice before `modus-themes` itself has
ever loaded. Result: `Symbol's function definition is void:
modus-themes-get-current-theme`, live, on every real startup, invisible in
any build-time check because the build environment never has both features
on the same load path to race in the first place.

Fixed by making `feature-loader.el` eagerly `(require 'modus-themes)` as the
literal first thing it does, before any per-feature `require` or
`add-hook` call runs. `modus-themes` is already on `feature-loader`'s load
path — it's a propagated input of the `rde-modus-themes` feature entry,
which `feature-loader`'s own propagated inputs are a union over — so this
only changes *when* it loads, not whether. Confirmed live on the Reform: the
theme system, evil-mode, vertico and the rest of rde's feature set all
activate correctly on a real login.

**The lesson underneath all three acts:** a batch-Emacs build-time check and
a real interactive session with the full profile loaded together are not the
same environment, and a fix that makes the narrower one pass can easily make
the wider one silently worse. The build going green was never sufficient
evidence that the config was doing what it claimed to.

**Postscript.** The `configs/patches.scm` mechanism above (a load-time patch
to `elisp-configuration-package` itself) turned out to be solving half of
this with more machinery than necessary. A separate, parallel branch had
independently hit and diagnosed the *exact same* modus-themes race — before
this account of it existed — and fixed the build-time half of the problem
through rde's own supported knobs instead: `home-emacs-feature-loader-service-type`
already takes `autoloads?` and `add-to-init-el?`, and setting `autoloads? #f`
/ `add-to-init-el? #t` gets the same "package builds, feature-loader still
gets called at real startup" outcome without ever needing a custom package
patch. The modus-themes ordering fix moved with it, from a `substitute*` over
generated `.el` files in `patches.scm` to a plain `(require 'modus-themes)`
ahead of `(require 'feature-loader)` in `init.el` (`users/laszlokr.scm`).
Once both branches were reconciled, `patches.scm` was deleted outright — see
`configs/configs.scm`'s `fix-feature-loader` for what replaced it. Same fix,
fewer moving parts, and it now lives in a file shared by every host instead
of one bolted onto Emacs's own build system.

## Where things stand

The Reform boots Guix System from NVMe, with Debian on the SD card as a
permanent fallback. `box` publishes substitutes over the LAN so `guix pull`
and reconfigures on the Reform are mostly downloads. The desktop is rde's
usual sway + Emacs setup, with `librewolf` in place of chromium/firefox and
`abiword`/`gnumeric` in place of libreoffice, and the Guile nREPL workflow
sacrificed to an ARM-specific `guile-fibers` version conflict. rde's actual
feature activation — evil, vertico, themes, all of it — works correctly at
real startup, which took three separate fixes across two sessions (and a
later reconciliation with parallel work that had fixed half of it a cleaner
way) to actually confirm rather than assume.

Since then: the onboard Wi-Fi (Realtek RTL8822CS) got its missing `rtw88`
kernel driver turned on via a `customize-linux` variant, a known firmware
low-power-state bug got a NetworkManager powersave-disable workaround, and
`sing-box` (via the `rosenthal` channel, not upstream guix/nonguix) is wired
up on both `box` and the Reform for the same VPN config.

What's next for this machine is tracked in the README's planned-improvements
list: mail via mu4e, a system-wide Catppuccin light/dark toggle, a real
answer for LibreOffice-class apps on aarch64 (an ARM build farm of its own is
one option), and a more compact/reliable Wi-Fi dongle if the driver fix and
powersave workaround together still aren't enough.
