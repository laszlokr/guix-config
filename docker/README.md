# Docker Compose stacks

Each subdirectory is a self-contained Docker Compose stack managed as a
Shepherd system service on `box` (HX90).  The stacks start automatically
at boot in the order defined in `src/configs/hosts/box.scm`.

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

Or use the Shepherd services:

```sh
sudo herd start docker-odoo
sudo herd stop  docker-nextcloud
sudo herd status docker-ai
```

## First-time service setup

Start stacks in dependency order — each stack is independent, but databases
must be initialised before the application container uses them:

1. `docker-odoo` — Odoo initialises its own DB on first start.
   Afterwards open `http://box:8069` and set the master password.
2. `docker-nextcloud` — Nextcloud auto-installs on first request to
   `http://box:8080`.
3. `docker-ai` — Pull an initial model:
   ```sh
   docker exec -it $(docker ps -qf name=ollama) ollama pull llama3.2
   ```
4. `docker-automation` — n8n is at `http://box:5678`,
   Gotify at `http://box:8090`.
5. `docker-search` — SearXNG is at `http://box:8888`.
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
