# Laszlo's GNU Guix config

This repository is for tracking configuration files for personal GNU Guix systems. It is based on [rde](https://git.sr.ht/~abcdw/rde) configuration framework and by default depends on Emacs (+evil-collection) and Sway window manager along other Wayland applications.

## Goals

To achieve reproducible setup across local devices and personal remote infrastructure (email, website, git, etc.).

The end goal is to have a consistent computing experience and a set of configuration templates for local and remote hosts, with all config files written in Guile Scheme.

The workflow implies having all Emacs buffers in new frames in order to utilize the window management capabilities of Sway instead of Emacs' internal window manager.

## Systems

### Hosts

| Host       | Device          | Config                                              | Description                               |
|------------|-----------------|-----------------------------------------------------|-------------------------------------------|
| box        | Minisforum HX90 | [box](src/configs/hosts/box.scm)                   | Main machine at home, runs full Guix system |
| mintsystem | HP laptop       | [mintsystem](src/configs/hosts/mintsystem.scm)     | HP laptop, runs home environment via Guix |
| reform     | MNT Reform (Banana Pi CM4, A311D, aarch64) | [reform](src/configs/hosts/reform.scm) | Full Guix system on NVMe; built on `box`, installed with `guix system init` |

### Usage

Build and reconfigure targets use the `RDE_TARGET` environment variable, driven by the `Makefile`:

```sh
# box (HX90) — system
make box/system/reconfigure

# box (HX90) — home environment
make box/home/reconfigure

# mintsystem (HP laptop) — home environment
make mintsystem/home/reconfigure

# reform (MNT Reform, aarch64) — run these ON the Reform
make reform/system/dry-run        # check nothing big would be built
make reform/system/build
make reform/system/init           # install onto the NVMe mounted at /mnt
make reform/system/reconfigure    # once it boots from NVMe
make reform/home/build

# reform — run these on box, to prebuild for the Reform
make reform/weather               # aarch64 substitute coverage for the kernel
make reform/system/emulated-build # produces what the Reform downloads (needs qemu binfmt)
make reform/system/cross-dry-run  # structural check only; cross does not build
```

The story of getting the Reform to a working Guix desktop — why it's set up
this way, and every sharp edge hit along the way — is in
[doc/reform-guix-desktop.md](doc/reform-guix-desktop.md). The step-by-step
procedures it references: [doc/reform-build-box.md](doc/reform-build-box.md)
(serving builds from `box`) and
[doc/reform-install.md](doc/reform-install.md) (the `guix system init`
checklist).

Planned work and open wishlist items (desktop polish, remaining hosts, the
larger remote-infrastructure migration) live in
[doc/wishlist.md](doc/wishlist.md) and
[doc/guix-everywhere-roadmap.md](doc/guix-everywhere-roadmap.md), not here.
