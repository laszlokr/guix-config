# Serving the Reform from the x86_64 box

How to make `box` (x86_64, full Guix System) the place where everything for
`reform` (MNT Reform, Banana Pi CM4 / Amlogic A311D, aarch64) gets built, so
the Reform only ever *downloads*.  The A311D module does not have the RAM to
build a kernel.

Nothing in this document has been run against either machine.  Every command
is written to be executed by you, on the machine named in its heading.

---

## 0. The thing to understand before anything else

**Cross-built store items cannot be served to the Reform.**

`guix build --target=aarch64-linux-gnu foo` and `guix build
--system=aarch64-linux foo` produce two *different derivations* with different
store hashes, even though both yield an aarch64 binary.  The cross build's
inputs include an x86_64-hosted cross toolchain; the native build's do not.

When the Reform runs `guix system init`, it computes native aarch64
derivations and asks substitute servers for *those* hashes.  A store full of
cross-built results is a store full of items it will never ask for.

So:

| purpose | how to build |
| --- | --- |
| check the config is sane, catch aarch64 breakage early | `--target=aarch64-linux-gnu` (cross) |
| produce store items the Reform will actually fetch | `--system=aarch64-linux` (native, under QEMU binfmt) |

Both are wired up in the Makefile (`make reform/system/cross-build`,
`make reform/system/native-build`).

All of the below was measured at the channels pinned in
`rde/channels-lock.scm` (guix 8db8515, rde 70a1881, nonguix 3b66965) on an
x86_64 host with qemu-aarch64 binfmt. `reform-system` builds to completion
that way — `guix system build --system=aarch64-linux --cores=1` produced a
system derivation with the MNT Reform kernel and the extlinux bootloader
configuration.

```
guix build -d --target=aarch64-linux-gnu hello  -> …-hello-2.12.2 output sz8x8ca…
guix build -d --system=aarch64-linux   hello    -> …-hello-2.12.2 output 8qjzxdk…
```

Different outputs, same package. And for the kernel specifically:

| | result |
| --- | --- |
| `--target=aarch64-linux-gnu` | kernel **would be built** (no substitute exists for a cross derivation), plus ~480 MB of cross toolchain |
| `--system=aarch64-linux` | kernel **would be downloaded**, 31.6 MB (`linux-libre-arm64-mnt-reform-7.0.14`) |

### Cross-compiling this config does not work end to end

`guix system build --target=aarch64-linux-gnu` computes all derivations
fine (the dry-run passes), but the real build fails:

```
libgudev-238: meson setup --cross-file … ->
  ERROR: Dependency "gobject-introspection-1.0" not found, tried pkgconfig
```

`libgudev` is a dependency of `upower`, which the rde desktop service set
pulls in, so the failure is not optional. It is a cross-compilation gap in
Guix (gobject-introspection does not provide a target `.pc` under
cross-compilation), not something this configuration can work around.

The home environment has an independent hard blocker: `libreoffice` depends
on `python-lxml`, and `pyproject-build-system`'s `lower` is `(and (not
target) …)` — it refuses cross builds outright, at this pinned commit as
well as in 1.5.0.

So `--target=` is useful as a *fast structural check* of the configuration —
it catches unresolved variables, wrong module imports, packages unsupported
on aarch64 — and nothing more. Do not plan around it. Everything that has to
run on the Reform is built with `--system=aarch64-linux`.

(For the record: no grafting failure was observed. Grafts stayed enabled for
all of the above; the cross build was not "made green" by passing
`--no-grafts`.)

## 1. QEMU binfmt on the box

Needed for `--system=aarch64-linux`.  Add to `box`'s system services in
`src/configs/hosts/box.scm` (via `feature-custom-services`) and reconfigure:

```scheme
(service qemu-binfmt-service-type
         (qemu-binfmt-configuration
          (platforms (lookup-qemu-platforms "aarch64"))))
```

`qemu-binfmt-service-type` is in `(gnu services virtualization)`;
`lookup-qemu-platforms` in `(gnu system)` — both upstream.

Verify after reconfiguring:

```sh
cat /proc/sys/fs/binfmt_misc/qemu-aarch64     # should exist, flags include F
guix build --system=aarch64-linux hello       # should fetch or build
```

Emulated builds are roughly 5–20× slower than native x86_64.  A full desktop
system closure is a long job — start it and walk away.  It is still far
faster than building on the Reform, which mostly cannot.

Two operational notes from actually doing this:

- **Use `--cores=1` if a build wedges.** With `--cores=4`, the `man-db`
  profile hook died with `qemu: uncaught target signal 11 (Segmentation
  fault)` and then hung indefinitely at "34/84 building list of man-db
  entries". The identical build with `--cores=1` completed with no
  segfaults. qemu-user and heavily-forking builds do not always get along;
  losing the parallelism costs less than losing the build.
- **Check the binfmt handler is still registered** if a build fails with
  `executing '…/bin/guile': No such file or directory`. That error means the
  aarch64 interpreter went away, not that the file is missing — verify with
  `cat /proc/sys/fs/binfmt_misc/qemu-aarch64`. On a Guix System box
  `qemu-binfmt-service-type` keeps it registered across reboots, so this
  should not bite you there.

## 2. Check substitute coverage before building anything

```sh
make reform/weather                            # kernel + firmware
guix weather --system=aarch64-linux \
     --substitute-urls='https://bordeaux.guix.gnu.org https://ci.guix.gnu.org' \
     linux-libre-arm64-mnt-reform
```

Whatever `guix weather` reports as available is a download, not a build.

Measured at the pinned channels: the kernel is **100% available for aarch64
on both ci.guix.gnu.org and bordeaux** (31.6 MB for
`linux-libre-arm64-mnt-reform-7.0.14`), so the feared expensive item is not
expensive at all. The whole `reform-system` closure needs only three
derivations built; everything else downloads.

What `guix weather` cannot tell you is that one item does not merely lack a
substitute — it cannot be built for aarch64 at all. `ovmf-x86-64` is named in
`libvirt-service-type`'s default `firmwares` field, so `feature-qemu` drags
it into the closure; EDK2 then compiles its X64 modules with the native
aarch64 gcc, which rejects `-m64` / `-mno-red-zone` / `-mno-mmx`, and the
build dies. Pointing the field at `ovmf-aarch64` does not help either:
libvirt builds `/etc/qemu/firmware` by union-ing `<pkg>/share/qemu/firmware`,
and `ovmf-x86-64` is the only package in guix that installs that directory,
so the union's `opendir` fails.

The Reform has 4 GB of RAM and is not going to run VMs, so `configs.scm`
drops `feature-qemu` for this host outright — which also takes libvirt,
virt-manager and their closures out of a machine that has no use for them.

Two things worth remembering from this. An x86 default buried in a service's
configuration only shows up when you build for the target architecture — the
dry-run computes the derivation happily. And the ~220 system-glue derivations
(shepherd `.go` files, `etc`, activation scripts) are never substitutable
from anywhere: they are specific to your service graph, so they get built
under emulation on the box, or natively on the Reform. They are Guile
compiles rather than C, which is why they are feasible on the Reform at all —
but they are also why the box is worth having.

## 3. Signing key on the box

`guix publish` signs every narinfo it serves.  The key pair lives in
`/etc/guix`:

```sh
sudo guix archive --generate-key        # slow: waits for entropy
sudo ls -l /etc/guix/signing-key.pub /etc/guix/signing-key.sec
```

On a Guix System box, `guix-publish-service-type` generates the key on first
activation, so you can skip this and just read `/etc/guix/signing-key.pub`
afterwards.  `signing-key.sec` never leaves the box.

## 4. Run `guix publish` on the box

Configured in `box.scm` as a system service:

```scheme
(service guix-publish-service-type
         (guix-publish-configuration
          (host "0.0.0.0")     ;default "localhost" is not reachable from the LAN
          (port 3001)
          (compression '(("zstd" 3)))
          (advertise? #f)      ;#t requires an mDNS/Avahi setup
          (ttl (* 30 24 3600))))
```

Port 3001, not the more obvious 3000: 3000 is already bound on the box by
Open WebUI (`docker/ai/compose.yml`, `127.0.0.1:3000:8080`). That bind is
loopback-only, but `guix-publish` has to listen on `0.0.0.0` to be reachable
from the Reform at all, and `0.0.0.0:N` can't coexist with `127.0.0.1:N` —
whichever service starts second just fails to bind. Check `docker/README.md`'s
port table before picking a port here if the podman stacks change.

The service runs the daemon as an unprivileged user itself — you do not
choose.  Reconfigure, then `sudo herd status guix-publish`.

By hand, for a one-off (note the port differs: the CLI defaults to 8080, the
service to 80 — pick whatever's actually free, checking the same port table):

```sh
sudo guix publish --user=nobody --port=3001 --compression=zstd:3
```

Start it as root — it must read `/etc/guix/signing-key.sec` and bind the port
— and always pass `--user`, which drops privileges immediately after.  Guix
warns if you don't.

Open the port to the LAN only (`box`'s firewall / your router), never to the
internet.

## 5. Authorize the box on the Reform — Debian side

The Reform runs Guix as a foreign-distro package manager, so this is
systemd + `/etc/guix`, **not** a Guix System `operating-system`.  None of
this touches `hosts/reform.scm`; the Guix System you install later has its
own `guix-configuration` (already set by `feature-additional-services` in
`users/laszlokr.scm`).

Copy the public key over, then authorize it:

```sh
# on box
scp /etc/guix/signing-key.pub reform:/tmp/box-signing-key.pub

# on the Reform, as root
guix archive --authorize < /tmp/box-signing-key.pub    # appends to /etc/guix/acl
```

> **Trust implication.** `/etc/guix/acl` is a trust root.  From this point the
> Reform's daemon will install *anything* signed by that key without further
> checks — the box can hand it arbitrary binaries under any store name,
> including replacements for the kernel and the init system.  Authorize the
> box because you control the box, and remove the entry from `/etc/guix/acl`
> if that ever stops being true.

Then point the daemon at the box.  Find the unit and its current `ExecStart`
first — do not copy a path out of this document:

```sh
systemctl cat guix-daemon
```

Add a drop-in (`sudo systemctl edit guix-daemon`) that clears and re-sets
`ExecStart`, keeping every option the original had and appending the box:

```ini
[Service]
ExecStart=
ExecStart=<the exact ExecStart from 'systemctl cat', with:> \
  --substitute-urls='https://ci.guix.gnu.org https://bordeaux.guix.gnu.org https://substitutes.nonguix.org http://box.lan:3001'
```

```sh
sudo systemctl daemon-reload
sudo systemctl restart guix-daemon
sudo systemctl status guix-daemon        # confirm the new ExecStart took
```

Use whatever name/IP actually resolves from the Reform (`box.lan`, `box.local`,
a static IP) — check with `getent hosts box.lan`.

Verify the two halves independently:

```sh
curl http://box.lan:3001/                          # "Guix Substitute Server" page
guix weather --substitute-urls=http://box.lan:3001 hello
```

`guix weather` reporting 0% while `curl` works usually means the key is not
authorized, or the box has not built that item yet.

A per-command `--substitute-urls=http://box.lan:3001` also works and is a good
way to test before editing the unit; the drop-in is what makes it stick.

## 6. Why `guix publish` and not `guix offload`

`guix offload` would have the Reform's daemon dispatch builds over SSH to the
box. It is the wrong tool here:

- Offload only accepts a build if the target machine advertises that system.
  The box would have to declare `aarch64-linux` in `/etc/guix/machines.scm`,
  which means QEMU binfmt anyway — so it does not save the emulation, it just
  moves when it happens.
- It is a push-on-demand model: the Reform blocks while the box builds. With
  `publish`, the box builds ahead of time, you see it succeed, *then* you touch
  the Reform. That ordering matters when the alternative is discovering a
  kernel build failure halfway through an install.
- It needs more moving parts on the Reform's foreign-distro daemon: a
  `guile-ssh`-enabled guix, an offload SSH key, `/etc/guix/machines.scm`, and
  `--max-jobs` tuning so the daemon actually offloads instead of building
  locally.
- `publish` keeps paying off afterwards, for `guix system reconfigure` and
  `guix pull` on the Reform.

Third option, worth knowing: `guix copy --to=reform /gnu/store/…-system` pushes
a closure over SSH from the box. Same key-authorization requirement, no HTTP
server, but you must name each closure by hand — fine for a one-shot rescue,
worse as the standing arrangement.

## 7. Make the Reform's `guix pull` cheap too

`guix system init` has to evaluate this repo's configuration on the Reform,
which means the Reform needs `guix` + `rde` + `nonguix` at the pinned commits
compiled for aarch64. That Guile compilation is itself heavy on a 4 GB
machine.

Build it on the box first, under emulation, so the Reform can fetch it:

```sh
# on box
guix pull --system=aarch64-linux -C rde/channels-lock.scm \
     -p /tmp/aarch64-guix-profile
```

`guix pull` takes `--system` — it pulls in `%standard-native-build-options`,
so `-s/--system` is available (verified, not assumed). This populates the
box's store with the aarch64 channel-instance derivations that the Reform's
own `guix pull -C rde/channels-lock.scm` will ask for.

Then the same pull on the Reform is mostly downloads from the box.

## 8. What the box cannot prebuild: the home environment

`guix home` takes **neither `--system` nor `--target`** — its option list is
`%standard-build-options` only, without the native or cross additions that
`guix system` and `guix pull` get. There is no way to ask it for an aarch64
home environment from the box, which is why the Makefile has no box-side
`reform/home` target.

Two ways around it, if the Reform's home environment turns out to be slow to
build there:

- Prebuild the *packages* rather than the environment. `guix build
  --system=aarch64-linux emacs firefox …` puts the same store items in the
  box's store, and `guix publish` serves them; the Reform's `guix home build`
  then downloads instead of building. Clumsy, but it is the same store paths.
- Just run `make reform/home/build` on the Reform and let it work. Guix Home
  is already running there on Debian today, so this is the path you know.

Be aware that the desktop-application half of the closure is where aarch64
substitute coverage is thinnest — `firefox` and `libreoffice` are built from
source in Guix, and nonguix's substitute server does not serve aarch64. That
part is unmeasured here; check it with `guix weather` on the Reform before
assuming it is a download.
