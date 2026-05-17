# Design Decisions

Locked-in choices for `remote-dev-servers`. Each entry has the decision and the reasoning. This document is the single source of truth — if anything elsewhere in the repo contradicts it, this file wins.

## Compute

| Decision | Value | Why |
|---|---|---|
| Cloud | GCP | User requirement. |
| Region | `us-central1` | Cheapest US region. |
| Zone (default) | `us-central1-a` | First zone; YAML-overridable per instance. |
| Machine type (default) | `e2-standard-2` | 2 vCPU / 8 GB, ~$50/mo if 24/7, burstable. Per-instance YAML override. |
| Boot disk | 20 GB `pd-balanced` | OS only; rebuilt on `destroy_recreate`. |
| Boot image | YAML-configurable, defaults to `ubuntu-2404-lts` | Image family pinned in module; exact image resolves at apply time. |
| Data disk | 100 GB `pd-balanced` | Holds `/home`, `/nix`, `/workspace`. Survives spin-down. Online-resizable via YAML. |
| Additional disks | Optional list in YAML, empty default | Module supports attaching pd-ssd or local-SSD later without rewrites. |
| External IP | None, ever | Hard requirement. |
| Static internal IP | Not reserved | Name-based routing via IAP. |

## Lifecycle

| Decision | Value | Why |
|---|---|---|
| Default mode | `stop_start` | Fast (~30s), cheap, preserves internal IP and boot disk. |
| Opt-in mode | `destroy_recreate` | Rebuild OS cleanly, change machine type. Data disk persists either way. |
| Data disk protection | `lifecycle { prevent_destroy = true }`; only `nuke.yml` can wipe | Prevents accidental data loss. |
| OS refresh | `unattended-upgrades` security-only + quarterly `destroy_recreate` discipline (runbook reminder, no automation) | Routine patches + periodic full image refresh. |

## Backup & DR

| Decision | Value | Why |
|---|---|---|
| Data-disk snapshots | `google_compute_resource_policy`: daily × 7 + weekly × 2 | Tamper-resistant, cheap (~$1–2/mo). |
| Cross-region replication | Deferred | Single-region in v1. |

## Connectivity

| Decision | Value | Why |
|---|---|---|
| Reach the VM | GCP Identity-Aware Proxy (IAP) only | Free, GCP-native, no public IP. |
| Tailscale | Not used | Avoiding third-party dependency. |
| Egress | Cloud NAT | VM needs outbound for apt, Nix, GitHub. |
| Firewall ingress | tcp/22 from `35.235.240.0/20` (IAP) only | Deny all else. |

## Identity & auth

### Layer 1 — reaching the SSH port (IAP gate)

- **Identity provider:** Cloud Identity Free, one tenant.
  - Primary domain: `intelops.dev`
  - Secondary domain: `intelops.ai` (free, same tenant, added in admin console)
  - Verified by TXT records in GoDaddy. MX records untouched — Office 365 keeps email.
- **2FA:** mandatory, enforced via Cloud Identity admin policy.
- **YAML schema** (`iap_principals:`) supports three principal types:
  - `user:alice@intelops.dev`
  - `user:useclaudetools@gmail.com` (plain consumer Google identity)
  - `group:devs@intelops.dev` (behind `use_groups: true` flag; requires Cloud Identity)
- **Time-bounded access:** optional `expires_at:` per principal, implemented via IAM Conditions.
- **Required role on principal:** `roles/iap.tunnelResourceAccessor` on the project.
- **Audit:** Cloud Audit Logs record every tunnel session by Google identity.

### Layer 2 — logging into Linux (sshd gate)

- **OS Login:** OFF, enforced via VM metadata.
- **Default mapping:** Google identity at Layer 1 → matching POSIX user at Layer 2. Decoupling is supported but not default; only used for `sudo -u <other> -i` after login.
- **Primary auth:** SSH public keys, declared per-user in YAML, written to `~/.ssh/authorized_keys`.
- **Password auth:** default off, per-user YAML toggle for break-glass.
- **TOTP 2FA:** Ansible role included from day one, default off, per-user YAML toggle.
- **Root login:** forbidden (`PermitRootLogin no`).
- **Allowed users:** `AllowGroups devs`.
- **MaxSessions:** 10.

## Multi-user model

| Decision | Value | Why |
|---|---|---|
| Initial users | 4 | User requirement. |
| POSIX accounts | One per human | Makes `sudo -i -u <other>` meaningful. |
| Sudo policy | `%devs ALL=(ALL:ALL) NOPASSWD: ALL` | User requirement. |
| Trust boundary | Full sudo = no personal credentials on the box. Everyone uses workload-bound creds (`gcloud auth login`, `gh auth login`). | Documented constraint, not enforceable. |
| Sudo audit (auditd) | Captures execve/setuid events | Forensic trail. |
| Sudo I/O logging (stdin/stdout/stderr) | Default OFF, YAML-toggleable per instance | Heavy, rarely consulted; available when needed. |
| Audit-log shipping (auditd + sshd → Cloud Logging) | Default ON, YAML-toggleable per instance | Without it, root can wipe local audit logs and defeat the trail. |
| Concurrent sessions | sshd `MaxSessions 10` | Multiple humans on one VM is the whole point. |
| Concurrent VSCode to same POSIX | Documented caveat in `docs/runbook.md` | Known quirk; no preemptive fix. |
| Shared workspace | `/workspace`, group-writable to `devs` | Optional scratch area. |
| Pair programming | Shared tmux socket pattern documented in `docs/runbook.md` | Five-line how-to. |
| Offboarding default | `state: locked` (account disabled, `/home` preserved). Opt-in `archived` (tarball to GCS) and `absent` (hard delete). | Recoverable by default. |

## Security guardrails

| Decision | Value | Why |
|---|---|---|
| WIF attribute condition | `assertion.repository == 'devopstoday11/remote-dev-servers' && assertion.ref == 'refs/heads/main'` | Only main-branch workflow runs can impersonate the deployer SA. |
| GitHub Environments | `down` and `nuke` require manual reviewer approval | Destructive operations gated behind human approval. |
| mkfs guardrail | Ansible `disks` role refuses to format any disk with a detected filesystem unless YAML sets `force_format: true` | Day-1 data-loss footgun closed. Integration-tested in Phase 2. |
| Firewall | Default-deny ingress; IAP CIDR only for tcp/22 | Defense-in-depth. |
| fail2ban | Installed on sshd | Defense-in-depth. |
| Secrets | GCP Secret Manager, fetched at runtime by VM's runtime SA | Never in the repo. |
| Encryption at rest | Google-managed keys (default); CMEK input wired but unused | Module is CMEK-ready when needed. |

## Operational automation

| Decision | Value | Why |
|---|---|---|
| GCP billing budget | $100/mo budget with notifications at every 10% ($10–$100) | Catch runaway costs. No hard cap. |
| Nightly idle auto-stop | Scheduled workflow at 00:00 UTC stops any VM whose YAML lacks `pinned: true` | Prevents weekend-left-on cost surprises. |
| Patching | `unattended-upgrades` security-only, no automatic reboots | Manual reboots via reconfigure workflow. |
| inotify limits | `fs.inotify.max_user_watches=524288`, `fs.inotify.max_user_instances=1024` | VSCode on real repos needs this. |

## Tooling

| Decision | Value | Why |
|---|---|---|
| Provisioning | Terraform, remote state in GCS, versioned | User requirement. |
| Config management | Ansible, idempotent, runs from GitHub runner via IAP-tunneled SSH | User requirement. |
| Ansible performance | `mitogen` deferred | Add only if reconfigure feels slow. |
| Dev toolchain | Nix, **single-user mode**, `/nix` on data disk, owned by `nix-users` group; all `devs` are members | Avoids multi-user `nixbld` UID-pinning footgun across boot-disk rebuilds. |
| CI auth | Workload Identity Federation (GitHub OIDC → GCP) | No long-lived service-account keys. |
| VM runtime identity | Per-VM dedicated service account with `roles/logging.logWriter`, `roles/monitoring.metricWriter`, `roles/secretmanager.secretAccessor` | Least-privilege; separate from deployer SA. |
| User-facing config | YAML files under `instances/` | One file per VM. |
| Codebase | Single monorepo: `devopstoday11/remote-dev-servers` | Configurable via workflow env / repo variables for forks. |

## Documentation

| Decision | Value | Why |
|---|---|---|
| User-laptop audience | Linux only | Per user requirement. |
| IDE focus | VSCode Remote-SSH, detailed step-by-step (gcloud install, IAP ProxyCommand, `~/.ssh/config`, first-connection walkthrough, common errors) | Primary user IDE. |
| Other IDEs | One-paragraph note pointing Cursor / JetBrains Gateway / neovim at the same ProxyCommand pattern | Coverage without bloat. |

## Cost posture

Approximate monthly cost (us-central1, e2-standard-2, 100 GB data disk):

- Always-on: ~$60/mo
- 40 hr/week active, stopped otherwise: ~$25/mo
- Long-idle (data disk only): ~$10/mo

Cloud NAT, IAP, Secret Manager, Cloud Audit Logs, snapshots: <$5/mo combined under realistic dev usage.

## Out of scope (v1)

- Multiple VMs sharing one data disk (PDs are single-writer).
- GPU instances (schema supports it, not validated).
- Customer-managed encryption keys (CMEK input wired, default Google-managed).
- Cross-region snapshot replication (revisit later).
- Public access of any kind.
