# remote-dev-servers

GitOps-managed remote Linux development VMs on Google Cloud.

A YAML file describes a VM. A GitHub Actions workflow spins it up. Another spins it down. State persists across spin-ups via a separate persistent disk. Connectivity is private-only via GCP Identity-Aware Proxy (IAP) — no public IP, no public SSH. Multiple human users share one VM, each with their own POSIX account and full sudo (including `sudo -i -u <other_user>`).

## Stack

- **Terraform** — infra provisioning, remote state in GCS
- **Ansible** — OS config, user management, idempotent
- **Nix** — declarative dev toolchain on the persistent disk
- **GitHub Actions + Workload Identity Federation** — no long-lived service-account keys
- **Cloud Identity Free** — Google identities at `intelops.dev` (primary) and `intelops.ai` (secondary) gate IAP access

## Repository layout (after all phases)

```
.
├── .github/workflows/    # up / down / reconfigure / plan / nuke
├── instances/            # YAML config — one file per VM (user-facing)
├── terraform/            # modules + envs
├── ansible/              # roles + playbooks
├── nix/                  # flake.nix dev environment
├── scripts/              # YAML → tfvars, inventory rendering
└── docs/                 # phase-by-phase build runbook
```

## Build phases

Each phase is independently reviewable and produces a working slice. Status reflects what lives in `main` right now.

| Phase | Title | Status |
|---|---|---|
| 0 | One-time bootstrap (Cloud Identity + GCP + GitHub) | Documented in [`docs/phase-0-bootstrap.md`](docs/phase-0-bootstrap.md) |
| 1 | Networking module (VPC, Cloud NAT, IAP firewall) | In progress — see [`docs/phase-1-networking.md`](docs/phase-1-networking.md) |
| 2 | Data disk + Compute modules | Pending |
| 3 | IAM module (IAP principals, VM runtime SA) | Pending |
| 4 | Ansible base (users, sudo, sshd, auditd + log shipping, TOTP) | Pending |
| 5 | Nix + dev environment | Pending |
| 6 | YAML → tfvars glue + GitHub Actions workflows | Pending |
| 7 | Hardening & polish | Pending |

Start here: [`docs/phase-0-bootstrap.md`](docs/phase-0-bootstrap.md).

## Design decisions (summary)

Full rationale in [`docs/design-decisions.md`](docs/design-decisions.md). Highlights:

- **Region / zone:** `us-central1` / `us-central1-a` (YAML-overridable)
- **Machine type:** `e2-standard-2` default, YAML-overridable per instance
- **Boot disk:** 20 GB `pd-balanced`, `ubuntu-2404-lts` family (YAML-configurable)
- **Data disk:** 100 GB `pd-balanced`, online-resizable, snapshots daily × 7 + weekly × 2
- **Lifecycle:** `stop_start` default, `destroy_recreate` opt-in
- **Connectivity:** IAP only, no public IP, Cloud NAT for egress
- **Identity (Layer 1, IAP):** Cloud Identity Free over `intelops.dev` + `intelops.ai`, 2FA enforced, per-user or Google Groups
- **Identity (Layer 2, sshd):** Ansible-managed, OS Login off, SSH keys primary, password + TOTP per-user opt-in
- **Sudo:** full `NOPASSWD: ALL`, auditd execve trail shipped to Cloud Logging by default
- **Security:** WIF pinned to `devopstoday11/remote-dev-servers` + `refs/heads/main`; GitHub Environments + required reviewers on `down`/`nuke`; mkfs guardrail in the disks role
- **Cost guard:** monthly budget with $10–$100 tiered alerts; nightly auto-stop of VMs not flagged `pinned: true`

## License

See [`LICENSE`](LICENSE).
