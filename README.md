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

### Usage

Build and reconfigure targets use the `RDE_TARGET` environment variable, driven by the `Makefile`:

```sh
# box (HX90) — system
make box/system/reconfigure

# box (HX90) — home environment
make box/home/reconfigure

# mintsystem (HP laptop) — home environment
make mintsystem/home/reconfigure
```

### Planned improvements

1. Consistent configs based on rde for `box` and `mintsystem` [x]
2. Customize the configuration
   - System-wide vim keys [x]
   - Consistent colorscheme based on palenight [ ]
   - Emacs as main client for:
     - Mail (mu4e) [ ]
     - Telegram (telega) [ ]
     - Matrix (ement + pantalaimon) [ ]
   - Find ways to apply:
     - emacs-frame-only-mode [ ]
     - SPC as leader key (Doom Emacs style keybindings) [ ]
     - UI based on packages made by Nicolas Rougier (NANO Emacs) [ ]
3. Populate `mintsystem` file system UUIDs and finalize host config [ ]

## Remote hosts

The list of remote hosts for laszlo.is domain. The desired setup includes:

1. Email server [ ]
2. Personal website [ ]
3. Matrix and Pantalaimon [ ]
4. File sync (currently Nextcloud, but can change to Syncthing) [ ]
5. Wireguard VPN (currently use [Wirehole](https://github.com/IAmStoxe/wirehole), could try same setup with Guix) [ ]
