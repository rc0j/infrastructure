# Services (Docker)

Each directory under `docker/` holds one Compose stack, grouped by the host it runs on.
To deploy one, copy or clone the directory onto the host and run `docker compose up -d`.
Stacks that need secrets come with an `.env-example`. Copy it to `.env` (gitignored)
and fill it in.

Timezone everywhere is `Indian/Mauritius`.

## Port map

| Host | Port | Service |
|------|------|---------|
| node01 (.98) | 80 / 443 / 81 | Nginx Proxy Manager (HTTP / HTTPS / admin) |
| node01 | 8080 | phpIPAM |
| node01 | 5984 | CouchDB (Obsidian LiveSync) |
| node01 | 4000 | Semaphore UI *(compose in repo, not currently running)* |
| node01 | 8384, 22000, 21027 | Syncthing *(not in repo)* |
| node01 | 8082 / 9100 | cAdvisor / node_exporter *(compose in `/opt/node01/monitoring-agents`, not in repo; scraped by Prometheus)* |
| node01 | – (outbound only) | Grafana Alloy (ships NPM logs), Komodo Periphery (managed from Komodo Core on .101), GitHub Actions self-hosted runner *(not in repo)* |
| bitwarden (.99) | 8000 (bound to 192.168.100.99) | Vaultwarden |
| jellyfin (.100) | 8096 (host network) | Jellyfin |
| jellyfin | 5055 | Seerr (requests) |
| jellyfin | 7878 / 8989 / 9696 / 8191 | Radarr / Sonarr / Prowlarr / FlareSolverr |
| vlcentreon (.107) | 3000 | Grafana |
| vlcentreon | 127.0.0.1:9090 | Prometheus (local only) |
| vlcentreon | 3100 | Loki |
| vlcentreon | 9100 (host) | node_exporter |
| immich (.104) | 2283 | Immich *(compose not in repo)* |
| adguard (.97) | 53 / 3000 | AdGuard Home DNS / UI *(not in repo)* |

---

## node01: `docker/node01/`

### Nginx Proxy Manager: `nginx/`

The reverse proxy and Let's Encrypt front end for the lab.

- `docker-compose.yml` is the standalone version (`jc21/nginx-proxy-manager:latest`), with
  `./data` and `./letsencrypt` bind mounts.
- `npm-swarm.yml` is the Docker Swarm version: it's pinned to `2.15.1`, uses
  ingress-mode ports and the external overlay `swarm-ingress-bridge`, and has a placement
  constraint of `node.hostname == VLNODE01` because the data lives on that host under
  `/opt/nginx-proxy-manager/docker-node01-stack/nginx/`.

```bash
docker stack deploy -c npm-swarm.yml npm      # swarm variant
```

### phpIPAM: `phpipam/`

IP address management, with a MariaDB 10.11 database, the web UI on `:8080` and a cron
container that scans subnets (every 1h, or every 2h in the swarm file). `ipam-swarm.yml`
is the swarm version. It uses **external** volumes `phpipam_phpipam-db` and
`phpipam_phpipam-logo`, which are the volumes the plain Compose stack created, so you can
move from Compose to Swarm without losing data.

### Obsidian LiveSync: `obsidian-livesync/`

`couchdb:latest` on `:5984` runs as UID 5984, with data in `./couchdb-data` and config in
`./couchdb-etc`. It's the sync backend for the Obsidian LiveSync plugin.

### Semaphore: `semaphore/`

See [ansible.md → Semaphore UI](ansible.md#semaphore-ui).

---

## Vaultwarden: `docker/vaultwarden-docker/`

Runs on VLBITWARDEN (192.168.100.99). This is the most automated stack in the repo.

| File | Purpose |
|------|---------|
| `docker-compose.yml` | `vaultwarden/server:<pinned>`, runs as UID/GID 1003, data in `./vw-data`, listens only on `192.168.100.99:8000` |
| `.env-example` | `ADMIN_TOKEN`, `INSTALL_ID`, `INSTALL_KEY` (Bitwarden push relay), `DOMAIN_URL` |
| `backup.sh` | Exports the vault with the `bw` CLI as encrypted JSON, compresses it with `zstd -19`, then rsyncs it to the Syncthing node (`/home/syncthing/bitwarden_export`) |
| `backup.env-example` | `BW_SERVER`, `BW_USERNAME`, `BW_PASSWORD`, `BW_EXPORT_PASS`, `SYNCTHING_SERVER` |
| `update_vaultwarden.sh` | Safe upgrade with rollback; see below |

On the host, the repo is checked out under `/home/vaultwarden/vaultwarden-docker`
(that's the path `backup.sh` sources its env file from).

### Upgrade flow (`update_vaultwarden.sh`)

```
record current git commit + running image
  → git pull --ff-only origin main
  → read target image from `docker compose config`
  → same image?  exit 0 (nothing to do)
  → docker compose pull
  → backup.sh            (abort + urgent ntfy if it fails)
  → docker compose up -d --pull never
  → wait for container running + GET http://192.168.100.99:8000/alive (10 × 3 s)
      ✓ notify "updated successfully"
      ✗ git reset --hard <previous commit> → up -d → re-check health
          ✓ notify "rollback successful"
          ✗ notify "ROLLBACK FAILED – manual intervention" and exit 1
```

Every failure path sends an ntfy notification at `high` or `urgent` priority. The script
is normally triggered by CI when Renovate bumps the image tag (see
[operations.md](operations.md#cicd)).

---

## Media: `docker/jellyfin/`

Runs on the `jellyfin` VM (192.168.100.100). Media lives under `/media`.

| Stack | Image | Port | Volumes |
|-------|-------|------|---------|
| `jellyfin/` | `jellyfin/jellyfin:<pinned>` | host network (8096) | `./config`, `./cache`, `/media`; memory limit 2.1G, reservation 400M |
| `arr-stack/jellystreer/` | `seerr/seerr` | 5055 | `./config`; has a healthcheck |
| `arr-stack/radarr/` | `linuxserver/radarr` | 7878 | `/media/movies`, `/media/download` |
| `arr-stack/sonarr/` | `linuxserver/sonarr` | 8989 | `./config`, `/media/tvshows`, `/media/anime`, `/media/download` |
| `arr-stack/polarr/` | `linuxserver/prowlarr:latest` | 9696 | `./config` |
| `arr-stack/polarr/flarersolver/` | `flaresolverr` | 8191 | `./config` |

The flow: Seerr takes requests, Radarr and Sonarr search through Prowlarr (which uses
FlareSolverr for Cloudflare-protected indexers), and a download client (qBittorrent,
referenced in comments but not in the repo) downloads into `/media/download`. The *arr
apps then move finished files into the library folders that Jellyfin serves.

`JELLYFIN_DOMAIN` in `.env` sets `JELLYFIN_PublishedServerUrl`.

> The *arr containers run with `PUID=0/PGID=0` (root). A comment says this is temporary.
> The Radarr compose file doesn't mount a `/config` volume, so its settings disappear
> whenever the container is recreated.

---

## Observability: `docker/vlcentreon/`

Runs on VLCENTREON (192.168.100.107) next to the native Centreon install. Compose project
name: `vlcentreon-dashboard`.

| Service | Image | Purpose |
|---------|-------|---------|
| `prometheus` | `prom/prometheus:latest` | Scrapes every 30 s and keeps 90 days. Bound to `127.0.0.1:9090`. |
| `grafana` | `grafana/grafana:latest` | Dashboards on `:3000`. Admin password comes from `GRAFANA_ADMIN_PASSWORD` in `.env`. Datasources are provisioned automatically. |
| `pve-exporter` | `prompve/prometheus-pve-exporter` | Proxmox API metrics, using API tokens from `pve/pve.yml` |
| `loki` | `grafana/loki:latest` | Log store on `:3100`. Single node, filesystem TSDB schema v13, 30-day retention |
| `node-exporter` | `prom/node-exporter` | Host metrics for the Centreon VM itself (host network/pid) |

**Prometheus scrape targets** (`prometheus/prometheus.yml`):

| Job | Target |
|-----|--------|
| `centreon-vm` | `host.docker.internal:9100` |
| `proxmox-nodes` | `192.168.100.20:9100` (pve1), `192.168.100.122:9100` (pve2) |
| `vlnode01` | `192.168.100.98:9100` |
| `cadvisor` | `192.168.100.98:8082` |
| `pve-exporter-1/2` | PVE API on each node, scraped through `pve-exporter:9221/pve` |

The Grafana datasources (`grafana/provisioning/datasources/ds.yml`) are Prometheus
(default) and Loki. Grafana Alloy on node01 ships the Nginx Proxy Manager logs to Loki,
but its config (`/opt/node01/monitoring-agents/alloy/config.alloy`) isn't in the repo yet.

**Prerequisites:** node_exporter on both PVE hosts and on node01, and a `prometheus@pve`
user with a `monitoring` API token on each PVE node.
