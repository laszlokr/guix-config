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

### Known issue: `podman network create` is broken in this Guix build

Confirmed (2026-08-12): `podman network create` fails identically as root
*and* as `laszlokr` — not a missing-config issue, a real bug in this
channel's podman/netavark pairing (podman 6.0.1, netavark 1.14.1, both
pinned in `gnu/packages/containers.scm`/`gnu/packages/rust-apps.scm` at the
same commit — not a version-skew problem):

```
error: unrecognized subcommand 'create'
Usage: netavark [OPTIONS] <COMMAND>
Error: netavark: : EOF
```

`podman network ls` and the pre-existing default `podman` bridge network
both work fine — only *creating a new* named network is broken. Something
in this build invokes netavark with a podman-level verb it was never meant
to receive (`create` isn't one of netavark's own subcommands in any
version — those are `setup`/`teardown`/`update`/`firewalld-reload`), most
likely a `network_cmd_path`-style misconfiguration rather than anything
fixable via a local `containers.conf` tweak. Not yet root-caused further or
reported upstream.

**Workaround, only viable when a stack's services don't need to talk to
each other**: use `network_mode: bridge` per-service (attaches to the
existing default `podman` bridge) instead of a custom `networks:` stanza,
which is what `automation`'s `compose.yml` does — n8n and gotify are
independent services with no need for a shared private network. This does
**not** work for stacks whose services must reach each other by container
name over a private network — `nextcloud` (app → db, app → redis), `ai`
(open-webui → ollama), `odoo` (app → db), and any future rhizome/Honcho
stack all need that and will hit this exact bug when enabled. Root-causing
and fixing (or reporting) this is a real prerequisite before any of those
can actually run, not just a config step like the two above.

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
