# Homelab Documentation

This folder documents the `infrastructure` repo: what runs where, how each piece is
provisioned, and how to operate it. The guiding principle (from the top-level README)
is **KISS**. Each tool does one job, and most things are plain files you can read.

| Page | What it covers |
|------|----------------|
| [Architecture](architecture.md) | Physical hosts, VMs, network/IP plan, DNS, how the layers fit together |
| [Terraform](terraform.md) | VM provisioning, Proxmox firewall, AdGuard DNS & filter lists |
| [Ansible](ansible.md) | Baseline host configuration roles, update playbooks, Semaphore |
| [Services](services.md) | Every Docker Compose stack, per host, with ports and volumes |
| [Operations](operations.md) | CI/CD, backups, monitoring/alerting, helper scripts, runbooks |
| [Known issues](known-issues.md) | Bugs, drift and security findings discovered while writing these docs |

## Repository layout

```
infrastructure/
├── .devcontainer/        # Alpine dev container with Terraform 1.16.3, Ansible, shellcheck
├── .github/workflows/    # Self-hosted CI: firewall, AdGuard DNS, Vaultwarden deploy
├── ansible/
│   ├── main.yml          # Baseline playbook applied to every host
│   ├── inventories/prod/ # hosts.yml – the source of truth for host IPs
│   ├── playbooks/        # update-server/ (OS patching + reboot)
│   ├── roles/            # ssh, bashrc, swapfile, update_motd, reboot, centreon_monitoring, ...
│   └── semaphore/        # Semaphore UI compose file (Ansible web runner)
├── docker/               # Docker Compose stacks, grouped by the host they run on
├── scripts/
│   ├── centreon/         # Nagios/Centreon check plugins + ntfy notification commands
│   └── proxmox/          # Backup, health-check and VM scheduling scripts for PVE hosts
├── terraform/prod/
│   ├── default/host-example/  # Template to copy when creating a new VM
│   ├── servers/<VMNAME>/      # One root module per VM (local state)
│   ├── network/               # Proxmox cluster firewall + security groups (CI-applied)
│   └── services/AdGuard/      # DNS rewrites (CI-applied) and filter lists
└── renovate.json         # Renovate keeps image tags & provider versions current
```

## Toolchain at a glance

| Layer | Tool | Notes |
|-------|------|-------|
| Hypervisor | Proxmox VE 9.1 (2 nodes) | `orion`, `orion-node02` |
| VM provisioning | Terraform + `telmate/proxmox` 3.0.2-rc10 | Cloud-init clones of a Debian/Alma template |
| Firewall | Terraform + `bpg/proxmox` 0.118.0 | Per-VM security groups, default-deny inbound |
| DNS | AdGuard Home, managed with `gmichels/adguard` | Local rewrites + block/allow lists |
| Config management | Ansible (run by hand or via Semaphore UI) | Users, SSH, SNMP, swap, MOTD |
| Workloads | Docker Compose (some Swarm variants) | One stack per directory |
| Monitoring | Centreon (SNMP + custom plugins), Prometheus, Grafana, Loki | Alerts go to ntfy.sh |
| CI/CD | GitHub Actions on a self-hosted runner | Terraform state is kept on the runner's disk |
| Dependency updates | Renovate (`config:recommended`) | Opens PRs that bump image tags / providers |

## Quick start

```bash
# Open the repo in the dev container (VS Code: "Reopen in Container"),
# or install terraform + ansible locally.

# Provision / change a VM
cd terraform/prod/servers/VLIMMICH
terraform init && terraform plan && terraform apply

# Apply the baseline config to one host (the reboot role is skipped here; see ansible.md)
ansible-playbook -i ansible/inventories/prod/hosts.yml ansible/main.yml \
  --limit immich --skip-tags reboot

# Patch every host one at a time
ansible-playbook -i ansible/inventories/prod/hosts.yml \
  ansible/playbooks/update-server/update_v2.yml
```

Firewall and AdGuard DNS changes are **not** applied by hand. You merge them to `main`
and CI applies them (see [Operations → CI/CD](operations.md#cicd)).
