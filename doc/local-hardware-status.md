# Local hardware rollout — status

Running checklist for [local-hardware-roadmap.md](local-hardware-roadmap.md).
Update this file as steps actually happen; keep the roadmap doc itself for
the "why," not day-to-day state, so its diffs stay reviewable.

Status legend: `[ ]` not started · `[~]` in progress/blocked · `[x]` done.

## Sequence (see roadmap doc for full detail on each)

- [ ] 1. Pi4 Guix boot-chain research
- [x] 2. HP Envy RAM swap-test (HX90's 64GB → HP Envy) — passed, 64GB works
- [ ] 3. HP Envy repair (dust, hinge, bottom-plate/chassis)
- [ ] 4. Reform webcam/mic purchase, if pursuing Reform-as-daily-driver path
- [ ] 5. Drive-migration cascade (new NVMe → HX90 → HP Envy → Reform → Pi4 enclosure)
- [ ] 6. `box` storage layout (LVM/mdadm pool across NVMe + 2 SATA bays)
- [ ] 7. `box` backup job (restic/borgbackup → VPS, scheduled)
- [ ] 8. Guix rollout: `box.scm` file-systems extension
- [ ] 8. Guix rollout: HP Envy full Guix System install (new hostname TBD)
- [ ] 8. Guix rollout: Pi4 host config + install
- [ ] 9. Pi4 roles: substitute cache, DNS resolver, monitoring node

## Blocking decisions (see roadmap doc's "Things to confirm")

- [x] RAM swap-test result known — HX90's 64GB runs fine in the HP Envy
- [ ] HP Envy new hostname chosen
- [ ] `box` volume split decided (media / backups / rhizome data)
- [ ] Rhizome deployment target resolved (VPS vs. `box` locally)
- [ ] Rhizome local-inference pushback accepted/rejected by the other session
- [ ] Restic vs. borgbackup chosen for the `box`→VPS job

## Open issue: DNS did not survive the reboot on `box`

Found 2026-08-12 on the first real boot of `box` in ten days. Everything
routed (pings to 8.8.8.8 and to the VPS both fine) but no name resolved —
`/etc/resolv.conf` contained only `# This is a placeholder.`, with no
`nameserver` line.

That placeholder comes from **nscd's activation script**
(`nscd-activation` in `gnu/services/base.scm`), which writes it only when
`/etc/resolv.conf` does not already exist, on the assumption NetworkManager
will then take the file over. NetworkManager had the servers —
`nmcli dev show wlp3s0` reported `IP4.DNS[1]: 192.168.0.1` from DHCP — but
never wrote them out. Guix's `network-manager-configuration` defaults
`dns` to `"default"` (i.e. NM *should* manage resolv.conf), and nothing in
this repo overrides it, so this looks like a boot-ordering race rather than
a misconfiguration.

Worked around by hand (`echo "nameserver 1.1.1.1" | sudo tee
/etc/resolv.conf`) — restores resolution immediately, but does not survive a
reconfigure, and has not been proven to recur.

**Why this matters for the headless plan**: if it recurs on a headless
`box`, the result is a machine reachable by IP but unable to resolve
anything, with no console to fix it. Worth making deterministic *before*
the monitor comes off, not after.

Next steps, in order:
1. Reboot once more and see whether it recurs. A one-off race and a
   persistent misconfiguration need different fixes, and this is cheap to
   find out.
2. If it recurs, make it declarative: set
   `network-manager-configuration`'s `dns` to `"none"` and provide
   `/etc/resolv.conf` from the config instead. Since sing-box's
   `hijack-dns` rule intercepts DNS to any address, the literal nameserver
   in that file barely matters — and if sing-box is down, a plain query to
   1.1.1.1 still works, so it is robust either way. Tradeoff: hardcodes DNS,
   which is wrong for a laptop that roams but fine for a stationary desktop.

## Ready to act on

- [ ] **Move the guix channel pin forward** (`make -B rde/channels-lock.scm`).
      Fixes the netavark bug outright — the pin (`8db8515a`, 2026-07-15)
      caught guix with podman 6.0.1 but netavark 1.14.1 / aardvark-dns
      1.17.0, where podman 6.0 requires both at 2.0.0. Current guix has the
      matched set. Big blast radius (rebuilds both hosts, kernel included),
      so it wants its own reconfigure-and-verify cycle per machine, and
      `make reform/weather` first for aarch64 substitute coverage. Once
      done, revert `docker/automation/compose.yml` to a normal `networks:`
      stanza and drop the `GOTIFY_SERVER_PORT` override.
- [ ] **First reconfigure with the new declarative bootloader** — `box.scm`
      now supplies `grub-efi-cryptodisk` and `--no-bootloader` is gone from
      the Makefile, so guix installs the bootloader itself. Rescue media to
      hand, and verify the menu before rebooting; see
      [box-bootloader.md](box-bootloader.md).
- [ ] **Reboot `box` once more** to see whether the DNS failure recurs.

## Notes

Add a dated one-line entry here when a step's status changes, e.g.:

- 2026-08-12: doc created, nothing started yet.
- 2026-08-12: `feature-box-podman-compose` gap (guix-everywhere-roadmap.md
  Phase D item 7) resolved — enabled on `box`, scoped to `automation` only.
- 2026-08-12: `automation` stack confirmed running on `box` — n8n on 5678,
  gotify on 8090, both verified serving. Took three unrelated fixes: root's
  missing `/etc/containers/{registries.conf,policy.json}`, a `network_mode:
  host` workaround for the netavark bug (see `docker/README.md`), and
  rewriting the Shepherd service to `make-forkexec-constructor` +
  `one-shot?` so it gets logging and an environment at all.
- 2026-08-12: sing-box on `box` was crash-looping (`initialize cache-file:
  timeout`), not running — a hand-started instance from before the service
  existed held the lock on `/var/lib/sing-box/cache.db`. Killed it, service
  now stable. Failure mode documented above the service in `box.scm`.
- 2026-08-12: GRUB menu had been frozen at the May generation since
  `--no-bootloader` was added — `install-bootloader` alone never fixed that
  (it writes only the EFI binary; the menu comes from `install-boot-config`,
  which `--no-bootloader` also skips), and the target was itself broken from
  the day it was written (make-expanded `$(find ...)`, never once succeeded).
- 2026-08-13: **HP Envy RAM swap-test passed** (sequence step 2) — the
  HX90's 64GB runs fine in the Envy. Unblocks the Envy as a full Guix System
  target (step 8) and removes the memory-capacity question from the
  drive-migration cascade (step 5). Hostname still unchosen.
- 2026-08-12: **GRUB gap now closed.** Ran the
  [box-bootloader.md](box-bootloader.md) sequence: reconfigure without
  `--no-bootloader`, then immediately `make box/system/install-bootloader`,
  no reboot in between. Verified the default menu entry's `gnu.system` store
  path matches generation 22's canonical path exactly; menu went 13 → 23
  entries. Not yet reboot-tested, but the boot path is current.
