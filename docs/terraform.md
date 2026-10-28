# Terraform

All Terraform lives in `terraform/prod/` and is split into small, independent root
modules. There are **no shared modules and no remote backend**. Each directory has its own
state, so a mistake in one module can't affect another.

| Path | Provider | State | Applied by |
|------|----------|-------|------------|
| `default/host-example/` | telmate/proxmox 3.0.2-rc10 | – | Template only, never applied |
| `servers/<VM>/` | telmate/proxmox 3.0.2-rc10 | Local `terraform.tfstate` (gitignored) | By hand from a workstation |
| `network/` | bpg/proxmox 0.118.0 | Runner disk: `/var/local/terraform-state/firewall.tfstate` | CI (`orion-firewall.yml`) |
| `services/AdGuard/adguard-dns/` | gmichels/adguard ≥ 1.7.0 | Runner disk: `/var/local/terraform-state/adguard-dns.tfstate` | CI (`adguard-dns.yml`) |
| `services/AdGuard/adguard-list/` | gmichels/adguard ≥ 1.7.0 | Local | By hand |

## VM modules (`servers/`)

Every VM directory has the same four files:

| File | Purpose |
|------|---------|
| `main.tf` | One `proxmox_vm_qemu.cloudinit` resource (`count = 1`) |
| `vars.tf` | Variable declarations; `template` defaults to `debian-template-restore` |
| `version.tf` | Provider pin and the `proxmox` provider block (`pm_tls_insecure = true`) |
| `terraform.tfvars` | The per-VM values, **including the Proxmox password** (gitignored) |

What the resource does:

- Clones `var.template`, a cloud-init-enabled template on the target node.
- Uses a `virtio-scsi-pci` controller. The boot disk is `scsi0` (qcow2 on `local`, size
  `var.disksize`) and the cloud-init drive is `ide2`.
- Gives one `virtio` NIC on `var.bridge` (`vmbr0`) a fixed `var.macaddr`.
- Passes a static IP through `ipconfig0` (`ip=192.168.100.X/24,gw=192.168.100.1`).
- Injects root SSH keys (`ssh_user = "root"`, `sshkeys`). Ansible uses these keys for its
  first run.

The `cores`, `memory`, `vmid`, `name` and `onboot` values come from tfvars. The `name`,
`vmid`, `memory`, `ipconfig0`, `macaddr` and `ssh_keys` variables are **lists** indexed by
`count.index`, so the module could in principle create several VMs. Today every one sets
`count = 1`. The `docker_vm` variable is declared but never used.

### Creating a new VM

```bash
cp -r terraform/prod/default/host-example terraform/prod/servers/VLNEWHOST
cd terraform/prod/servers/VLNEWHOST
# Copy version.tf/vars.tf from an existing server instead if you need ssh_keys/scsihw
$EDITOR terraform.tfvars     # name, vmid (192<octet>), ip, unique MAC, template, sizing
terraform init
terraform plan
terraform apply
```

After it boots:

1. Add the host to `ansible/inventories/prod/hosts.yml` and run `ansible/main.yml` against it.
2. Add a DNS rewrite to `services/AdGuard/adguard-dns/dns.tf` and merge to `main`.
3. If the VM needs a firewall, add a security group in `network/firewall.tf`.
4. Add the IP and MAC to phpIPAM, and add it to Centreon.

> `host-example` is older than the server modules. It doesn't have `scsihw`, `ssh_keys`
> or the `network.id` argument. Copying an existing `servers/*` directory is the safer
> starting point.

### Templates in use

| Template | OS | Used by |
|----------|----|---------|
| `debian-template-restore` | Debian (cloud-init) | Most VMs |
| `template-generic-alma-9.8` | AlmaLinux 9.8 | VLCENTREON (Centreon packages target EL) |
| `bookworm-template` | Debian 12 | Default in `host-example` only |

## Network – Proxmox firewall

File: `terraform/prod/network/firewall.tf`. It authenticates to `orion` as `root@pam`, with
the password taken from `TF_VAR_proxmox_admin_password`.

The pattern for each protected VM:

```hcl
resource "proxmox_virtual_environment_cluster_firewall_security_group" "<svc>_sg" { ...rules... }
resource "proxmox_virtual_environment_firewall_options" "<svc>_policy" {   # enable + DROP inbound
  node_name = "orion"; vm_id = <id>; enabled = true; input_policy = "DROP"
}
resource "proxmox_virtual_environment_firewall_rules" "<svc>_vm_rules" {   # attach the group
  rule { type = "in"; security_group = <svc>_sg.name }
}
```

### Allowed inbound ports

| Group | VMID | TCP | UDP | Other |
|-------|------|-----|-----|-------|
| `vaultwarden-sg` | 19299 | 22, 8000 (Vaultwarden), 161 | 161 | ICMP |
| `immich-sg` | 192104 | 22, 2283 (Immich), 161 | 161 | ICMP |
| `adguard-sg` | 192105 | 22, 53, 3000 (AdGuard UI) | 53, 161 | ICMP |
| `vlnode01-sg` | 19298 | 22, 80, 443, 81 (NPM admin), 8080 (phpIPAM), 9100 (node_exporter), 8082 (cAdvisor), 5984 (CouchDB/Obsidian), 8384 (Syncthing UI), 22000, 21027, 22067, 22068 (Syncthing) | 161, 22000, 21027, 22067 | ICMP |

All groups allow every outbound connection. Every rule sets `log = "info"`, so accepted
packets show up in the Proxmox firewall log.

**To change a rule**, edit `firewall.tf`, open a PR and merge it to `main`. The
`terraform_firewall_update` workflow then plans and applies the change. Don't run
`terraform apply` locally in `network/`, because the authoritative state file is on the
CI runner.

## AdGuard

### `adguard-dns/`: local DNS records

`dns.tf` keeps a `locals.dns_records` map of `name => answer` and turns each entry into an
`adguard_rewrite` with `for_each`. To add a record, add one line to the map and merge to
`main`. The `adguard_dns_update` workflow applies it.

### `adguard-list/`: filter lists

These are `adguard_list_filter` resources, applied by hand (`terraform apply
-var-file=secrets.tfvars`):

| Type | Lists |
|------|-------|
| Blocklists | OISD Big, AdGuard HostlistsRegistry filters 10, 11, 61 |
| Allowlists | GoodnessJSON (main, referral-sites, optional), O365 whitelist, a Mauritius allowlist gist and a custom gist (both owned by `rc0j`) |

## Conventions and tips

- Provider versions are pinned exactly (`3.0.2-rc10`, `0.118.0`), and Renovate opens PRs
  to bump them.
- `.terraform/` and the lock files are gitignored, so every `terraform init` re-downloads
  the providers (~20 MB per module).
- State files are gitignored. The state for each `servers/*` module exists **only on the
  machine that last applied it**, so back up `terraform/prod/servers/*/terraform.tfstate`
  or move to a remote backend (see [known issues](known-issues.md)).
