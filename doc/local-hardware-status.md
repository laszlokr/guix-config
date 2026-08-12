# Local hardware rollout — status

Running checklist for [local-hardware-roadmap.md](local-hardware-roadmap.md).
Update this file as steps actually happen; keep the roadmap doc itself for
the "why," not day-to-day state, so its diffs stay reviewable.

Status legend: `[ ]` not started · `[~]` in progress/blocked · `[x]` done.

## Sequence (see roadmap doc for full detail on each)

- [ ] 1. Pi4 Guix boot-chain research
- [ ] 2. HP Envy RAM swap-test (HX90's 64GB → HP Envy)
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

- [ ] RAM swap-test result known
- [ ] HP Envy new hostname chosen
- [ ] `box` volume split decided (media / backups / rhizome data)
- [ ] Rhizome deployment target resolved (VPS vs. `box` locally)
- [ ] Rhizome local-inference pushback accepted/rejected by the other session
- [ ] Restic vs. borgbackup chosen for the `box`→VPS job

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
- 2026-08-12: **GRUB still frozen at the May generation** — `make
  box/system/install-bootloader` not yet run. Do not reboot `box` before
  running it, or it comes back on a three-month-old config.
