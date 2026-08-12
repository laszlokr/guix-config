# Local hardware reorg + Guix-everywhere rollout

Live progress against this plan is tracked separately in
[local-hardware-status.md](local-hardware-status.md) — check that file for
current state; this doc is the narrative "why," not a running checklist.

## Context

This covers the four **local** machines, separate from
[guix-everywhere-roadmap.md](guix-everywhere-roadmap.md) (which covers the
two remote Hetzner servers, `box`'s AI/container stack, and terminal
tooling — that plan is unaffected by this one). The four machines: `box`
(Minisforum HX90, Ryzen 9 5900HX, already full Guix System), `mintsystem`
(HP Envy x360 15-eu — **name TBD, being renamed**; currently dual-boot
Manjaro/Pop!_OS with **Guix Home** layered on top of Pop!_OS, not full Guix
System, and that dual-boot setup is being **fully replaced**, not kept as a
fallback), the MNT Reform (`reform`, already full Guix System, working),
and a dormant Raspberry Pi 4 (4GB) that currently **has no OS at all**. It
reconciles a pasted third-party hardware plan (drive cascade, RAM figures, a
Pi4 role sketch) against what this repo has already decided and what's
physically confirmed, and folds in the actual long-term vision: a homelab
where `box` becomes a real home server (bulk media/book storage, backups,
dev containers, and a personal AI/knowledge-base project called "rhizome"),
the Pi4 becomes an always-on local controller node, and a future
high-memory inference box gets added once acquired.

The central open question — **is the Reform-family the long-term primary
road machine, or does the HP Envy keep that role** — stays deliberately
undecided (the user's explicit choice): both paths are planned for below,
to be revisited once the HP Envy's repair/RAM outcome is known and once
"Reform Next" (a future MNT Reform purchase/CPU module being targeted as a
stronger travel-daily-driver candidate) actually exists. Whichever way it
resolves, the broader architecture is the same: the road machine leans on
the homelab remotely — latency-tolerant/always-on services on the VPS
(already decided, sing-box), privacy-sensitive/local services at home
across `box`, the Pi4, and eventually the future inference box. The one
constraint that architecture can't route around: a video call's own
outbound webcam/mic capture and encode has to happen on the machine that's
actually in the call — it can't be offloaded over a WAN link without
killing latency — so the Reform's camera/mic/encode gaps (confirmed below)
stay relevant to the road-machine decision no matter how much compute lives
at home.

**Recovery-priority principle, stated explicitly because it changes how
backup effort should be weighted**: `box`'s and `reform`'s system state
lives entirely in this git-tracked declarative config — a dead NVMe on
either is cheap to recover from, since `guix system reconfigure` from the
tracked `.scm` rebuilds the system itself. The SATA-bay **data** (media
library, rhizome's vault/DB, Qdrant store) has no such regeneration path.
Backup effort belongs almost entirely on the data volumes; the system NVMe
is disposable-and-rebuildable and doesn't need the same treatment.

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
  unconfirmed for this specific board (a Ryzen 7 5700U 64GB-support
  citation floated during planning turned out to be about the wrong chip
  anyway — `box`'s real CPU is a Ryzen 9 5900HX, see below — so it never
  transferred as evidence for the HP Envy's board/BIOS either way).
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
- **Dual-boot resolved**: the existing Manjaro and Pop!_OS partitions get
  fully wiped for a clean Guix System install, matching how the Reform was
  done — no dual-boot fallback kept. Back up anything worth keeping off
  either partition before this happens.
- **The host is being renamed** from `mintsystem` — new name not yet
  decided. Once it is, the rename touches more than one file:
  `src/configs/hosts/mintsystem.scm` itself, the `Makefile` targets, the
  README's host table, and every cross-reference in `wishlist.md` and this
  doc. Treat picking the name as a real prerequisite step before any of the
  install work below, not a detail to clean up afterward.

**`box`'s actual CPU is a Ryzen 9 5900HX** (Zen3 "Cezanne," 8-core/16-thread,
45W+ desktop-replacement class, integrated Vega 8/gfx90c iGPU, no discrete
GPU) — corrected mid-planning from an earlier wrong assumption (Ryzen 7
5700U, a much lower-power Zen2 chip). This matters directly for the local
LLM question in the rhizome section below: real-world llama.cpp benchmarks
on this chip class (proxied by desktop 5800X/5900X, same cores) show
roughly 6-9 tok/s generation on a 7-8B Q4_K_M model and ~3-5 tok/s
(extrapolated) on 13-14B — CPU-only, memory-bandwidth-bound, no discrete
GPU to help. llama.cpp's Vulkan backend on the Vega 8 iGPU is a real,
working acceleration path here (ROCm is not — no official support for this
iGPU) — measured ~2x prefill/prompt-processing speedup on the same iGPU
class, with token-generation staying roughly flat since generation is
bandwidth-bound either way. This favors prefill-heavy workloads (embedding
generation, document ingestion) more than interactive chat throughput.

**Repo/config state**:
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
  host.
- **Secrets management**: mostly already solved for the containerized case
  by a convention this repo already uses — `.gitignore` already excludes
  `docker/**/.env` and `files/sing-box/config.json` (real credentials live
  outside git, only a credential-free template is tracked). Rhizome's
  Anthropic/Voyage keys, and Honcho's LLM key (see below), just extend this
  same pattern — no new decision needed there. The genuinely open gap is
  for secrets a **native** Guix service would need to reference
  declaratively (nothing currently needs this, but LUKS/native-DB passwords
  would if that ever comes up): the closest thing to NixOS's `sops-nix` is
  the third-party **`sops-guix`** channel (encrypted files checked into
  git, decrypted into tmpfs at activation by a one-shot Shepherd service) —
  would need the same trust/authentication verification already applied to
  `rosenthal`/`saayix` before adopting it. `password-store` (`pass`) plus a
  small run-time decrypt script is the lower-tech, well-precedented
  fallback. Defer choosing between these until a native service actually
  needs a secret — not urgent today.

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
6. **The HP Envy's dual-boot gets fully wiped, not kept as a fallback** —
   resolved, no longer an open question.
7. **The Pi4's substitute-cache role moves to the front of the sequence.**
   It needs nothing beyond the Pi4 itself (independent of every RAM/repair
   gating item), and speeds up every subsequent `guix system
   reconfigure` in this whole plan — the HP Envy install, any `box.scm`
   rebuild after the storage work. Doing it first pays for itself across
   everything downstream, rather than only benefiting whatever comes after
   it in a fixed reading order.
8. **UPS scope corrected to include `box`, not just the Pi4.** `box` is the
   machine actually holding the LVM/mdadm pool and doing the writes — an
   outage mid-write there is a real corruption risk, more realistic than
   the Pi4 losing power. If "survives outages" is a real requirement
   anywhere in this plan, it has to cover the machine doing the writes.
9. **Pi4 monitoring role named concretely**, not left as a placeholder word
   — reusing the lightweight custom monitor already decided in
   `guix-everywhere-roadmap.md` for Uptime Kuma's absence from Guix (a
   small Guile/shell script + Shepherd timer hitting endpoints, notifying
   via Gotify), rather than introducing a heavier stack like
   Prometheus+Alertmanager that this repo already rejected as overkill for
   this scale elsewhere in the same roadmap.
10. **A `box`-level backup job is now part of the plan**, not just a named
    role with no destination — restic or borgbackup pushing the SATA-bay
    data volumes to VPS-attached storage over sing-box, on a schedule.
11. **Rhizome's local-inference stance is being pushed back on.** The
    spec's current default (hosted APIs only, no local inference) is
    getting revisited given real capability findings for `box`'s actual
    hardware — see the rhizome section below.
12. **Honcho added as a new candidate service** for local agentic
    memory/user-modeling, alongside rhizome — see the rhizome section.

## The plan

### 1. Stand up the Pi4 as a Guix substitute cache first

Moved to the front of the sequence: this needs nothing beyond the Pi4
itself and pays off across every later step in this plan (the HP Envy
install, any `box.scm` rebuild) by speeding up `guix system reconfigure`
runs the same way `box` already speeds up the Reform's. Requires first
researching Guix's actual RPi4 boot-chain story (see machine-by-machine
rollout below) — that research, not any hardware purchase, is the real
blocker here, so it can start immediately.

### 2. Test the HP Envy's real RAM ceiling with the HX90's existing sticks

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

### 3. HP Envy repair

Dust cleaning, hinge fix, and either a targeted bottom-plate replacement or
the ~200 EUR full replacement chassis (no motherboard) to fix the
keyboard/touchpad pressure issue. Straightforward mechanical repair;
sequence it around whichever RAM outcome above so the machine is only
opened up as many times as necessary.

### 4. Reform webcam/mic options, in case it ends up daily-driven

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
  will do more for call clarity than upgrading the camera.
- Mounting: a standard clip-on webcam should sit fine on the Reform's
  screen lid given its case thickness, but confirm physically before buying
  a specific clip design.

### 5. Drive-migration cascade

One new 1TB+ NVMe for the HX90 → HX90's current 512GB down to the HP Envy →
HP Envy's current 1TB BC711 down to the Reform (2280 NVMe, fits the M-key
slot; PCIe 2.0 x1 caps its speed but the 4x capacity jump over the 256GB
Transcend is still worth it) → Reform's old 256GB Transcend into an
external enclosure as the Pi4's boot drive. Keeping the Reform gaining
capacity (rather than donating its drive to the HP Envy) is correct — it's
the machine stuck with the slow, unswappable-for-speed slot.

### 6. `box` storage layout for its new home-server role

Use Guix's native `lvm-device-mapping` (proven pattern from `reform.scm`)
to pool the new NVMe capacity with the two SATA-bay drives, or
`raid-device-mapping` (mdadm) specifically where mirroring/redundancy is
wanted — not Btrfs multi-device pooling, per the research above.
Concretely, this likely means separate logical volumes/arrays for: bulk
media/book library storage, a backup staging area, and rhizome's data
volumes — exact split is part of the rhizome planning session, not this
plan; what belongs here now is just making sure `box.scm`'s
`file-systems`/`mapped-devices` can accommodate however many volumes that
turns out to be. `box` needs to be on a UPS too, not just the Pi4 (see key
decision 8) — it's the machine actually writing to this pool.

### 7. `box` backup job

Not just a named role — an actual restic or borgbackup job, scheduled via
`mcron-service-type` or a Shepherd timer, pushing the SATA-bay data volumes
(rhizome data, the book/media library, Arcus dev-container configs) to
VPS-attached storage over the existing sing-box link. This needs no new
infrastructure decision — the VPS side is already reachable — just the
cron/Shepherd job and a restic/borgbackup repository set up on the VPS end.
Per the recovery-priority principle above, this is where backup effort
should concentrate; `box`'s own system NVMe doesn't need equivalent
treatment since it rebuilds from git.

### 8. Guix rollout per machine

- **`box`**: no OS change. Extend `file-systems`/`mapped-devices` in
  `box.scm` for the new drives once the volume split above is decided.
- **`reform`**: no OS change, already full Guix System and working. Only
  the physical NVMe swap (step 5) applies.
- **HP Envy (new name TBD)**: converting from Guix-Home-on-Pop!_OS to full
  Guix System, wiping both existing partitions (resolved above, no
  dual-boot kept). Partition, `blkid` for the real LUKS/EFI UUIDs, and
  follow the same class of procedure already documented for the Reform
  ([reform-install.md](reform-install.md), [reform-build-box.md](reform-build-box.md))
  adapted for x86_64/UEFI instead of aarch64/U-Boot. Do this *after* the
  repair and RAM outcome are known, and after the new hostname is decided
  (the rename touches the host file, Makefile, README, and every
  cross-reference in this doc and `wishlist.md`).
- **Raspberry Pi 4**: genuinely new ground for this repo, but now the
  first thing actually built (step 1) rather than the last. Before writing
  `src/configs/hosts/rpi4.scm` (or whatever it ends up named) or attempting
  an install, research Guix System's actual current RPi4 boot-chain story —
  the same way `reform-install.md` started from research before a
  procedure existed.

### 9. Pi4 roles: substitute cache (first), then local controller

Once the boot-chain research from step 1/8 confirms a working install
path, layer on: a Guix substitute mirror/cache proxy for the home network
(the reason it's built first), a DNS resolver (Pi-hole/AdGuard) reachable
over the existing sing-box mesh, and the lightweight custom
Guile/Shepherd-timer + Gotify monitor already decided elsewhere in this
project (see key decision 9) extended to watch `box`. All of this stays
within 4GB RAM and explicitly doesn't host any Qdrant/Neo4j/rhizome-style
workload itself. Both the Pi4 and `box` need their own small UPS if
"survives home power outages" is meant literally — the controller being up
doesn't help if the machine it's watching just lost power mid-write, and
vice versa.

## Rhizome: reality check against the actual spec, plus open pushback

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
- **Local-inference stance is under active pushback, not settled.** The
  spec's current default routes all embedding/extraction/cleanup calls
  through hosted Anthropic + Voyage APIs. Given real capability findings
  for `box`'s actual hardware (Ryzen 9 5900HX, see above), the stated
  preference is: **run locally where it works, fall back to a cloud API
  where it doesn't** — not the spec's current API-first default. Concretely,
  by task:
  - **Embeddings**: strong local candidate. Small embedding models
    (nomic-embed-text, bge-m3, mxbai-embed-large, 100M-600M params) are
    cheap enough that CPU-only throughput on this chip processes a personal
    library of thousands of chunks in minutes, not hours — replace Voyage
    outright, served off the same native `llama-cpp` Shepherd service
    already planned in Phase D.
  - **Voice-transcript cleanup**: a well-bounded, low-complexity task (strip
    filler words, fix formatting) that a local 7-8B model at the ~6-9 tok/s
    this chip gets handles fine for background processing — good local
    candidate, Claude as fallback for anything that comes back malformed.
  - **Knowledge-graph extraction**: the hardest case — nuanced
    entity/relationship extraction is where a local 7-14B Q4 model will
    genuinely trail Claude in quality. Run it locally first, lean on the
    spec's existing `review_queue` human-approval step as the safety net,
    and escalate to the Claude API for cases the local pass can't handle
    confidently, rather than eliminating the API call outright.
  - This only applies cleanly if rhizome's AI calls route to a `llama-server`
    running on `box` — if it deploys to the VPS instead (still unresolved,
    see below), this means the VPS calling back home over the network for
    every request, which is fine for the batch-friendly embedding case and
    more of a real design tradeoff for the others.
- **New candidate service: self-hosted Honcho** (Plastic Labs' open-source
  agent memory/user-modeling service), for local agentic work. Its actual
  requirements: Docker Compose (API server + a background "Deriver" worker,
  both built from source), **PostgreSQL with pgvector as a hard
  requirement** (not optional), Redis for production caching, and a
  **mandatory** LLM API key — it won't start without one configured. It
  defaults to OpenAI but works with any OpenAI-compatible endpoint,
  including a local one — meaning it can point at the same native
  `llama-cpp` server already planned instead of a hosted key, once that
  server exists. Not packaged for Guix; practical self-hosting mirrors the
  existing pattern here: a new `docker/honcho/compose.yml` stack, secrets
  via a gitignored `.env` exactly like the Odoo/Nextcloud/n8n stacks
  already in this repo. Its own compose file ships a bundled pgvector
  Postgres instance — start with that documented setup rather than
  pointing it at a hypothetical native Guix Postgres instance; revisit only
  if running two separate Postgres instances (Honcho's own, plus any future
  native one) becomes an actual problem.
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
  - **`box`/HX90 locally**: run the same Compose stack(s) via
    podman-compose, structurally identical to the `docker/ai/`,
    `docker/nextcloud/`, `docker/automation/` stacks already in this repo —
    no new Guix packaging or service work needed, since the stacks are
    fully self-contained. Just new `docker/rhizome/` and `docker/honcho/`
    directories following the existing convention.
- **Partially resolved**: `feature-box-podman-compose` now takes a
  `#:stacks` argument and is enabled on `box`, scoped to `automation`. But
  bringing it up surfaced a real bug: netavark's network-attachment call is
  broken for any bridge-networked container in this Guix build, confirmed
  with a bare `podman run alpine` (not a config gap, not specific to custom
  networks or this stack — see `docker/README.md`'s "Known issue" section).
  Confirmed workaround: `network_mode: host` per service, which
  `automation` now uses (n8n and gotify don't need to talk to each other,
  so this was the easy case). **Honcho's own compose stack (API + Deriver
  worker + Postgres+pgvector + Redis) needs real inter-container
  communication**, so the same workaround would require each service to
  reference `localhost` instead of container-name DNS, plus manually
  keeping ports unique against everything else running host-networked at
  the same time — doable, not a dead end, but real extra setup work versus
  a plain compose file, and worth root-causing the underlying bug properly
  before relying on host networking long-term.

## Things to confirm before spending money or wiping data

- Physical RAM swap-test result (step 2) — determines both machines' final
  RAM configuration and budget.
- Whether there's data on the HP Envy's Manjaro/Pop!_OS partitions worth
  backing up before they're wiped (the wipe itself is now decided).
- The new hostname for the HP Envy, before any of its install work starts.
- Exact volume split on `box` (media library / backups / rhizome data) —
  deferred to the rhizome planning session, but needed before writing
  `box.scm`'s new `file-systems` entries.
- Rhizome's deployment target (VPS vs. `box` locally), its
  "WireGuard mesh"/"existing reverse proxy" assumptions, and the proposed
  local-inference-first pushback — all answerable now, independent of any
  hardware work, by whoever is driving that session.
- Restic vs. borgbackup for the `box`→VPS backup job — either is a
  reasonable pick; not blocking, just needs a choice before step 7 above.

## Verification

- RAM: `free -h` and `dmidecode -t memory` on both machines after the swap
  test and after any subsequent purchase, to confirm each sees the capacity
  actually installed.
- Drive cascade: `lsblk`/`blkid` on each machine after each swap, before
  touching the next machine in the chain.
- `box` storage: confirm the LVM/mdadm pool assembles and mounts correctly
  (`vgs`/`lvs` or `mdadm --detail`) before pointing any service at it.
- `box` backups: a real test restore, not just confirming the job runs
  without erroring — verify at least one file can actually be pulled back
  from the VPS-side repository before trusting the job.
- HP Envy Guix System install: dry-run via the Makefile target before any
  real build, confirm boot before deleting anything, then reconfigure once
  booted from the new install (exact target names depend on the new
  hostname).
- Pi4: once a working install path is researched and documented, the same
  dry-run-before-real-build discipline applies before it takes on any
  service role.

## Immediate next step

The Pi4 boot-chain research (step 1) can start immediately, independent of
everything else. In parallel: the RAM swap-test (step 2) and getting a firm
repair cost (step 3) gate the primary-machine decision and the HP Envy's
own rollout.
