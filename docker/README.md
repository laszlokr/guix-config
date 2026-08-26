# Docker Compose stacks

Each subdirectory is a self-contained Docker Compose stack. Stacks named in
`feature-box-podman-compose`'s `#:stacks` argument in
`src/configs/hosts/box.scm` start automatically at boot as Shepherd
services — currently just `automation`. The others can still be run
manually (see below) until there's an actual need to have them running
unattended too.

## Prerequisites

### Storage layout

The compose files use bind mounts under `/data/docker/`.  Create this tree
before starting any stack:

```sh
sudo mkdir -p \
  /data/docker/odoo/{db,data} \
  /data/docker/nextcloud/{db,redis,html,data,config,apps,themes} \
  /data/docker/ai/{ollama,open-webui,qdrant} \
  /data/docker/automation/{n8n,gotify} \
  /data/docker/search/searxng
sudo chown -R 1000:1000 /data/docker   # adjust UID if needed
```

`/data/` is expected to be a dedicated SSD mount point.  Until the disk is
mounted, add a placeholder to `/etc/fstab` or create the directory on the
root filesystem temporarily.

Backups land in `/storage/backups/` — see `../scripts/backup.sh`.

### Secrets

```sh
cp docker/.env.template docker/.env
$EDITOR docker/.env   # fill in every TODO value
```

`docker/.env` is listed in `.gitignore` and must never be committed.

### Also required for root: podman config files Guix doesn't ship by default

`feature-box-podman-compose` runs `podman-compose` as root (Shepherd system
services default to root), and root's podman has none of the config files
`feature-podman`'s home-environment fix already gives `laszlokr` (see
`fix-podman-storage-driver` in `src/configs/configs.scm`). Confirmed missing
and required, in the order they surface:

```sh
sudo mkdir -p /etc/containers
sudo tee /etc/containers/registries.conf > /dev/null <<'CONF'
unqualified-search-registries = ["docker.io"]
CONF
sudo tee /etc/containers/policy.json > /dev/null <<'CONF'
{
    "default": [
        {
            "type": "insecureAcceptAnything"
        }
    ]
}
CONF
```

Without `registries.conf`, pulling any image with a short name (e.g.
`n8nio/n8n`, not `docker.io/n8nio/n8n`) fails with "short-name ... did not
resolve to an alias." Without `policy.json`, every image operation fails
with "no policy.json file found."

### Resolved: netavark's network setup was broken in this Guix build

**Fixed 2026-08-26** by moving the guix channel pin forward (see
`doc/local-hardware-status.md`) — `podman network create` now works, and the
`network_mode: host` workaround below has been reverted in
`docker/automation/compose.yml`. Left the diagnosis in place as a reference
in case this class of channel-drift bug recurs.

Confirmed (2026-08-12), and broader than it first looked. Started as
`podman network create` failing identically as root *and* as `laszlokr`:

```
error: unrecognized subcommand 'create'
Usage: netavark [OPTIONS] <COMMAND>
Error: netavark: : EOF
```

Working around *that* (attaching to the pre-existing default `podman`
bridge via `network_mode: bridge` instead of creating a custom network)
hit a second, deeper failure at actual container-start time:

```
Error: unable to start container "...": netavark: failed to load network
options: IO error: invalid type: sequence, expected a map at line 1 column ...
```

Isolated with the simplest possible case, no compose involved at all:

```sh
sudo podman run --rm alpine echo hello
```

fails the exact same way. **This confirms it's not specific to a custom
network, to compose, or to this stack — netavark's actual network-
attachment call is broken for every bridge-networked container on this
system.** It affects any podman use on `box`, not just these compose
stacks; `feature-podman`/`feature-distrobox` usage on `reform` should be
assumed affected too until checked.

### Root cause: a version mismatch in the pinned guix, fixed upstream

**Podman 6.0 requires netavark and aardvark-dns 2.0.0.** The pinned guix
(`8db8515a`, 2026-07-15) has podman 6.0.1 but netavark **1.14.1** and
aardvark-dns **1.17.0** — a full major version behind what podman 6 needs.
The pin caught guix mid-transition, after podman had been bumped to 6.x but
before its network backend followed.

That explains both symptoms precisely: podman 6 invokes subcommands
netavark 1.14 does not have (`unrecognized subcommand 'create'`), and hands
it a JSON schema it cannot parse (`invalid type: sequence, expected a map`).
The tell was visible in the package definitions all along — netavark and
aardvark-dns are released in lockstep upstream, yet guix had them at 1.14.1
and 1.17.0 respectively, which should not happen in a coherent set.

Current guix has the matched set: **podman 6.0.2, netavark 2.0.0,
aardvark-dns 2.0.0**. So the real fix is simply to move the pin forward:

```sh
make -B rde/channels-lock.scm     # regenerate; see the note in profiles.mk
```

Do that deliberately, not casually. Bumping the guix channel changes
*everything* on both hosts — kernel included — so it wants its own
reconfigure-and-verify cycle per machine, and on `reform` it means aarch64
substitute coverage has to be checked first (`make reform/weather`). It is
ordinary maintenance, but it is not a small change, which is why the
workaround below stays documented rather than deleted.

**Workaround: `network_mode: host` per-service**, which is what
`automation`'s `compose.yml` now does. Host networking shares the host's
network namespace directly, so no netns/netavark setup happens at all —
confirmed to sidestep the bug. Real costs, and this is genuinely a
workaround, not a fix:
- No per-container port remapping — a service listens on whatever port
  it's configured for internally, directly on the host. `automation`'s
  gotify needed an explicit `GOTIFY_SERVER_PORT: "8090"` added since it
  otherwise defaults to 80.
- Every host-networked container shares one network namespace, so ports
  must be manually kept unique across *all* simultaneously-running
  stacks, not just within one compose file.
- Container-to-container communication still works (they share the host's
  loopback), but must use `localhost`/`127.0.0.1`, not container-name DNS
  — `nextcloud` would need `POSTGRES_HOST: localhost` instead of `db`, for
  example.
- This is the general workaround for `nextcloud`, `ai`, `odoo`, and any
  future rhizome/Honcho stack too, not just `automation`.

Once the channel pin moves forward and bridge networking works again,
`automation`'s `compose.yml` can go back to a normal `networks:` stanza and
drop the `GOTIFY_SERVER_PORT` override — worth doing, since host networking
gives up isolation between stacks and forces manual port de-confliction
across all of them.

## Starting stacks manually

Run any stack from the repo root (the `--env-file` flag is required because
each stack's `compose.yml` lives in a subdirectory):

```sh
# Start a specific stack
docker compose --env-file docker/.env \
  --project-directory docker/odoo up -d

# Stop a stack
docker compose --project-directory docker/odoo down

# View logs
docker compose --project-directory docker/odoo logs -f
```

Or use the Shepherd services — named `podman-<stack>`, not `docker-<stack>`,
matching `feature-box-podman-compose`'s `provision` in `box.scm`:

```sh
sudo herd start podman-odoo
sudo herd stop  podman-nextcloud
sudo herd status podman-ai
```

Only stacks listed in `feature-box-podman-compose`'s `#:stacks` argument in
`box.scm` actually run as Shepherd services — currently just `automation`.
The rest can still be run manually via `docker compose`/`podman-compose` as
shown above; add a stack's name to `#:stacks` when it's ready to run
unattended at boot too.

**`herd status` showing `It is stopped (one-shot)` means success, not
failure.** These are one-shot services: `podman-compose up -d` starts the
containers and exits rather than staying resident, so Shepherd marks the
*service* stopped once the command has exited zero. The containers it
started keep running independently — check those with `sudo podman ps`,
which is the real health indicator, not `herd status`.

Each stack logs to `/var/log/podman-<stack>.log` (Shepherd-managed, via
the service's `#:log-file`). Check there first when a stack won't come up —
`herd status` alone will not show you why anything failed.

After changing a service definition in `box.scm`, `guix system reconfigure`
does not always reload a service that is currently in a failing state; use
`sudo herd restart podman-<stack>` rather than `herd start`, and note that
reconfigure sometimes prints a "you will need to reboot" hint for changes
it could not apply live.

## First-time service setup

Start stacks in dependency order — each stack is independent, but databases
must be initialised before the application container uses them:

1. `podman-odoo` — Odoo initialises its own DB on first start.
   Afterwards open `http://box:8069` and set the master password.
2. `podman-nextcloud` — Nextcloud auto-installs on first request to
   `http://box:8080`.
3. `podman-ai` — Pull an initial model:
   ```sh
   docker exec -it $(docker ps -qf name=ollama) ollama pull llama3.2
   ```
4. `podman-automation` — n8n is at `http://box:5678`,
   Gotify at `http://box:8090`.
5. `podman-search` — SearXNG is at `http://box:8888`.
   Update the `secret_key` in `docker/search/settings.yml` before starting.

## Ports (localhost only)

| Service       | Port  |
|---------------|-------|
| Odoo          | 8069  |
| Nextcloud     | 8080  |
| Ollama API    | 11434 |
| Open WebUI    | 3000  |
| Qdrant HTTP   | 6333  |
| Qdrant gRPC   | 6334  |
| n8n           | 5678  |
| Gotify        | 8090  |
| SearXNG       | 8888  |

All ports are bound to `127.0.0.1` — expose them externally via nginx.

## Adding OCA modules to Odoo

Clone the module repository into `docker/odoo/addons/`:

```sh
git clone https://github.com/OCA/account-financial-tools \
  docker/odoo/addons/account-financial-tools
```

Each subdirectory under `addons/` is gitignored individually (see
`.gitignore`).  Add the specific modules you want tracked as git submodules
if you need them pinned.

The `addons/` directory is bind-mounted into the container at
`/mnt/extra-addons`.  Restart Odoo and update the apps list after adding
modules.

## SSD mount plan

`/data/` and `/storage/` are expected on a dedicated data SSD.  Uncomment
and adjust the relevant `file-system` stanzas in
`src/configs/hosts/box.scm` once the disk is formatted and its UUID is
known.
