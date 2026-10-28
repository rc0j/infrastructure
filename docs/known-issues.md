# Known issues & recommendations

These came up while reviewing the repo for the documentation (October 2026). They're
ordered by impact. Secret values are deliberately **not** reproduced here.

## 🔴 Security: credentials committed to Git

The repo is hosted at `github.com/rc0j/infrastructure`. `.gitignore` covers `*.tfvars`
and `*.env`, but these files are **tracked** anyway (they were added before the ignore
rules, or added with force):

| File | Contains |
|------|----------|
| `terraform/prod/servers/VLADGUARD-DNS1/terraform.tfvars` | Proxmox `root@pam` password (real value, not a placeholder) |
| `terraform/prod/servers/VLBITWARDEN/terraform.tfvars` | Proxmox `root@pam` password (real value) |
| `terraform/prod/services/AdGuard/adguard-dns/provider.tf` | AdGuard admin password hardcoded in the provider block |
| `docker/vlcentreon/pve/pve.yml` | Two `prometheus@pve` API token secrets |
| `docker/node01/phpipam/*.yml`, `docker/node01/obsidian-livesync/…` | Database passwords (look like defaults) |
| Several scripts and role defaults | ntfy topic names. Anyone who knows a topic can read and post to it. |

**Recommended fix:**

1. **Rotate** the Proxmox root password, the AdGuard admin password and both PVE API tokens.
   The repo is private, but anyone who has ever had access (collaborators, forks,
   clones, CI logs) has these values.
2. Stop tracking the files: `git rm --cached <file>`. The ignore rules already cover the tfvars.
3. In `adguard-dns/`, restore `variable "adguard_admin_password"` in `vars.tf` and use
   `password = var.adguard_admin_password`. CI already passes `TF_VAR_adguard_admin_password`.
4. Move `pve.yml` to `pve.yml.example` and gitignore the real one.
5. Remove the old values from history (`git filter-repo` or BFG). Rotating them is what
   actually protects you; rewriting history is just cleanup.
6. Consider a dedicated Proxmox API token for Terraform instead of `root@pam` with a
   password.

## 🟠 Ansible

- **`main.yml` reboots every host.** The `reboot` role isn't tagged `never`, so a run
  without tags reboots all hosts, including both hypervisors and DNS, at once. Use
  `tags: never, reboot` like the optional roles.
- **The `backup_proxmox` timer is never enabled.** The task enables `vm_backup.service`,
  which has `WantedBy=multi-user.target`. As a result the backup (and the VM shutdowns
  that go with it) **runs at every boot of orion**, while the Friday timer never starts.
  Enable `vm_backup.timer` instead (`enabled: true, state: started`) and drop the
  `[Install]` section from the service.
- **The backup schedule doesn't match its description.** The timer says Fri 03:00, but the
  role README and meta say Friday 23:30.
- **The backup ntfy URL is incomplete.** `snapshot_ntfy_channel` is just a topic name with
  no `ntfy.sh/` host, so the final `curl` fails and, because of `set -e`, the script exits
  with an error after the backup itself has finished.
- **The `ssh` role inserts file paths instead of keys.** The "Add public keys" task loops
  over `pub_files.files | map(attribute='path')`, so it writes `/home/…/x.pub` into
  `authorized_keys` rather than the key inside the file. Either read the files with
  `slurp` or `lookup('file')`, or remove the task. The role's `files/*.pub` aren't used at all.
- **`Protocol 2` is obsolete.** OpenSSH ≥ 7.4 ignores it, so it's harmless but can be removed.
- **`homelab.conf` (the SSH client config) is owned by the admin user with mode 600.** Files
  in `/etc/ssh/ssh_config.d/` should be `root:root 0644`. Otherwise other users, including
  root's own ssh in some setups, can't read it.
- **`update_v2.yml` checks the wrong OS family.** It checks `os_family == "Almalinux"`, but
  Ansible reports `RedHat` for Alma, so VLCENTREON never gets updated. The Alpine task
  passes `&&` through `command`, which doesn't use a shell; use `community.general.apk`
  or `shell`.
- **`centreon_monitoring` ignores its variable.** The community string is hardcoded in
  `snmpd.j2`, so `snmpd_community` has no effect. The play also restarts snmpd on every
  run instead of using a handler.
- **Unused settings and files.** `swap_swappiness` is never applied. `update_motd/templates/motd.j2`
  is never used. Several role READMEs are still the Galaxy boilerplate.

## 🟠 Scripts

- **`check_smart` crashes on every run.** `SATA_DISKS` is never defined and the script runs
  under `set -u`, so it dies with "unbound variable" after the NVMe loop. Centreon sees
  that as UNKNOWN. Define `SATA_DISKS=()`.
- **`bk-proxmoxconf.sh` skips the VM configs.** It quotes the glob
  `"/etc/pve/nodes/orion/qemu-server/*"`, so the glob never expands, and `…/lxc` is a
  directory, which the `-f` test skips. The VM and LXC configs, the most valuable part of
  the backup, are left out. Use `cp -r` over an unquoted glob or `tar` the directories directly.
- **Placeholders are still in the scripts.** `scripts/proxmox/mv-backup.sh` has
  `NTFY_CHANNEL="ntfy.sh/#"` and `check_temp.sh` has `WEBHOOK_URL="#"`.
- **`mv-backup.sh` starts the VMs only after every dump is done.** All the VMs stay down
  for the whole run. Starting each VM right after its own dump would shorten the downtime.
  If `vzdump` fails, `set -e` exits before any VM is restarted.
- **The ntfy scripts depend on the working directory.** They use `source ./ntfy-notification.env`;
  `source "$(dirname "$0")/ntfy-notification.env"` would work from anywhere.

## 🟡 Configuration drift

| Item | Source A | Source B |
|------|----------|----------|
| AdGuard VM IP | tfvars `192.168.100.5` | inventory/DNS/provider `192.168.100.97` |
| AdGuard VMID | tfvars `19205` | firewall `192105` |
| Bitwarden IP | tfvars `192.168.100.96` | inventory/compose `192.168.100.99` |
| orion-node02 IP | inventory `.122` | top-level README fastfetch shows `.22`; `homelab.conf` also has `node02 → .126` |
| Centreon | DNS `centreon-prod → vlcentreon (.107)` | `homelab.conf` `centreon-prod/centreon-new → 192.168.100.7` |
| MAC address | VLDRIVE `BC:24:11:A8:64:68` | VLIMMICH uses **the same MAC** (both on orion). That's an L2 conflict if both run on the same bridge. |
| VLDRIVE | directory/inventory name `vldrive` | VM `name = VLNEXTCLOUD`; SSH alias `docker` |
| Semaphore | `ansible/semaphore` (pinned, :3000) | `docker/node01/semaphore` (`:latest`, :4000) |

These usually come from the VM being changed in the Proxmox UI after Terraform created
it. Run `terraform plan` in each `servers/*` module to see how far it has drifted, then
update the tfvars to match reality (or the other way round).

## 🟡 Terraform & CI

- **The VM modules have no remote state.** Their state exists on one workstation only.
  Consider a shared backend, such as the same runner directory or an S3-compatible MinIO
  bucket.
- **The VM modules are copy-pasted.** Nine `main.tf`/`vars.tf` copies have already started
  to diverge. One module (`modules/proxmox_vm`) plus a small root module per VM, or a
  single root module with `for_each` over a map of VMs, would remove the duplication.
- **Leftover directories.** `VLABITWARDEN/` has no tfvars and looks like a leftover from
  `VLBITWARDEN/`. `VLNODE01/` has no tfvars in the repo.
- **Unpinned images in CI.** The workflows use `hashicorp/terraform:latest`, while the dev
  container pins 1.16.3. Pin the CI image to the same version.
- **No plan step on PRs.** Workflows run only on push to `main`, so the
  `if: github.event_name == 'push'` guards never filter anything and nobody sees a plan
  before merging. Adding a `pull_request` trigger that runs `plan` only would let you
  review changes first. A misleading comment says "updated to v4" next to
  `actions/checkout@v7`.
- **Unbounded provider version.** `gmichels/adguard` is constrained with `>= 1.7.0`. Pin it
  so Renovate controls upgrades.

## 🟡 Containers

- **Images Renovate can't update.** Several run on `:latest` (NPM standalone, Prowlarr,
  phpIPAM, CouchDB, Semaphore on node01, and the whole Prometheus/Grafana/Loki stack).
  Pin them so upgrades are deliberate and Renovate-driven.
- **The *arr apps run as root.** They use `PUID=0`. Create a `media` user and set
  PUID/PGID to match ownership of `/media`.
- **Radarr loses its config.** It has no `/config` volume, so its settings disappear when
  the container is recreated.
- **Obsolete Compose key.** `version: "3.9"` is ignored by Compose v2 and produces a
  warning; it can be removed.
