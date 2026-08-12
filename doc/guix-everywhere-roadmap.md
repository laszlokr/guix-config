# Guix-everywhere roadmap: infra, containers, AI, terminal

## Context

The Reform is now a working daily-driver Guix desktop, and the guix-config
repo has proven its pattern for bringing a new machine under declarative
management (host `.scm` + features + a documented install procedure). The
goal is to extend that pattern much further: two rented Hetzner ARM servers
currently on Debian/Ubuntu migrated fully to Guix System, `box`'s
podman-based AI/automation stack rationalized (replace what has a native
Guix path, keep what doesn't), `arcus` SaaS local development (currently
podman-compose) evaluated for a Guix-native alternative, LLM interaction
moved into Emacs as the primary UI, and Ghostty added as the terminal
emulator on both `box` and the Reform, alongside an Emacs-embedded terminal
(`ghostel`).

This is a large, multi-domain undertaking spanning months, not one session.
This is a **roadmap with a concrete first phase**, not a promise to build
all of it now. Research this round (four background investigations: repo
inventory, Guix container capabilities, remote ARM install methods, and
per-service Guix packaging status) surfaced hard constraints that reshape
the original service-split sketch — most notably, most of the originally
listed self-hosted services (Postfix, Forgejo, Uptime Kuma, Headscale,
Nextcloud, Vaultwarden) have **no native Guix service**, only OCI-container
wrapping or nothing at all. The plan below substitutes natively-packaged
alternatives where that's acceptable, rather than forcing OCI containers or
building large from-scratch packages.

## Current state (confirmed by inventory)

- **Hosts**: `box` (x86_64 desktop, full Guix System), `mintsystem` (dormant,
  never enabled), `reform` (aarch64 laptop, full Guix System, just finished).
- **docker/** on `box`: 5 podman-compose stacks — `ai` (ollama, open-webui,
  qdrant), `automation` (n8n, gotify), `nextcloud` (postgres, redis,
  nextcloud), `odoo` (postgres, odoo), `search` (searxng). Snapshot at
  research time: none auto-started (`feature-box-podman-compose` was
  commented out in `box.scm`) — since resolved, see Phase D item 7 below;
  only `automation` actually runs at boot today.
- **Containers**: `feature-podman` + `feature-distrobox` already used by both
  `box` and `reform` via shared `users/laszlokr.scm`; `fix-podman-storage-driver`
  in `configs.scm` already patches around podman's hardcoded btrfs assumption.
- **AI**: only `emacs-ellama` is installed, unconfigured (no init.el wiring).
  No `gptel`.
- **Terminal**: only `feature-foot` is configured. No Ghostty, no alacritty
  wiring (a stray unused `alacritty.yml` exists on disk).
- **sing-box**: already working on `box` and the Reform as clients, via the
  `rosenthal` channel's `sing-box-service-type`, connecting to a Hetzner VPS
  ("the VPN box") that currently runs the sing-box **server** side in Docker.

## Key decisions made this round

1. **Headscale is dropped.** VPN needs are already covered by sing-box
   (vless/vmess/hysteria2); Headscale would need a large from-scratch Go
   packaging effort for no real gain here.
2. **OCI-container Shepherd services (via the `gocix` channel) are acceptable
   as a fallback**, but native Guix packages/services are preferred where a
   reasonable substitute exists — this is why Nextcloud/Vaultwarden are
   replaced below rather than run via OCI.
3. **ClamAV is deferred.** Rspamd alone for the initial mail server; ClamAV
   needs a custom shepherd service (no service-type exists) and isn't worth
   blocking launch on.
4. **Pilot on a disposable third server first.** Before touching either
   production ARM box, stand up a brand-new Hetzner CAX instance purely to
   prove the remote-install flow works, using the same low-risk-first
   approach as the Reform bring-up (fallback path before anything
   irreversible).
5. **Topology confirmed**: "VPN box" = the existing sing-box server (Hetzner,
   currently Docker-based). "Mail box" is a separate, not-yet-provisioned
   Hetzner ARM (CAX) server. Both on Hetzner CAX (ARM) — the
   `hetzner-environment-type` / `guix deploy` community tooling found in
   research applies directly to both.

## Service substitutions (native-Guix-first)

| Originally planned | Guix status | Substitute used here | Why |
|---|---|---|---|
| Postfix | Not in Guix at all | **OpenSMTPD** (`opensmtpd-service-type`, native, real precedent: Ieong's "Guix as a mail server") | Only MTA with a real Guix path |
| Dovecot | Native (`dovecot-service-type`) | Dovecot, unchanged | Already fits |
| Rspamd/SpamAssassin | Rspamd native (`rspamd-service-type`, merged since the reference blog); SpamAssassin has no Guix path at all | **Rspamd** | Only one with Guix support |
| ClamAV | Package only, no service-type | Deferred | Custom shepherd service is real work; not launch-blocking |
| Headscale | No Guix path, large dependency tree | **Dropped** — sing-box already covers VPN | Avoids a speculative packaging project |
| WireGuard | Native, well-precedented | Not needed | sing-box covers this |
| Forgejo | No native service-type; only OCI via `gocix`, or a from-scratch stream (not upstreamed) | **Open decision at implementation time** — see below | Native git hosting alternatives exist but weren't compared against Forgejo's PR/issue UI yet |
| Uptime Kuma | Nothing packaged anywhere | **Custom lightweight monitor**: a small Guile/shell script + shepherd timer hitting endpoints, notifying via existing Gotify | Matches the actual stated need ("watch both boxes and the mail queue") without standing up Prometheus+Grafana for two boxes |
| Nextcloud | No server package, OCI-only via `gocix`/hand-rolled | **Syncthing** (native package+service, already on this repo's own remote-hosts wishlist in README) | Covers file sync without Nextcloud's PHP/dependency weight; loses calendar/contacts/office, which weren't confirmed as required |
| Vaultwarden | OCI-only via `gocix` | **KeePassXC + Syncthing** — sync the existing `.kdbx` (KeePassXC is already installed on `box`) instead of running any server | Zero new service needed at all; fully native |
| sing-box server | Native via `rosenthal` (already proven on `box`/Reform as client) | Move server side off Docker onto the same `sing-box-service-type` | Removes a whole Docker stack from the VPN box, reuses work already done |

Open decision, not resolved now: **Forgejo** — native alternatives
(`guix-forge`, a from-scratch minimalist git-forge project, or plain `cgit` +
SSH push with no web PR/issue UI) versus accepting an OCI-container Forgejo
via `gocix` for the fuller GitHub-like UI. Depends on whether `arcus` or
other projects need PR/issue workflows from collaborators — revisit when
this phase starts.

## Phased roadmap

### Phase A — Prove the remote-install process (disposable server)

Spin up a new, throwaway Hetzner CAX instance. Boot Hetzner's rescue image,
install Guix there, and run through the same class of procedure the Reform
used (`guix system init` from an existing running Linux, but chrooted onto a
freshly partitioned disk instead of installer media) — ideally using the
`hetzner-environment-type` patch for `guix deploy` found in research
(issues.guix.gnu.org #75144, `%hetzner-os-arm` template) rather than a fully
manual rescue-mode dance, since it already encodes the ARM/UEFI/grub-efi
specifics for this exact provider. Minimal config: hostname, networking,
SSH — no services yet. Goal: confirm the install/boot/reconfigure/rollback
cycle works on Hetzner's ARM offering with **no production risk**, and write
up what's learned the same way `doc/reform-install.md` and
`doc/reform-build-box.md` did.

Deliverable: `doc/hetzner-arm-install.md` (or similar), a working disposable
instance, confidence in the rescue→install→boot→rollback loop before either
real server is touched.

### Phase B — Migrate the mail box

New host file `src/configs/hosts/mailbox.scm` (naming TBD at implementation
time), modeled on `reform.scm`'s structure (host-specific features,
file-systems from the real provisioned disk, no desktop features at all —
this is a headless server, so most of `%laszlokr-features`/`rde-desktop`
does not apply; needs its own minimal feature set closer to
`rde-base`/`rde-cli` only).

Layer in, in order, testing each before adding the next:
1. OpenSMTPD (`opensmtpd-service-type`) — get basic mail flow working first.
2. Dovecot (`dovecot-service-type`) — IMAP.
3. Rspamd (`rspamd-service-type`) — spam filtering.
4. DNS records (SPF/DKIM/DMARC) — needs real domain access, out of scope for
   this repo but flagged since mail deliverability lives and dies on this.
5. Monitoring (the custom lightweight script/shepherd-timer above).
6. Forgejo or its alternative (open decision above).

Migrate via the Phase A technique, but this time against the real box's
existing data — back up whatever currently lives there first (this server
doesn't run mail today per the original framing, so likely low
existing-data risk, but confirm before wiping anything).

### Phase C — Migrate the VPN box

Currently running sing-box server-side in Docker. Migration order:
1. OS to Guix System (same Phase A technique, second time through — should
   be faster now that the process is proven).
2. sing-box server config via `rosenthal`'s `sing-box-service-type` —
   removes the Docker dependency entirely; box/reform's client config
   doesn't change (same server, same protocols), only how the server side
   is run.
3. Syncthing (native service) as the Nextcloud substitute.
4. KeePassXC `.kdbx` sync via the same Syncthing instance — no new service.

### Phase D — box's AI/automation stack

Not a server migration — `box` is already Guix System. Changes:

1. **Ollama → `llama-cpp`** (native Guix package, includes server mode,
   OpenAI-compatible API). No service-type exists yet — write a custom
   Shepherd service in `box.scm`, following the exact pattern already used
   for `feature-box-podman-compose` and the `sing-box-service-type` usage
   already in this repo (a `shepherd-service` with `make-forkexec-constructor`
   running `llama-server`). This removes the `ollama` container entirely.
2. **Emacs as primary LLM UI**: add `emacs-gptel` (native Guix package,
   confirmed maintained) alongside the already-installed `emacs-ellama`, and
   actually wire both up in `users/laszlokr.scm`'s init-el (today
   `emacs-ellama` is installed but unconfigured) — point both at the new
   native `llama-server` endpoint. gptel for ongoing chat, ellama for
   one-off task commands (summarize/translate/rewrite) — they're
   complementary, not redundant, per research.
3. **Open WebUI**: keep containerized for now, or drop it if Emacs fully
   covers the interactive-chat need once gptel is wired up — decide once
   gptel/ellama are actually in daily use.
4. **Qdrant, n8n, gotify**: no native Guix path found for any of them (Qdrant
   has no Guix package; n8n and Gotify are Node.js/Go apps with no Guix
   packaging effort found). Stay in podman-compose, unchanged. **Real
   blocker found enabling `automation` first**: `podman network create` is
   broken in this Guix build (confirmed bug in the podman 6.0.1/netavark
   1.14.1 pairing, not a config gap — see `docker/README.md`'s "Known
   issue" section). `automation` worked around it since n8n and gotify
   don't need to talk to each other, but the `ai` stack specifically
   (open-webui → ollama) does, and will hit this exact wall when enabled —
   root-causing/fixing this bug is a real prerequisite for `ai`, not
   optional.
5. **"Rhizome"** (a personal AI/knowledge-base project — Obsidian vault +
   book/article library search, a knowledge graph, signals dashboard) is
   being built in a separate session against a fixed, already-opinionated
   spec: SQLite + Neo4j Community Edition + Qdrant as a three-container
   Docker Compose stack, with embeddings/extraction originally spec'd as
   hosted-Anthropic+Voyage-only, no local inference, no Postgres. **That
   local-inference stance is now under active pushback**: `box`'s actual
   CPU (Ryzen 9 5900HX, corrected from an earlier wrong assumption) gives
   real local-inference headroom for at least the embedding step outright
   and the cleanup step probably, with extraction as a local-first,
   Claude-fallback candidate — see
   [local-hardware-roadmap.md](local-hardware-roadmap.md) for the
   per-task breakdown and benchmarks. If that pushback lands, rhizome
   would end up sharing the `llama-cpp` endpoint from item 1 above after
   all, rather than being fully independent of it. Its deployment target
   (the Hetzner VPS the spec describes vs. running locally on `box` via
   podman-compose, identical in shape to the `ai`/`nextcloud`/`automation`
   stacks already here) is still unresolved — see the same doc for the
   full reality-check against its spec, including two spec-vs-reality
   mismatches worth reconciling with whoever drives that session (it
   references a "WireGuard mesh" and "existing reverse proxy" that don't
   match this repo's actual sing-box-based VPN or confirmed absence of a
   reverse proxy).
6. **Honcho** (Plastic Labs' open-source agent memory/user-modeling
   service) is a new candidate for local agentic work, alongside rhizome.
   Docker Compose based, requires PostgreSQL+pgvector (hard requirement)
   and a mandatory LLM API key — but that key can point at any
   OpenAI-compatible endpoint, including the native `llama-cpp` server from
   item 1 once it exists, instead of a hosted key. Not packaged for Guix;
   would be a new `docker/honcho/compose.yml` stack matching the existing
   convention. Full detail in `local-hardware-roadmap.md`.
7. **Resolved**: `feature-box-podman-compose` now takes a `#:stacks`
   argument instead of hardcoding all five, and is enabled in `box.scm`
   scoped to just `automation` (n8n + gotify) for now — the rest stay off
   until there's an actual need for them. Add a stack's name to `#:stacks`
   when that changes; no further Guix-side work needed to bring the others
   up.

### Phase E — Terminal: Ghostty + ghostel

- **Ghostty** is not in Guix/nonguix/rosenthal (Zig dependency-vendoring
  blocks it upstream), but the **`saayix`** channel
  (`codeberg.org/look/saayix`) reportedly carries a working build. Lowest-risk
  path: add `saayix` as a fourth channel (same pattern as adding `rosenthal`
  for sing-box — pin a commit, verify authentication, add the package),
  rather than writing a from-scratch Zig-build-system package. Configure as
  the standalone terminal emulator on both `box` and the Reform, likely
  alongside (not replacing) `feature-foot` initially, to compare before
  committing.
- **ghostel** (`github.com/dakra/ghostel`) — a real, actively maintained
  Emacs package embedding a terminal via `libghostty-vt`, independent of the
  standalone Ghostty app. Its native module **auto-downloads on first use**,
  which conflicts with Guix's no-network-at-build-time model — packaging it
  properly means pinning that download as a fixed-output derivation (a real,
  somewhat fiddly packaging task, similar in spirit to problems already
  solved for other blob-fetching packages, but not yet attempted for this
  one). Treat as a **follow-on experiment after Ghostty itself is in place**,
  not part of this phase's critical path.

### Phase F — arcus / podman-compose dev workflow

No change recommended now. Research confirmed Guix has no drop-in
replacement for podman-compose's multi-service local-dev model (`guix
system container` and `guix shell --container` solve different problems).
Optional, non-blocking future improvement: use `guix pack -f docker` to
build `arcus`'s own service images reproducibly from Guix package
definitions instead of hand-written Dockerfiles, while keeping
podman-compose itself as the orchestration layer — revisit only if
Dockerfile reproducibility becomes an actual pain point.

## Risks and mitigations

- **Remote server migration risk**: mitigated by Phase A's disposable
  pilot, and by Hetzner Cloud's KVM/rescue console as the equivalent of the
  Reform's SD-card fallback — confirm console access works *before* wiping
  either production box.
- **Mail deliverability**: the hardest-to-get-right part of this whole plan;
  OpenSMTPD+Dovecot+Rspamd have a real precedent but DNS/DKIM/reputation
  setup is inherently fiddly and mostly outside this repo's scope. Budget
  real testing time (send/receive to real external addresses) before
  cutting over any existing mail flow.
- **Service substitutions change functionality, not just implementation**:
  Syncthing isn't Nextcloud (no calendar/contacts/web office), and
  KeePassXC+sync isn't Vaultwarden (no browser-extension-friendly hosted
  vault, no sharing between multiple people). Confirm these tradeoffs are
  acceptable in practice once Phase C is reached, not just in the abstract.
- **Ghostty via a third-party channel** (`saayix`) carries the same trust
  question as `rosenthal` — verify its channel introduction authenticates
  cleanly (same check already done for `rosenthal`) before relying on it.

## Immediate next step

Start with **Phase A**: provision a disposable Hetzner CAX instance and
prove the rescue-mode Guix System install/boot/rollback cycle, documenting
it the way `doc/reform-install.md` did. Everything else in this plan depends
on that working first.
