# Phase 1 — Networking module

This phase delivers the private network that every dev VM will live in: a VPC, a regional subnet with Private Google Access, a Cloud Router + Cloud NAT for egress, and an IAP-scoped SSH firewall rule.

**Goal of this phase:** prove the network works end-to-end by manually creating a throwaway VM, SSH'ing into it through IAP, and reaching the internet from inside it.

No GitHub Actions automation yet — that's Phase 6. For now you `terraform apply` from your laptop, impersonating the deployer service account.

## What gets created

| Resource | Name pattern | Notes |
|---|---|---|
| VPC | `${name_prefix}-vpc` | Custom mode, regional routing. |
| Subnet | `${name_prefix}-subnet-${region}` | Default `10.0.0.0/24`, Private Google Access on. |
| Cloud Router | `${name_prefix}-router-${region}` | Required by Cloud NAT. |
| Cloud NAT | `${name_prefix}-nat-${region}` | Auto-allocated public IPs, logs errors only. |
| Firewall rule | `${name_prefix}-allow-iap-ssh` | tcp/22 from `35.235.240.0/20` only, targets VMs tagged `iap-ssh`. |

Default name prefix is `remote-dev`, so concrete names will be `remote-dev-vpc`, `remote-dev-subnet-us-central1`, etc.

## Prerequisites

Phase 0 complete:
- GCP project exists and is set as current (`gcloud config get-value project`).
- Terraform state bucket exists.
- Deployer service account exists with the roles from Phase 0 Step 5.
- Your user has `roles/iam.serviceAccountTokenCreator` on the deployer SA (project owners get this by default).

Local tooling:
- `terraform` >= 1.6.0
- `gcloud` CLI authenticated with your user (`gcloud auth login`)
- Application Default Credentials set up: `gcloud auth application-default login`

## Directory layout

```
terraform/
├── modules/
│   └── network/
│       ├── versions.tf
│       ├── variables.tf
│       ├── main.tf
│       └── outputs.tf
└── envs/
    └── dev/
        ├── backend.tf            # GCS remote state (bucket via -backend-config)
        ├── providers.tf
        ├── variables.tf
        ├── main.tf               # composes the network module
        ├── outputs.tf
        └── terraform.tfvars.example
```

## Apply locally

### Step 1 — Set environment

Re-source the variables file from Phase 0 (or set inline):

```bash
source ~/.config/remote-dev-servers.env
# Should give you PROJECT_ID, TF_STATE_BUCKET, DEPLOYER_SA_EMAIL at minimum.
```

Tell the Google provider to impersonate the deployer SA, so this local run matches what CI will do later:

```bash
export GOOGLE_IMPERSONATE_SERVICE_ACCOUNT="${DEPLOYER_SA_EMAIL}"
```

### Step 2 — Create your tfvars

```bash
cd terraform/envs/dev
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars   # set project_id, optionally tweak region or name_prefix
```

`terraform.tfvars` is gitignored.

### Step 3 — Init with the state bucket

```bash
terraform init \
  -backend-config="bucket=${TF_STATE_BUCKET}"
```

This downloads providers and configures the GCS backend. State will live at `gs://${TF_STATE_BUCKET}/envs/dev/network/default.tfstate`.

### Step 4 — Plan

```bash
terraform plan -out=tfplan
```

You should see ~5 resources to add: network, subnetwork, router, router_nat, firewall.

### Step 5 — Apply

```bash
terraform apply tfplan
```

Takes about 1–2 minutes. On success, `terraform output` prints the VPC/subnet/router/NAT names and the `iap_ssh_tag` value (`iap-ssh`) that Phase 2 will use.

## Verify

### From gcloud
```bash
gcloud compute networks describe "$(terraform output -raw vpc_name)"
gcloud compute networks subnets describe \
  "$(terraform output -raw subnet_name)" --region="${REGION}"
gcloud compute routers describe \
  "$(terraform output -raw router_name)" --region="${REGION}"
gcloud compute routers nats describe \
  "$(terraform output -raw nat_name)" \
  --router="$(terraform output -raw router_name)" \
  --region="${REGION}"
gcloud compute firewall-rules list --filter="network:$(terraform output -raw vpc_name)"
```

The firewall list should show exactly one rule: `${name_prefix}-allow-iap-ssh` with `sourceRanges: 35.235.240.0/20` and `targetTags: iap-ssh`.

### End-to-end smoke test with a throwaway VM

This proves IAP + subnet + NAT + firewall all work together. Resources are deleted at the end.

**1) Create a tiny test VM in the new subnet, with the IAP tag and no external IP:**

```bash
TEST_VM="phase1-iap-smoke-test"
ZONE="${REGION}-a"
SUBNET_SELF_LINK="$(terraform output -raw subnet_self_link)"
IAP_TAG="$(terraform output -raw iap_ssh_tag)"

gcloud compute instances create "${TEST_VM}" \
  --project="${PROJECT_ID}" \
  --zone="${ZONE}" \
  --machine-type="e2-micro" \
  --image-family="ubuntu-2404-lts" \
  --image-project="ubuntu-os-cloud" \
  --subnet="${SUBNET_SELF_LINK}" \
  --no-address \
  --tags="${IAP_TAG}" \
  --metadata="enable-oslogin=FALSE"
```

`--no-address` is the critical bit — no external IP.

**2) SSH in via IAP:**

```bash
gcloud compute ssh "${TEST_VM}" \
  --zone="${ZONE}" \
  --tunnel-through-iap \
  --project="${PROJECT_ID}"
```

If this works, IAP + the firewall rule + your user's IAP IAM are all good. If it hangs or errors, see Troubleshooting below.

**3) From inside the VM, verify outbound NAT works:**

```bash
curl -s https://ifconfig.me ; echo
curl -s -o /dev/null -w "%{http_code}\n" https://archive.ubuntu.com/ubuntu/
sudo apt-get update -qq && echo "apt update OK"
```

The first command should print a public IP (that's the NAT egress IP, not your VM's IP). The third confirms package mirrors are reachable.

**4) Exit and delete the test VM:**

```bash
exit   # leaves the SSH session
gcloud compute instances delete "${TEST_VM}" --zone="${ZONE}" --quiet
```

Total cost of this smoke test: a few cents.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `terraform init` fails on backend auth | Your `GOOGLE_IMPERSONATE_SERVICE_ACCOUNT` isn't set, or you don't have `serviceAccountTokenCreator` on the deployer SA. |
| `terraform apply` fails with `Permission denied on resource project` | Deployer SA missing one of the Phase 0 Step 5 roles. Re-check with `gcloud projects get-iam-policy`. |
| `gcloud compute ssh --tunnel-through-iap` hangs | Either (a) your user lacks `roles/iap.tunnelResourceAccessor` on the project — IAP IAM bindings happen in Phase 3, but for the smoke test you can grant yourself temporarily; or (b) the firewall target tag on the VM doesn't match `iap_ssh_tag`. |
| `gcloud compute ssh` returns `Permission denied (publickey)` | Expected — OS Login is disabled, and Phase 1 hasn't provisioned any POSIX users yet. The point of the smoke test is that the IAP tunnel reaches sshd; an SSH auth failure proves the network path works. |
| `curl https://ifconfig.me` from inside VM hangs | Cloud NAT not wired correctly, or you forgot Private Google Access on the subnet. |

**Temporary IAP IAM for the smoke test only** (revoke after Phase 1):

```bash
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="user:chandu@intelops.ai" \
  --role="roles/iap.tunnelResourceAccessor"
```

## Cleanup (if you want to start over)

```bash
cd terraform/envs/dev
terraform destroy
```

This removes the VPC, subnet, router, NAT, and firewall. The state bucket and deployer SA are untouched.

## Phase 1 is done when

- [ ] `terraform apply` succeeds with the 5 network resources created.
- [ ] `gcloud compute firewall-rules list` shows the one IAP SSH rule.
- [ ] The throwaway-VM smoke test connects via IAP and reaches the internet through NAT.
- [ ] The test VM is deleted.
- [ ] (Optional) The temporary IAP IAM binding for your user is revoked.

→ Continue to **Phase 2 — Data disk + Compute modules**: standalone persistent disk with `prevent_destroy`, snapshot policy attachment, the VM resource that mounts it, per-VM runtime service account, and the mkfs-guardrail integration test.
