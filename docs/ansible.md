# Ansible

Everything lives under `ansible/`. There's no `ansible.cfg`, so pass the inventory
explicitly with `-i ansible/inventories/prod/hosts.yml`, or configure it in Semaphore.

## Inventory

`inventories/prod/hosts.yml` is the source of truth for which hosts Ansible manages:

| Host | IP | Group |
|------|----|-------|
| `orion` | 192.168.100.20 | physical |
| `orion-node02` | 192.168.100.122 | physical |
| `jellyfin` | 192.168.100.100 | virtual |
| `adguard` | 192.168.100.97 | virtual |
| `node01` | 192.168.100.98 | virtual |
| `bitwarden` | 192.168.100.99 | virtual |
| `immich` | 192.168.100.104 | virtual |
| `immich-ml` | 192.168.100.103 | virtual |
| `vlcentreon` | 192.168.100.107 | – |
| `dnsprod01` | 192.168.100.111 | – |
| `vldrive` | 192.168.100.101 | – |
| `minecraft-server` | 192.168.103.11 | – (reached with `ProxyJump=orion-node02`) |
| ~~`orion-nodepi`~~ | 192.168.100.21 | commented out |

The `physical` and `virtual` groups are handy for `--limit physical` and similar.
`vlcentreon`, `dnsprod01`, `vldrive` and `minecraft-server` are only in `all`.

## Baseline playbook: `main.yml`

`main.yml` runs on `hosts: all` and applies these roles in order:

| Role | Tag | Runs by default | What it does |
|------|-----|-----------------|--------------|
| `ssh` | `ssh` | ✅ | Creates the `sysmaster` group with passwordless sudo and the admin user `raif.coonjah`, deploys `authorized_keys`, a client-side `homelab.conf` SSH config with host aliases, `MaxAuthTries 3` and `Protocol 2`. Also sets `disable_root: false` in cloud-init. |
| `bashrc` | `bashrc` | ✅ | Puts a managed `/root/.bashrc` in place (red `host:path #` prompt, `EDITOR=vim`, `ls`/`ll`/`l` aliases) and keeps a backup of the old one |
| `swapfile` | `swapfile` | ✅ | Creates and enables a `/swapfile` (default 1G) if it doesn't exist, and adds it to fstab |
| `update_motd` | `update_motd` | ✅ | Installs figlet and writes `/etc/motd` as a figlet banner of the hostname |
| `reboot` | `reboot` | ⚠ ✅ | **Reboots the host unconditionally** |
| `centreon_monitoring` | `centreon_monitoring` | ✅ | Installs `snmpd`/`snmp`, writes `/etc/snmp/snmpd.conf` (UDP 161, read-only community) and enables and restarts snmpd |
| `backup_proxmox` | `never, backup_proxmox` | ❌ | Deploys the weekly VM backup script and a systemd service and timer (PVE hosts only) |
| `minimal_packages` | `never, minimal_packages` | ❌ | Installs byobu, vim, sudo, bash-completion, ncdu, netcat-traditional, cron |

> ⚠ The `reboot` role isn't tagged `never`, so **a plain `ansible-playbook main.yml`
> reboots every host in the inventory at the same time**, including both hypervisors. Run
> it with `--skip-tags reboot` unless that's what you want.

### Common invocations

```bash
INV=ansible/inventories/prod/hosts.yml

# Bootstrap a freshly provisioned VM (first run connects as root using the cloud-init key)
ansible-playbook -i $INV ansible/main.yml --limit immich -u root --skip-tags reboot

# Only refresh SSH keys/config everywhere
ansible-playbook -i $INV ansible/main.yml --tags ssh

# Deploy the backup timer to the primary hypervisor
ansible-playbook -i $INV ansible/main.yml --limit orion --tags backup_proxmox

# Install the extra packages
ansible-playbook -i $INV ansible/main.yml --tags minimal_packages
```

## Role reference

### `ssh`

| Variable | Default | Meaning |
|----------|---------|---------|
| `ssh_master_user` | `raif.coonjah` | Admin user that's created and added to `sysmaster` |
| `ssh_authkey_path` | `/home/raif.coonjah/.ssh` | Where `authorized_keys` goes |
| `ssh_hardening` | `true` | Turns on the `MaxAuthTries` and `Protocol` edits |

The authorized keys are written straight into `templates/authorized_keys.j2`. To grant or
revoke access, edit that template and re-run `--tags ssh`. `files/*.pub` also contains
`proxmox.pub` and `raif.coonjah.pub`, but no task reads them.

### `backup_proxmox`

| Variable | Default |
|----------|---------|
| `script_path` | `/usr/local/homelab/scripts` |
| `snapshot_ntfy_channel` | ntfy topic for the completion notification |
| `snapshot_path` | `/backup/weekly-backup` (currently unused by the template) |

It installs:

- `{{ script_path }}/mv-backup.sh`, which shuts down each VM in `VM_IDS`, runs
  `vzdump --compress zstd`, moves the `.vma.zst` files to `/backup`, prunes files older
  than one day, restarts the VMs and posts to ntfy.
- `/lib/systemd/system/vm_backup.service` (oneshot).
- `/lib/systemd/system/vm_backup.timer` (`OnCalendar=Fri *-*-* 03:00:00`, `Persistent=true`).

> The task enables the **service**, not the **timer**. See
> [known issues](known-issues.md#ansible). `vm-backup.j2` is an older variant that rsyncs
> to a remote host, and nothing deploys it.

### `swapfile`

`swap_size: 1G` and `swap_file: /swapfile`. `swap_swappiness: 1` is defined but no task applies it.

### `centreon_monitoring`

It only templates `snmpd.j2`. The community string is hardcoded in the template, and the
`snmpd_community` default isn't used.

## Update playbooks (`playbooks/update-server/`)

| Playbook | Behaviour |
|----------|-----------|
| `update.yml` | Debian only, runs on all hosts **in parallel**. Checks DNS (`nslookup proxy.core-forge.fyi`), checks that `/` and `/boot` each have more than 3 GB free, runs `apt upgrade` for all packages, then reboots (60 s warning, waits up to 300 s). |
| `update_v2.yml` | **Rolling** (`serial: 1`) and multi-distro. Requires more than 1 GB free on `/`. Upgrades with apt, yum or apk depending on the OS family, reboots, and if Docker is installed runs `/opt/container-updater.sh` (logged to `/var/log/container-updater.log`). |

Prefer `update_v2.yml`. Because it patches one host at a time, DNS and the hypervisors
never all go down together.

> `container-updater.sh` is expected to exist on the hosts but isn't in this repo.

## External roles

`roles/requirements.yml` lists two Git roles that aren't vendored:

```bash
ansible-galaxy install -r ansible/roles/requirements.yml -p ansible/roles
```

- `jellyfin_role` from `sxravan/ansible-role-jellyfin`
- `syncthing_role` from `raifcoonjah/syncthing`. Its entry in `main.yml` is commented out.

## Semaphore UI

[Semaphore](https://semaphoreui.com) is a web UI for running these playbooks. There are two compose files:

| File | Port | Image |
|------|------|-------|
| `ansible/semaphore/docker-compose.yml` | 3000 | `semaphoreui/semaphore:v2.19.17` (pinned, bumped by Renovate) |
| `docker/node01/semaphore/docker-compose.yml` | 4000 | `semaphoreui/semaphore:latest` (not currently running on node01) |

Both use SQLite in named volumes and set `ANSIBLE_HOST_KEY_CHECKING=False`. Change the
bootstrap admin password (`changeme`) after the first login.
