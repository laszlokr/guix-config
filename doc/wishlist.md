# Wishlist / roadmap

Everything not yet done, moved out of the README to keep that file to hosts
and usage. For the large multi-host infra migration (mail box, VPN box,
box's AI stack, terminal), see
[guix-everywhere-roadmap.md](guix-everywhere-roadmap.md) instead — that plan
has its own phases and status. This file covers the smaller, per-machine
items plus the remote-hosts wishlist entries that plan doesn't cover yet.

## Desktop & Emacs polish

- [x] Consistent configs based on rde for `box` and `mintsystem`
- [x] `reform` as a working daily-driver Guix desktop
- [x] System-wide vim keys
- [ ] System-wide Catppuccin theme with a light/dark toggle (apps +
      userstyles for supporting websites)
- [ ] Emacs as main client for:
  - [ ] Mail (mu4e)
  - [ ] Telegram (telega)
  - [ ] Matrix (ement + pantalaimon)
- [ ] Find ways to apply:
  - [ ] `emacs-frames-only-mode` (already installed, not yet wired up)
  - [ ] SPC as leader key (Doom Emacs style keybindings)
  - [ ] UI based on packages made by Nicolas Rougier (NANO Emacs)

## `mintsystem`

- [ ] Populate file system UUIDs and finalize host config

## `reform` as a full portable/travel machine

- [x] sing-box on `reform` (via the `rosenthal` channel)
- [ ] A real answer for LibreOffice-class apps on aarch64 — possibly a
      personal ARM build farm, since bordeaux doesn't substitute them
- [x] Wi-Fi without the dongle, or at least a smaller compatible one —
      resolved as **not fixable**: the onboard Realtek RTL8822CS is
      permanently blocked by linux-libre's firmware-deblob policy (confirmed
      live, see the comment above `%reform-kernel` in
      [reform.scm](../src/configs/hosts/reform.scm)). The USB dongle stays.
- [ ] Agentic coding on the road (opencode or similar)

## Remote hosts (laszlo.is)

The desired setup for personal remote infrastructure. Items already covered
by a phase in [guix-everywhere-roadmap.md](guix-everywhere-roadmap.md) link
there instead of duplicating the plan.

- [ ] Email server — see roadmap Phase B
- [ ] Personal website — not yet in the phased roadmap; needs its own plan
- [ ] Matrix and Pantalaimon — not yet in the phased roadmap; needs its own
      plan
- [ ] File sync (currently Nextcloud, moving to Syncthing) — see roadmap
      Phase C
- [x] Wireguard VPN (previously [Wirehole](https://github.com/IAmStoxe/wirehole)) —
      superseded: sing-box already covers VPN needs on `box` and `reform`,
      and the roadmap's Phase C moves the server side onto native
      `sing-box-service-type` too, dropping Wirehole/Docker entirely
