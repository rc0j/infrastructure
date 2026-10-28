# Operations

## CI/CD

All workflows run on a **self-hosted GitHub Actions runner** on node01
(`actions.runner.rc0j-infrastructure.node01-runner`, user `github-actions`). They trigger
on `push` to `main` when the relevant paths change. Every change should go through a PR,
because merging to `main` *is* the deploy.

| Workflow | Trigger paths | What it does |
|----------|---------------|--------------|
| `orion-firewall.yml` (`terraform_firewall_update`) | `terraform/prod/network/**` | Runs Terraform in a `hashicorp/terraform` container: restores state, `init`, `plan -out`, `apply`, then saves state |
| `adguard-dns.yml` (`adguard_dns_update`) | `terraform/prod/services/AdGuard/adguard-dns/**` | Same pattern for the DNS rewrites |
| `vaultwarden.yml` | `docker/vaultwarden-docker/{docker-compose.yml,update_vaultwarden.sh}` | SSHes to the `bitwarden` host and runs `update_vaultwarden.sh` |

### How Terraform state is handled in CI

The runner host mounts `/var/local/terraform-state` into the job container as
`/opt/terraform-state`. Before `init`, the job copies `<name>.tfstate` into the module
directory, and after `apply` it copies it back:

| Module | State file on runner host |
|--------|---------------------------|
| `network/` | `/var/local/terraform-state/firewall.tfstate` |
| `services/AdGuard/adguard-dns/` | `/var/local/terraform-state/adguard-dns.tfstate` |

**Back up `/var/local/terraform-state`.** If those files are lost, the next run will try
to create resources that already exist.

### Secrets and variables

| Name | Type | Used by |
|------|------|---------|
| `PROXMOX_ADMIN_PASSWORD` | secret | Firewall workflow, as `TF_VAR_proxmox_admin_password` |
| `ADGUARD_ADMIN_PASSWORD` | secret | AdGuard workflow, as `TF_VAR_adguard_admin_password` |
| `VAULTWARDEN_HOST` | secret | SSH user for `<user>@bitwarden` |
| `VAULTWARDEN_UPDATE_DIR` | variable | Path to `update_vaultwarden.sh` on the host |

The runner needs an SSH key it can use to reach `bitwarden`, and it must be able to
resolve that name (through AdGuard or the `homelab.conf` SSH alias).

### Renovate

`renovate.json` extends `config:recommended`. Renovate opens PRs that bump pinned Docker
image tags (Vaultwarden, Jellyfin, Semaphore, *arr apps, NPM swarm) and Terraform provider
versions. Renovate can't bump anything pinned to `:latest`, so those images only change
when someone pulls them by hand.

The Vaultwarden release flow from end to end: Renovate opens a PR for the new tag →
you merge it → `vaultwarden.yml` runs → the host pulls, backs up, upgrades and
health-checks, rolling back if the check fails → ntfy notifies you.

## Backups

| What | How | Where | When |
|------|-----|-------|------|
| VMs on `orion` | `mv-backup.sh` (from the `backup_proxmox` role): shut down → `vzdump` zstd → start | `/backup` on orion, 1-day retention | systemd timer, Fridays 03:00 |
| VMs + LXCs (manual variant) | `scripts/proxmox/mv-backup.sh` (VMs 19205, 19207, 192100; CTs 1108, 1199) | `/backup/weekly-backup` | Manual or cron |
| LXC only | `scripts/proxmox/mv-backup-lxc.sh` (CT 1111) | `/backup/weekly-backup` | Manual or cron |
| PVE host config | `scripts/proxmox/bk-proxmoxconf.sh`: tars `/etc/network/interfaces`, hosts, resolv.conf, passwd, scripts, root bashrc, VM configs | `/backup/proxmoxconf/weekly`, keeps the latest 3 | Manual or cron |
| Vaultwarden vault | `backup.sh`: `bw export` as encrypted JSON → zstd → rsync | Syncthing node `/home/syncthing/bitwarden_export` | Before every upgrade, plus whenever it's scheduled on the host |

> These are **cold** backups. Each VM is shut down while it's being dumped (with a 25 s
> wait for VMs and 15 s for LXCs), so expect a few minutes of downtime per VM in the
> backup window. Only one day of history is kept on `/backup`, so keep a copy off the
> host as well, for example by syncing `/backup` with Syncthing.

### Restoring a VM

```bash
# on the PVE node
qmrestore /backup/vzdump-qemu-<vmid>-<date>.vma.zst <vmid> --storage local
qm start <vmid>
```

For an LXC, use `pct restore <ctid> /backup/weekly-backup/vzdump-lxc-<ctid>-<date>.tar.zst`.

### Restoring Vaultwarden data

Decompress the newest export (`zstd -d <file>.json.zst`) and import it in the web vault
under *Tools → Import data → Bitwarden (json, encrypted)*, using `BW_EXPORT_PASS`.

## Monitoring & alerting

There are two complementary systems, both on VLCENTREON:

1. **Centreon** checks whether things are up, using SNMP and plugins.
   - Every host gets `snmpd` from the `centreon_monitoring` Ansible role, and each firewall
     group allows 161/udp.
   - Custom plugins live in `scripts/centreon/` and are deployed to
     `/usr/lib/centreon/plugins/`.
   - Notifications go out through `ntfy-notification-v2.sh`. It maps the Centreon state to
     an ntfy priority (CRITICAL/DOWN → urgent, WARNING → high, UNKNOWN → default,
     OK/UP → low).
2. **Prometheus, Grafana and Loki** handle metrics, dashboards and logs (see
   [services.md](services.md#observability-dockervlcentreon)).

All alerts go to topics on the public **ntfy.sh** server. Subscribe to them in the ntfy app.

| Source | Topic stored in |
|--------|-----------------|
| Centreon notifications | `scripts/centreon/ntfy-notification.env` (gitignored) |
| Vaultwarden upgrade | `NTFY_TOPIC` in `update_vaultwarden.sh` |
| Proxmox backups | `snapshot_ntfy_channel` (role default) / `NTFY_CHANNEL` in the scripts |
| CPU temperature | Discord webhook in `check_temp.sh` (`WEBHOOK_URL`) |

## Script reference

### `scripts/centreon/`

| Script | Usage | Checks |
|--------|-------|--------|
| `check_uri` | `check_uri [-t timeout] [-k] [-f urls.txt] URL...` | CRITICAL if any URL doesn't return 2xx/3xx. `-k` skips TLS verification. The file takes one URL per line and supports `#` comments. |
| `check_syncthing` | `check_syncthing <host> <port>` | Health endpoint, internal errors, at least one connected device, all folders in sync. Reads the API key from `/usr/lib/centreon/plugins/.env_syncthing`. Needs `jq`. |
| `check_smart` | `check_smart` | NVMe available spare vs threshold for `/dev/nvme0n1` and `/dev/nvme1n1`, plus a SATA SMART check. Needs `nvme-cli`. |
| `ntfy-notification-v2.sh` | `… "$HOSTNAME$" "$SERVICEDESC$" "$STATE$" "$OUTPUT$" "$DATE$ $TIME$"` | Centreon notification command. Exits non-zero if ntfy doesn't return 2xx. |
| `ntfy-notification.sh` | `… <title> <message> <priority>` | Older, simpler version |

Both ntfy scripts run `source ./ntfy-notification.env`, so they have to be started with
the plugin directory as the working directory.

### `scripts/proxmox/`

These run on the PVE hosts from `/usr/local/homelab/scripts/`.

| Script | Purpose |
|--------|---------|
| `mv-backup.sh` | Cold backup of VMs and LXCs in one run (see Backups) |
| `mv-backup-lxc.sh` | Cold backup of LXCs only |
| `bk-proxmoxconf.sh` | Archives the host's config files and keeps the 3 newest |
| `check_nvme.sh <dev>` | Nagios-style NVMe check: spare ≤ threshold → CRITICAL; wear ≥ 80% → WARNING, ≥ 90% → CRITICAL. Prints perfdata. |
| `check_temp.sh` | Reads `sensors` "Package id 0" and posts a Discord embed at ≥ 70 °C (warning) or ≥ 85 °C (critical). Says nothing when the temperature is normal. |
| `vm_schedular.sh` | **Toggles** every VM tagged `not_always_on` or `ondemand`: a running one is shut down and a stopped one is started. Schedule it twice from cron, once to start and once to stop. |
| `archive/` | Older versions of the backup scripts, kept for reference |

Example cron entries for the scheduler (run as root on a PVE node):

```cron
0 8  * * * /usr/local/homelab/scripts/vm_schedular.sh   # start on-demand VMs
0 23 * * * /usr/local/homelab/scripts/vm_schedular.sh   # stop them again
```

## Runbooks

**Add a DNS name.** Add `"name" = "ip"` to `terraform/prod/services/AdGuard/adguard-dns/dns.tf`,
open a PR and merge it. Then check with `nslookup name 192.168.100.97`.

**Open a firewall port for a VM.** Add a `rule {}` block to that VM's security group in
`terraform/prod/network/firewall.tf`, open a PR and merge it. Then check the *Firewall* tab
for the VM in the Proxmox UI.

**Patch everything.** Run `ansible-playbook -i ansible/inventories/prod/hosts.yml
ansible/playbooks/update-server/update_v2.yml`. It works through the hosts one at a time
and reboots each one.

**Upgrade Vaultwarden by hand.** SSH to `bitwarden` and run `bash <repo>/docker/vaultwarden-docker/update_vaultwarden.sh`.

**Rotate SSH keys.** Edit `ansible/roles/ssh/templates/authorized_keys.j2`, then run
`ansible-playbook … main.yml --tags ssh`.

**Dev environment.** Open the repo in the dev container. It's Alpine-based, installs
Terraform 1.16.3, Ansible, shellcheck, git and curl, and adds the VS Code Terraform,
Ansible, YAML, ShellCheck and GitLens extensions.
