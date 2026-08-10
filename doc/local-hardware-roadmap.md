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
**has no OS at all**.

The trigger: consolidating storage across these machines via a
drive-migration cascade (one new NVMe purchase cascades old drives down the
chain instead of buying three), a possible RAM upgrade + repair for the HP
Envy, and getting Guix System (not just Guix Home) onto every machine that
doesn't have it yet. This reconciles a third-party hardware plan (drive
cascade, RAM figures, a Raspberry Pi role sketch) against what this repo has
already decided and what's physically confirmed about the hardware.

The central open question — **is the Reform capable enough to be the
primary on-the-road machine for remote work and video calls, or does the HP
Envy need to stay in that role** — is deliberately left undecided here (both
paths are laid out below) pending the HP Envy's repair outcome and the RAM
verification below.

## Confirmed facts

**Reform's limits for video-conferencing/remote-work-primary duty** — all
previously confirmed in this repo's own investigation, not assumed:
- Onboard Wi-Fi (Realtek RTL8822CS) is **permanently dead** under
  linux-libre — confirmed via live dmesg (`/*(DEBLOBBED)*/`, error -2). A USB
  dongle is required for any networking at all; see the comment above
  `%reform-kernel` in `src/configs/hosts/reform.scm`.
- No built-in camera or microphone (by design) — any video call needs an
  external USB webcam+mic, one more dongle to carry/manage.
- RAM on the Banana Pi CM4 module is soldered LPDDR4 and modest — not
  upgradable, and no confirmed headroom check has been done for
  video-call-plus-dev-tools workloads.
- No hardware video encode/decode path exists under linux-libre for this
  Amlogic SoC (VPU microcode isn't even in mainline `linux-firmware`) — a
  video call's outbound encode would be pure software encode, CPU-bound on
  an already modest SoC.
- Battery life is weaker than a typical business laptop.

None of this blocks the Reform in its existing wishlist role as a
lightweight coding/tinkering travel machine — it specifically undercuts it
as a video-conferencing/all-day-remote-work primary machine.

**HP Envy x360 15-eu RAM ceiling** — researched, not assumed:
- Confirmed: **2 SODIMM slots, not soldered** (teardown-confirmed).
- HP's own service manual lists 16GB max for this exact sub-model
  (15-eu0xxx), but multiple community reports (HP Support Community threads)
  describe 32GB (2×16GB DDR4-3200) working in practice despite that official
  cap — 32GB is a safe bet.
- **64GB (2×32GB) is unconfirmed for this specific Tiger Lake-based 15-eu
  variant.** The 64GB listings found in research are a different, newer
  sub-model (15-ew, Alder Lake) — not evidence for this board. Verify before
  buying a 64GB kit (see checklist below).

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
  configuration exists yet. Adding the SATA-bay drives from the cascade plan
  means writing new file-systems entries from scratch, not just physically
  installing them.
- No Raspberry Pi host config exists anywhere in the repo — a Pi4 host
  config would be entirely new, and Guix's RPi4 boot chain (Raspberry Pi's
  own GPU-firmware-driven boot process reading `config.txt`, distinct from
  both `box`'s UEFI/GRUB and the Reform's vendor U-Boot/extlinux) has not
  been researched in this repo yet.
- **Headscale was already decided against** in `guix-everywhere-roadmap.md`
  ("Headscale is dropped... VPN needs are already covered by sing-box") — a
  "Headscale-adjacent mesh node" framing for the Pi4 conflicts with this;
  use sing-box-adjacent framing instead (DNS resolver, substitute mirror, or
  monitoring node reachable over the existing sing-box mesh).
- "Rhizome" (a Qdrant/Neo4j data volume from the third-party plan) has **no
  existing counterpart in this repo** — Qdrant exists only as a
  podman-compose container (`docker/ai/compose.yml`), and Neo4j doesn't
  appear anywhere. Treat this as an unconfirmed idea to check before
  building storage around it, not an established service.

## Key decisions made this round

1. **Primary-road-machine decision is sequenced, not forced now.** It
   depends on the HP Envy's repair scope/cost and the RAM ceiling
   verification below — both unknown at plan time.
2. **The drive-migration cascade is sound as designed.** One new 1TB+ NVMe
   for the HX90 → HX90's old 512GB to the HP Envy → HP Envy's old 1TB BC711
   to the Reform (2280 NVMe, fits the M-key slot; PCIe 2.0 x1 caps its speed
   but 4x capacity over the 256GB Transcend is still worth it) → Reform's
   old 256GB Transcend to an external enclosure as the Pi4's boot drive.
   Keeping the Reform gaining capacity (rather than donating its drive to
   the HP Envy) is correct — it's the machine stuck with the slow,
   unswappable-for-speed slot.
3. **Pi4 networking role reframed around sing-box**, not Headscale, per the
   decision already recorded in `guix-everywhere-roadmap.md`.
4. **No config work starts on `mintsystem` or a new Pi4 host until their
   physical/OS prerequisites are resolved** — filling in placeholder UUIDs
   or writing a Pi4 config before partitioning decisions and boot-chain
   research are done would just be guessing.

## The plan

### 1. Verify the HP Envy's real RAM ceiling before buying anything

Boot the HP Envy (Manjaro, Pop!_OS, or a live USB — doesn't matter which)
and check the *board's* real ceiling, not just the CPU's theoretical one:
- `sudo dmidecode -t memory | grep -A2 "Maximum Capacity"`, and note the
  exact CPU model (`lscpu`) to cross-check against Intel ARK's listed max
  memory for that SKU.
- If that comes back ambiguous or optimistic, the safe purchase is a single
  32GB DDR4-3200 SODIMM to test in one slot before committing to a full
  2×32GB kit.

### 2. Drive-migration cascade

As decided above — no changes needed to the third-party plan's mechanics.
One addition: `box.scm`'s file-systems section needs new entries for
whatever goes in the two empty SATA bays (mirror/backup target for the Guix
store, or a separate data volume) — this is real config work, not just
inserting drives. Defer deciding *what* goes there until the "rhizome"
question is resolved — don't build storage around a service that may not
get built.

### 3. Guix rollout per machine

- **`box`**: no OS change needed. Extend `file-systems` in `box.scm` once
  the SATA-bay drives' purpose is confirmed.
- **`reform`**: no OS change needed, already full Guix System and working.
  Only the physical NVMe swap (step 2) applies.
- **`mintsystem` (HP Envy)**: converting from Guix-Home-on-Pop!_OS to full
  Guix System is bigger than filling in the two TODO UUIDs. First decide
  what happens to the existing Manjaro and Pop!_OS partitions (wipe both for
  a clean install matching how the Reform was done, or keep one as a
  dual-boot fallback the way the Reform keeps Debian on the SD card). Then:
  partition, `blkid` for the real LUKS/EFI UUIDs, and follow the same class
  of procedure already documented for the Reform
  ([reform-install.md](reform-install.md), [reform-build-box.md](reform-build-box.md))
  adapted for x86_64/UEFI instead of aarch64/U-Boot. Do this *after* the
  repair and RAM decision — no point reinstalling before knowing the
  hardware is staying in service.
- **Raspberry Pi 4**: genuinely new ground for this repo. Before writing a
  `src/configs/hosts/rpi4.scm` or attempting an install, research Guix
  System's actual current RPi4 boot-chain story (Raspberry Pi's own
  GPU-firmware-driven boot process and `config.txt`, unlike either existing
  local machine) — its own short research pass, the same way
  `reform-install.md` started from research before a procedure existed.
  Don't schedule the enclosure/boot-drive work for it until that research
  confirms a working path.

### 4. Pi4 service role (once it has an OS)

Reframed around sing-box: DNS resolver (Pi-hole/AdGuard) reachable over the
existing sing-box mesh, a Guix substitute mirror/cache proxy for the home
network, or a lightweight monitoring/alerting node (independent of the HX90
it would be watching). 4GB RAM keeps it to lightweight services only —
explicitly not part of any Qdrant/Neo4j-style workload.

## Things to confirm before spending money or wiping data

- Real RAM ceiling test result for the HP Envy (step 1).
- What's actually wrong with the HP Envy that needs repair, and rough cost —
  the other half of the primary-machine decision, not yet specified.
- Whether "rhizome" (Qdrant/Neo4j) is a real, intended service or a stray
  idea — affects what the new `box` SATA-bay drives are even for.
- Whether to wipe the HP Envy's Manjaro/Pop!_OS partitions entirely or keep
  one as a dual-boot fallback, and whether there's data on either worth
  backing up first.

## Verification

- RAM: `dmidecode`/BIOS check before purchase; after installation, `free -h`
  and `dmidecode -t memory` to confirm the OS sees the full installed
  capacity.
- Drive cascade: `lsblk`/`blkid` on each machine after each swap, before
  touching the next machine in the chain, to confirm the moved drive is
  recognized and not silently degraded by the Reform's PCIe 2.0 x1 lane.
- `mintsystem` Guix System install: same pattern already used for the
  Reform — `make mintsystem/system/dry-run` before any real build, confirm
  boot via the kept fallback (dual-boot partition or USB rescue media)
  before deleting anything, then `make mintsystem/system/reconfigure` once
  booted from the new install.
- Pi4: once a working install path is researched and documented, the same
  dry-run-before-real-build discipline applies before it takes on any
  service role.

## Immediate next step

Verify the HP Envy's real RAM ceiling (step 1) and get a repair
scope/estimate — both gate the primary-machine decision and the rest of
this plan.
