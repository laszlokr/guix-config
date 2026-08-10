# Local hardware reorg + Guix-everywhere rollout

## Context

This covers the four **local** machines, separate from
[guix-everywhere-roadmap.md](guix-everywhere-roadmap.md) (which covers the
two remote Hetzner servers, `box`'s AI/container stack, and terminal
tooling — that plan is unaffected by this one). The four machines: `box`
(Minisforum HX90, already full Guix System), `mintsystem` (HP Envy x360
15-eu, currently dual-boot Manjaro/Pop!_OS with **Guix Home** layered on top
of Pop!_OS, not full Guix System), the MNT Reform (`reform`, already full
Guix System, working), and a dormant Raspberry Pi 4 (4GB) that currently
**has no OS at all**. It reconciles a pasted third-party hardware plan
(drive cascade, RAM figures, a Pi4 role sketch) against what this repo has
already decided and what's physically confirmed, and folds in the actual
long-term vision: a homelab where `box` becomes a real home server (bulk
media/book storage, backups, dev containers, and a personal AI/
knowledge-base project called "rhizome"), the Pi4 becomes an always-on
local controller node, and a future high-memory inference box gets added
once acquired.

The central open question — **is the Reform-family the long-term primary
road machine, or does the HP Envy keep that role** — stays deliberately
undecided (explicit choice, not an oversight): both paths are planned for
below, to be revisited once the HP Envy's repair/RAM outcome is known and
once "Reform Next" (a future MNT Reform purchase/CPU module being targeted
as a stronger travel-daily-driver candidate) actually exists. Whichever way
it resolves, the broader architecture is the same: the road machine leans
on the homelab remotely — latency-tolerant/always-on services on the VPS
(already decided, sing-box), privacy-sensitive/local services at home
across `box`, the Pi4, and eventually the future inference box. The one
constraint that architecture can't route around: a video call's own
outbound webcam/mic capture and encode has to happen on the machine that's
actually in the call — it can't be offloaded over a WAN link without
killing latency — so the Reform's camera/mic/encode gaps (confirmed below)
stay relevant to the road-machine decision no matter how much compute lives
at home.

## Confirmed facts

**Reform's limits for video-conferencing/remote-work-primary duty** — all
previously confirmed in this repo's own investigation, not assumed:
- Onboard Wi-Fi (Realtek RTL8822CS) is **permanently dead** under
  linux-libre — confirmed via live dmesg (`/*(DEBLOBBED)*/`, error -2). A USB
  dongle is required for any networking at all; see the comment above
  `%reform-kernel` in `src/configs/hosts/reform.scm`.
- No built-in camera or microphone (by design) — see webcam/mic
  recommendations below for if the current Reform ends up daily-driven
  before Reform Next exists.
- RAM on the Banana Pi CM4 module is soldered LPDDR4 and modest — not
  upgradable.
- No hardware video encode/decode path exists under linux-libre for this
  Amlogic SoC (VPU microcode isn't even in mainline `linux-firmware`) — a
  video call's outbound encode would be pure software encode, CPU-bound on
  an already modest SoC.
- Battery life is weaker than a typical business laptop.

None of this blocks the Reform in its existing wishlist role as a
lightweight coding/CPU-module-tinkering machine — it specifically undercuts
it as a video-conferencing/all-day-remote-work primary machine, which is
why the primary-machine question stays open rather than resolved here.

**HP Envy x360 15-eu RAM ceiling and repair scope**:
- 2 SODIMM slots, not soldered (teardown-confirmed). HP's own service
  manual lists 16GB max for this sub-model, but community reports describe
  32GB (2×16GB DDR4-3200) working in practice — 32GB is a safe bet. 64GB is
  unconfirmed for this specific Tiger Lake-based board (a Ryzen 7 5700U
  64GB-support citation floated during planning is about the HX90's own
  CPU, a different machine — it doesn't transfer as evidence for the HP
  Envy's board/BIOS).
- **Best verification available: a physical swap-test, not a spec lookup.**
  The HX90 already has 64GB installed. Since both machines almost certainly
  take standard DDR4 SODIMMs, physically moving the HX90's sticks into the
  HP Envy and checking whether it POSTs and reports the full 64GB is a more
  direct test than any dmidecode/community-report guess — free, and
  reversible if it fails (see the plan below for what to do either way).
- Repair scope, as described: dust cleaning, a display hinge fix, and
  either a replacement bottom plate or a full replacement chassis
  (~200 EUR, no motherboard) — needed because the current bottom plate
  presses on the keyboard/touchpad ribbon connectors hard enough to cause
  intermittent input failures under pressure. This is a contained,
  known-shape mechanical repair, not a logic-board problem.

**Repo/config state**:
- `src/configs/hosts/mintsystem.scm` already has a real feature list
  (`feature-file-systems`, `feature-kanshi`, `feature-custom-services`,
  `feature-hidpi`) but its LUKS and EFI partition UUIDs are literal
  placeholders (`"TODO-fill-in-luks-uuid"`, `"TODO-fill-in-efi-uuid"`) — it
  was drafted for a full Guix System install that was never carried out. The
  Makefile only wires up `mintsystem/home/reconfigure` today, matching its
  Guix-Home-only actual deployment.
- `src/configs/hosts/box.scm` has a single-drive file-systems setup (one
  LUKS `cryptroot`, one EFI partition) — no SATA-bay or multi-drive
  configuration exists yet.
- No Raspberry Pi host config exists anywhere in the repo — a Pi4 host
  config would be entirely new, and Guix's RPi4 boot chain (Raspberry Pi's
  own GPU-firmware-driven boot process reading `config.txt`, distinct from
  both `box`'s UEFI/GRUB and the Reform's vendor U-Boot/extlinux) has not
  been researched in this repo yet.
- **Headscale was already decided against** in `guix-everywhere-roadmap.md`
  — a "Headscale-adjacent mesh node" framing for the Pi4 is dropped in
  favor of sing-box-adjacent framing instead.
- **Guix's Btrfs support was researched this round** (there was openness to
  reinstalling everything with Btrfs): it's real, documented, first-class
  support (`(type "btrfs")` in `file-systems`), but a minority path with a
  real history of subvolume/GRUB boot friction that needed upstream fixes
  (Guix bugs #33517, #37305) to become workable. Critically, **Guix has no
  declarative multi-device Btrfs pooling** — `mapped-devices` only ships
  `luks-device-mapping`, `raid-device-mapping` (mdadm), and
  `lvm-device-mapping`, no Btrfs equivalent — so spanning the NVMe + 2 SATA
  SSDs as one Btrfs pool would mean formatting it by hand outside Guix's
  model, then declaring one `file-system` entry pointing at the result by
  UUID. There's also no snapper-equivalent snapshot service; snapshotting
  would be fully DIY (a custom Shepherd/cron job calling `btrfs subvolume
  snapshot`). **Verdict: LVM (already proven in `reform.scm` for
  `/home`+swap) or mdadm RAID1 (also natively modeled via
  `raid-device-mapping`) is the lower-friction, Guix-native choice for
  pooling/mirroring the SATA-bay drives.** If subvolume snapshots
  specifically are wanted on one particular data volume later, formatting
  that single LVM logical volume as Btrfs (single-device, sidestepping the
  multi-device gap) is a viable add-on — not a reason to reinstall
  everything with Btrfs now.
- "Rhizome" is a real project already being built in a separate session
  against its own fixed spec — see the dedicated section below for the
  reality-check against that spec, which supersedes earlier speculation
  here about its architecture. `box`'s bulk media/book-library and backup
  role stands regardless of where rhizome's live services end up running.
- The local/remote split principle: latency-tolerant/always-on services
  live on the VPS; privacy-sensitive services that should survive a home
  power outage live locally. This is why the Pi4's role is framed as an
  **always-on local controller** for the rest of the homelab
  (watching/orchestrating `box` and friends) rather than a peer service
  host — worth keeping on a small UPS if "survives power outages" is meant
  literally, since the Pi4 itself still needs power to do that job.

## Key decisions made this round

1. **Primary-road-machine decision stays open, explicitly.** Both the
   Reform-family and the HP Envy paths are planned for; revisit once the
   HP Envy's repair/RAM outcome and Reform Next's existence are known.
2. **RAM verification method upgraded**: physically test the HX90's
   existing 64GB in the HP Envy rather than trust spec sheets or community
   reports alone.
3. **Btrfs is not adopted wholesale.** LVM/mdadm (already proven in
   `reform.scm`) stays the pooling/mirroring mechanism for `box`'s new
   drives; Btrfs is only a candidate for single-volume snapshotting later,
   layered on top of an LVM logical volume, not as a multi-device pool.
4. **Rhizome is confirmed real** and shapes `box`'s storage role, but its
   own architecture is deliberately deferred to a separate planning
   session — this plan only ensures `box.scm` can accommodate whatever
   volumes that session decides on.
5. **Pi4 networking role reframed around sing-box**, not Headscale, per the
   decision already recorded in `guix-everywhere-roadmap.md`, and framed as
   an always-on local controller node rather than a peer service host.
6. **No config work starts on `mintsystem` or a new Pi4 host until their
   physical/OS prerequisites are resolved** — filling in placeholder UUIDs
   or writing a Pi4 config before partitioning decisions and boot-chain
   research are done would just be guessing.

## The plan

### 1. Test the HP Envy's real RAM ceiling with the HX90's existing sticks

Physically move the HX90's current 64GB (assuming standard DDR4 SODIMM form
factor on both machines — confirm before removing anything) into the HP
Envy and check `free -h`/BIOS POST. Two outcomes:
- **Works**: HP Envy gets 64GB, but the HX90 now needs its own RAM sourced
  again — factor a 64GB (or whatever's decided) kit purchase for the HX90
  into the budget, not just the HP Envy.
- **Doesn't POST/doesn't see full capacity**: revert, and buy a 32GB
  DDR4-3200 kit for the HP Envy instead — well-corroborated as safe by
  community reports even though HP's own spec sheet caps lower.

Do this test as a standalone step, not squeezed in around other work on
either machine, since it involves opening both chassis and briefly leaves
the HX90 without RAM.

### 2. HP Envy repair

Dust cleaning, hinge fix, and either a targeted bottom-plate replacement or
the ~200 EUR full replacement chassis (no motherboard) to fix the
keyboard/touchpad pressure issue. Straightforward mechanical repair;
sequence it around whichever RAM outcome above so the machine is only
opened up as many times as necessary.

### 3. Reform webcam/mic options, in case it ends up daily-driven

Since the primary-machine decision is open, and the current Reform lacks
both camera and mic: standard UVC-class USB webcams need no special
drivers on Linux (no firmware-blob concern, in keeping with the libre
theme) and are the easy fix. Solid, well-established picks:
- **Logitech C920/C922**: the long-standing default recommendation for
  Linux UVC compatibility — plug-and-play, decent 1080p image quality,
  widely available secondhand/cheap.
- **Logitech Brio**: higher-end (4K, better low-light), same UVC
  reliability, more expensive.
- **Audio matters more than video for call quality** — most webcams' built-
  in mics are mediocre. A cheap USB headset or a small standalone USB mic
  will do more for call clarity than upgrading the camera. Worth pairing
  whichever webcam is chosen with one rather than relying on its onboard
  mic.
- Mounting: a standard clip-on webcam should sit fine on the Reform's
  screen lid given its case thickness, but confirm physically before buying
  a specific clip design.

### 4. Drive-migration cascade

One new 1TB+ NVMe for the HX90 → HX90's current 512GB down to the HP Envy →
HP Envy's current 1TB BC711 down to the Reform (2280 NVMe, fits the M-key
slot; PCIe 2.0 x1 caps its speed but the 4x capacity jump over the 256GB
Transcend is still worth it) → Reform's old 256GB Transcend into an
external enclosure as the Pi4's boot drive. Keeping the Reform gaining
capacity (rather than donating its drive to the HP Envy) is correct — it's
the machine stuck with the slow, unswappable-for-speed slot.

### 5. `box` storage layout for its new home-server role

Use Guix's native `lvm-device-mapping` (proven pattern from `reform.scm`)
to pool the new NVMe capacity with the two SATA-bay drives, or
`raid-device-mapping` (mdadm) specifically where mirroring/redundancy is
wanted (e.g., a backup target) — not Btrfs multi-device pooling, per the
research above. Concretely, this likely means separate logical
volumes/arrays for: bulk media/book library storage, backups, and rhizome's
data volumes (Qdrant store, Obsidian vault) — exact split is part of the
rhizome planning session, not this plan; what belongs here now is just
making sure `box.scm`'s `file-systems`/`mapped-devices` can accommodate
however many volumes that turns out to be.

### 6. Guix rollout per machine

- **`box`**: no OS change. Extend `file-systems`/`mapped-devices` in
  `box.scm` for the new drives once the volume split above is decided.
- **`reform`**: no OS change, already full Guix System and working. Only
  the physical NVMe swap (step 4) applies.
- **`mintsystem` (HP Envy)**: converting from Guix-Home-on-Pop!_OS to full
  Guix System is bigger than filling in the two TODO UUIDs. First decide
  what happens to the existing Manjaro and Pop!_OS partitions (wipe both for
  a clean install matching how the Reform was done, or keep one as a
  dual-boot fallback the way the Reform keeps Debian on the SD card). Then:
  partition, `blkid` for the real LUKS/EFI UUIDs, and follow the same class
  of procedure already documented for the Reform
  ([reform-install.md](reform-install.md), [reform-build-box.md](reform-build-box.md))
  adapted for x86_64/UEFI instead of aarch64/U-Boot. Do this *after* the
  repair and RAM outcome are known.
- **Raspberry Pi 4**: genuinely new ground for this repo. Before writing
  `src/configs/hosts/rpi4.scm` or attempting an install, research Guix
  System's actual current RPi4 boot-chain story — its own short research
  pass, the same way `reform-install.md` started from research before a
  procedure existed. Don't schedule the enclosure/boot-drive work for it
  until that research confirms a working path.

### 7. Pi4 role: always-on local controller

Framed around sing-box, not Headscale: a DNS resolver (Pi-hole/AdGuard)
reachable over the existing sing-box mesh, a Guix substitute mirror/cache
proxy for the home network, and/or a lightweight monitoring/alerting node
watching `box` and the rest of the homelab — the "controller of other
nodes" role, kept lightweight (4GB RAM) and explicitly not hosting any
Qdrant/Neo4j-style workload itself. If it's meant to survive home power
outages, it needs its own small UPS — the Pi4 being up doesn't help if the
outlet it's plugged into is dead.

## Rhizome: reality check against the actual spec

Rhizome (a personal AI/knowledge-base "life-OS" — Obsidian vault + book/
article library search, a knowledge graph, a signals dashboard) is already
being built in a separate session against a concrete, opinionated spec, not
something to design from scratch here. That spec overrides earlier
speculation about a Postgres+pgvector architecture explored while planning
this document — worth recording why, since the research behind that idea
isn't wrong, just inapplicable to this specific build:

- **Fixed stack, no substitution**: SQLite (single file) for the app's own
  tables, Neo4j Community Edition (one database, every node/relationship
  tagged with a `vault` property — Community Edition can't do per-vault
  databases) for the knowledge graph, and Qdrant (one named collection per
  vault) for vector search — all three as Docker Compose services. The spec
  explicitly forbids Postgres. Guix does natively package PostgreSQL +
  `pgvector` (confirmed via research: `postgresql-service-type` plus the
  `pgvector` package in Guix proper, no container needed) — genuinely
  useful to know, but only as a candidate for a possible future
  from-scratch rewrite, not for the version already in progress.
- **No local inference at all**: embeddings/extraction/cleanup go through
  hosted Anthropic + Voyage APIs, not `llama-cpp` or any local model. Voice
  capture happens locally on whichever machine is in use (a standalone
  script calling local `whisper.cpp` + the Claude API), separate from the
  Docker stack entirely. This means rhizome barely shares actual runtime
  infrastructure with `guix-everywhere-roadmap.md`'s Phase D
  (`llama-cpp`/`gptel` work) — they overlap in category, not in shared
  technical dependencies.
- **Deployment target is genuinely unresolved, in both sessions.** The
  spec's own text says "a personal Hetzner VPS... behind an existing
  reverse proxy and WireGuard mesh," which doesn't cleanly match this
  repo's actual VPN setup (sing-box running vless/vmess/hysteria2, not
  literally WireGuard) or confirm any existing reverse proxy (none found in
  this repo). Two real paths, left open on purpose:
  - **VPS**: run it on one of the Hetzner boxes from
    `guix-everywhere-roadmap.md` (the VPN box, the not-yet-built mail box,
    or a new third VPS) once that box is on Guix System. `box`/HX90's role
    becomes bulk file storage the app reads/writes to over the network,
    not the live app host. This path needs reconciling the spec's
    "WireGuard mesh"/"existing reverse proxy" assumptions with reality —
    either update the other session's spec to reference sing-box, or stand
    up a real reverse proxy (native `nginx-service-type` +
    `certbot-service-type`, no packaging gaps) and/or a genuine WireGuard
    tunnel (`wireguard-service-type`, also native) alongside sing-box.
  - **`box`/HX90 locally**: run the same three-container Compose stack via
    podman-compose, structurally identical to the `docker/ai/`,
    `docker/nextcloud/`, `docker/automation/` stacks already in this repo —
    no new Guix packaging or service work needed, since the stack is fully
    self-contained. Just a new `docker/rhizome/` directory following the
    existing convention.
- **Real gap found regardless of which path wins**: `feature-box-podman-compose`
  is currently commented out in `box.scm` — none of the existing
  podman-compose stacks (`ai`, `nextcloud`, `automation`, `odoo`, `search`)
  actually run today, and a local rhizome deployment would hit the same
  wall. Worth enabling on `box` regardless of rhizome's fate.

## Things to confirm before spending money or wiping data

- Physical RAM swap-test result (step 1) — determines both machines' final
  RAM configuration and budget.
- Whether to wipe the HP Envy's Manjaro/Pop!_OS partitions entirely or keep
  one as a dual-boot fallback, and whether there's data on either worth
  backing up first.
- Exact volume split on `box` (media library / backups / rhizome data) —
  deferred to the rhizome planning session, but needed before writing
  `box.scm`'s new `file-systems` entries.
- Rhizome's deployment target (VPS vs. `box` locally) and its spec's
  "WireGuard mesh"/"existing reverse proxy" assumptions — answerable now,
  independent of any hardware work, by whoever is driving that session.

## Verification

- RAM: `free -h` and `dmidecode -t memory` on both machines after the swap
  test and after any subsequent purchase, to confirm each sees the capacity
  actually installed.
- Drive cascade: `lsblk`/`blkid` on each machine after each swap, before
  touching the next machine in the chain.
- `box` storage: confirm the LVM/mdadm pool assembles and mounts correctly
  (`vgs`/`lvs` or `mdadm --detail`) before pointing any service at it.
- `mintsystem` Guix System install: `make mintsystem/system/dry-run` before
  any real build, confirm boot via the kept fallback before deleting
  anything, then `make mintsystem/system/reconfigure` once booted from the
  new install.
- Pi4: once a working install path is researched and documented, the same
  dry-run-before-real-build discipline applies before it takes on any
  service role.

## Immediate next step

The RAM swap-test (step 1) and getting a firm repair cost (step 2) — both
gate the primary-machine decision and everything downstream of it.
