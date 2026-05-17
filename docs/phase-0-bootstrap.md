# Phase 0 — One-Time Bootstrap

A manual, one-time setup performed once per Cloud Identity tenant + GCP project. After this phase, every subsequent operation (Phase 1 onward) is automated via Terraform + GitHub Actions.

**Estimated time:** 45–60 minutes total — Cloud Identity ~20 min, GCP ~25 min, GitHub ~10 min.

## What you will create

1. A **Cloud Identity Free** tenant covering `intelops.dev` (primary) and `intelops.ai` (secondary), with 2FA enforced and four end-user identities.
2. A dedicated GCP project with billing linked.
3. The required GCP APIs.
4. A versioned GCS bucket for Terraform remote state.
5. A Workload Identity Pool + OIDC provider scoped to `devopstoday11/remote-dev-servers`, **`refs/heads/main` only**.
6. A deployer service account with the roles Terraform needs.
7. A GCP billing budget with tiered notifications at $10–$100 in $10 steps.
8. Two GitHub Environments (`down`, `nuke`) with required-reviewer protection.
9. GitHub repository Variables so workflows know where everything lives.

---

## Prerequisites

### On your laptop
- `gcloud` CLI installed and authenticated as a user with **Organization Admin** or at minimum **Project Creator** + **Billing Account User**.
- A GCP billing account ID (`gcloud billing accounts list`).
- DNS access to `intelops.dev` and `intelops.ai` in GoDaddy.
- Admin access to the `devopstoday11/remote-dev-servers` repository (or your fork).

### Verify local auth
```bash
gcloud auth list
gcloud config list
```

---

## Variables used throughout

Set once, reuse. Save to `~/.config/remote-dev-servers.env` and source whenever you return.

```bash
# --- REQUIRED ---
export PROJECT_ID="remote-dev-servers-prod"           # must be globally unique
export PROJECT_NAME="Remote Dev Servers"
export BILLING_ACCOUNT_ID="XXXXXX-XXXXXX-XXXXXX"      # gcloud billing accounts list
export GITHUB_REPO="devopstoday11/remote-dev-servers"
export PRIMARY_DOMAIN="intelops.dev"
export SECONDARY_DOMAIN="intelops.ai"

# --- DEFAULTS, change only if needed ---
export REGION="us-central1"
export STATE_BUCKET="${PROJECT_ID}-tfstate"
export WIF_POOL_ID="github-actions"
export WIF_PROVIDER_ID="github-provider"
export DEPLOYER_SA_NAME="tf-deployer"
export DEPLOYER_SA_EMAIL="${DEPLOYER_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
export BUDGET_AMOUNT_USD="100"
```

---

## Part 1 — Cloud Identity Free tenant

### Step 0a — Sign up for Cloud Identity Free

1. In a browser, open `https://cloud.google.com/identity`.
2. Click **Get started** (or **Sign up**) under "Cloud Identity Free Edition".
3. Use **`intelops.dev`** as the primary domain when prompted.
4. Enter your name and a working email address (you will receive a verification email there).
5. When asked about Workspace email (Gmail), choose **Skip / I do not need this** — you only want identity, not Gmail.
6. Set the super-admin username, e.g. **`admin@intelops.dev`**, and a strong password. Save these in a password manager.

You will land in the Google Admin console at `https://admin.google.com`.

> Use this `admin@intelops.dev` account ONLY for tenant management. Create a separate daily-driver identity in Step 0e and use that for actual GCP work. Enable a hardware security key on the admin account.

### Step 0b — Verify the primary domain (`intelops.dev`)

1. Admin → **Account → Domains → Manage domains**.
2. Click **Verify domain** next to `intelops.dev`.
3. Choose the **TXT record** method.
4. Copy the verification string (looks like `google-site-verification=...`).
5. In **GoDaddy DNS for `intelops.dev`**, add a new TXT record:
   - **Type:** TXT
   - **Name:** `@` (root)
   - **Value:** the verification string
   - **TTL:** default
6. Wait 2–5 minutes. Back in Admin, click **Verify**.

> **DO NOT** change MX, SPF, DKIM, autodiscover, or `mail.*` CNAME records. Cloud Identity needs **only** the TXT record. Office 365 email keeps working because MX is untouched.

### Step 0c — Add `intelops.ai` as a secondary domain

1. Admin → **Account → Domains → Manage domains → Add a domain**.
2. Enter `intelops.ai`. Choose **Secondary domain** (NOT alias).
3. Add the TXT record Google provides — in **GoDaddy DNS for `intelops.ai`** (same procedure as Step 0b, but in the `intelops.ai` zone).
4. Verify.

Result: one tenant, two domains, both verified. You can now create users at either `@intelops.dev` or `@intelops.ai`.

### Step 0d — Enforce 2FA

1. Admin → **Security → Authentication → 2-step verification**.
2. **Allow users to turn on 2-step verification:** On.
3. **Enforcement:** On.
4. **New user enrollment period:** 7 days (grace period).
5. **Methods allowed:** Any except SMS (SMS is phishable). Authenticator app and hardware keys preferred.
6. Save.

### Step 0e — Create the user identities

For each of the four working identities:

1. Admin → **Directory → Users → Add new user**.
2. Set first/last name, primary email, and a temporary password.
3. Tick **Ask for a password change at next sign-in**.
4. Send the temporary password to the human out-of-band (1Password, Signal, in person).

Create:

| Email | For | Domain |
|---|---|---|
| `example1@intelops.dev` | other user 1 | primary |
| `example2@intelops.dev` | other user 2 | primary |
| `example3@intelops.dev` | other user 3 | primary |
| `chandu@intelops.ai` | you (daily driver) | secondary |

> `useclaudetools@gmail.com` is **NOT** created here. It is an existing consumer Google account and will be listed directly in `iap_principals:` in Phase 3 as `user:useclaudetools@gmail.com`.

### Step 0f — (Optional) Create a Google Group for IAP

Only do this if you intend to use `use_groups: true` in instance YAML.

1. Admin → **Directory → Groups → Create group**.
2. **Name:** `devs`, **email:** `devs@intelops.dev`.
3. **Access type:** Restricted.
4. Add the four working identities as members.

You can skip this and list users individually in YAML; group support can be enabled later without code changes.

---

## Part 2 — GCP project

### Step 1 — Create the project and link billing

```bash
gcloud projects create "${PROJECT_ID}" --name="${PROJECT_NAME}"
gcloud config set project "${PROJECT_ID}"

gcloud billing projects link "${PROJECT_ID}" \
  --billing-account="${BILLING_ACCOUNT_ID}"
```

Verify:
```bash
gcloud projects describe "${PROJECT_ID}"
gcloud billing projects describe "${PROJECT_ID}"
```

### Step 2 — Enable required APIs

```bash
gcloud services enable \
  compute.googleapis.com \
  iap.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  secretmanager.googleapis.com \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com \
  storage.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  cloudbilling.googleapis.com \
  billingbudgets.googleapis.com \
  --project="${PROJECT_ID}"
```

Verify:
```bash
gcloud services list --enabled --project="${PROJECT_ID}"
```

### Step 3 — Create the Terraform state bucket

```bash
gcloud storage buckets create "gs://${STATE_BUCKET}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --uniform-bucket-level-access \
  --public-access-prevention

gcloud storage buckets update "gs://${STATE_BUCKET}" --versioning
```

Add a lifecycle rule for old state versions:

```bash
cat > /tmp/lifecycle.json <<'EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": { "type": "Delete" },
        "condition": {
          "numNewerVersions": 10,
          "daysSinceNoncurrentTime": 30
        }
      }
    ]
  }
}
EOF

gcloud storage buckets update "gs://${STATE_BUCKET}" \
  --lifecycle-file=/tmp/lifecycle.json
rm /tmp/lifecycle.json
```

Verify:
```bash
gcloud storage buckets describe "gs://${STATE_BUCKET}" \
  --format="value(versioning.enabled,iamConfiguration.publicAccessPrevention)"
# Expected:  True   enforced
```

### Step 4 — Create the deployer service account

```bash
gcloud iam service-accounts create "${DEPLOYER_SA_NAME}" \
  --project="${PROJECT_ID}" \
  --display-name="Terraform Deployer (GitHub Actions)" \
  --description="Used by GitHub Actions via Workload Identity Federation to run Terraform."
```

### Step 5 — Grant the deployer SA the roles it needs

```bash
for role in \
  roles/compute.admin \
  roles/iam.serviceAccountAdmin \
  roles/iam.serviceAccountUser \
  roles/resourcemanager.projectIamAdmin \
  roles/iap.admin \
  roles/secretmanager.admin ; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${DEPLOYER_SA_EMAIL}" \
    --role="${role}" \
    --condition=None
done

gcloud storage buckets add-iam-policy-binding "gs://${STATE_BUCKET}" \
  --member="serviceAccount:${DEPLOYER_SA_EMAIL}" \
  --role="roles/storage.objectAdmin"

gcloud storage buckets add-iam-policy-binding "gs://${STATE_BUCKET}" \
  --member="serviceAccount:${DEPLOYER_SA_EMAIL}" \
  --role="roles/storage.legacyBucketReader"
```

Verify the deployer SA's effective roles:

```bash
gcloud projects get-iam-policy "${PROJECT_ID}" \
  --flatten="bindings[].members" \
  --filter="bindings.members:${DEPLOYER_SA_EMAIL}" \
  --format="value(bindings.role)"
```

### Step 6 — Create the Workload Identity Pool

```bash
gcloud iam workload-identity-pools create "${WIF_POOL_ID}" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --display-name="GitHub Actions"

export WIF_POOL_FULL_ID=$(gcloud iam workload-identity-pools describe "${WIF_POOL_ID}" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --format="value(name)")

echo "${WIF_POOL_FULL_ID}"
# Example: projects/123456789/locations/global/workloadIdentityPools/github-actions
```

### Step 7 — Create the OIDC Provider for GitHub

The attribute condition pins this provider to **the named repo AND the `refs/heads/main` ref**. Only main-branch workflow runs can mint impersonation tokens.

```bash
gcloud iam workload-identity-pools providers create-oidc "${WIF_PROVIDER_ID}" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --workload-identity-pool="${WIF_POOL_ID}" \
  --display-name="GitHub OIDC Provider" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner,attribute.ref=assertion.ref,attribute.actor=assertion.actor" \
  --attribute-condition="assertion.repository == '${GITHUB_REPO}' && assertion.ref == 'refs/heads/main'"

export WIF_PROVIDER_FULL_ID=$(gcloud iam workload-identity-pools providers describe "${WIF_PROVIDER_ID}" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --workload-identity-pool="${WIF_POOL_ID}" \
  --format="value(name)")

echo "${WIF_PROVIDER_FULL_ID}"
```

> If you fork or rename the repo, update the condition with `gcloud iam workload-identity-pools providers update-oidc`. The repo string + ref string here is the real security boundary.

### Step 8 — Let GitHub OIDC impersonate the deployer SA

```bash
gcloud iam service-accounts add-iam-policy-binding "${DEPLOYER_SA_EMAIL}" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${WIF_POOL_FULL_ID}/attribute.repository/${GITHUB_REPO}"
```

Verify:
```bash
gcloud iam service-accounts get-iam-policy "${DEPLOYER_SA_EMAIL}" --format="json"
```

### Step 9 — Create the GCP billing budget with tiered alerts

This creates a $100/month budget that fires alert emails to project billing administrators at every $10 increment.

```bash
cat > /tmp/budget.yaml <<EOF
displayName: "${PROJECT_ID} monthly budget"
budgetFilter:
  projects:
    - "projects/${PROJECT_ID}"
amount:
  specifiedAmount:
    currencyCode: "USD"
    units: "${BUDGET_AMOUNT_USD}"
thresholdRules:
  - thresholdPercent: 0.10
  - thresholdPercent: 0.20
  - thresholdPercent: 0.30
  - thresholdPercent: 0.40
  - thresholdPercent: 0.50
  - thresholdPercent: 0.60
  - thresholdPercent: 0.70
  - thresholdPercent: 0.80
  - thresholdPercent: 0.90
  - thresholdPercent: 1.00
notificationsRule:
  disableDefaultIamRecipients: false
EOF

gcloud billing budgets create \
  --billing-account="${BILLING_ACCOUNT_ID}" \
  --budget-file=/tmp/budget.yaml

rm /tmp/budget.yaml
```

`disableDefaultIamRecipients: false` sends the alerts to project Billing Account Administrators and Billing Account Users. Add Pub/Sub topics or Cloud Monitoring notification channels later if you want Slack/PagerDuty hooks.

Verify:
```bash
gcloud billing budgets list --billing-account="${BILLING_ACCOUNT_ID}"
```

### Step 10 — Capture outputs you need for GitHub

```bash
echo ""
echo "============ Save these for GitHub repo Variables ============"
echo "GCP_PROJECT_ID:     ${PROJECT_ID}"
echo "GCP_REGION:         ${REGION}"
echo "GCP_ZONE_DEFAULT:   ${REGION}-a"
echo "TF_STATE_BUCKET:    ${STATE_BUCKET}"
echo "WIF_PROVIDER:       ${WIF_PROVIDER_FULL_ID}"
echo "DEPLOYER_SA_EMAIL:  ${DEPLOYER_SA_EMAIL}"
echo "==============================================================="
```

### Step 11 — Add as GitHub repository Variables

GitHub → **Repo → Settings → Secrets and variables → Actions → Variables tab → New repository variable.**

| Variable name | Value |
|---|---|
| `GCP_PROJECT_ID` | from Step 10 |
| `GCP_REGION` | `us-central1` |
| `GCP_ZONE_DEFAULT` | `us-central1-a` |
| `TF_STATE_BUCKET` | from Step 10 |
| `WIF_PROVIDER` | from Step 10 (full `projects/.../providers/...` path) |
| `DEPLOYER_SA_EMAIL` | from Step 10 |

These are Variables (not Secrets). None of them are sensitive — project IDs and SA emails are discoverable from your GCP project. Treating them as Variables makes workflow logs and debugging cleaner.

### Step 12 — Create GitHub Environments with required reviewers

GitHub → **Repo → Settings → Environments → New environment.**

Create two:

**`down`**
- Required reviewers: yourself + at least one other person.
- Deployment branches: `main` only.
- Wait timer: 0 minutes.

**`nuke`**
- Required reviewers: yourself + at least one other person.
- Deployment branches: `main` only.
- Wait timer: 5 minutes (forces a cooling-off period before destruction).

The `down.yml` and `nuke.yml` workflows in Phase 6 will declare `environment: down` and `environment: nuke` respectively, and inherit these protection rules.

### Step 13 — Smoke test the WIF chain

Prove the chain works by manually impersonating the deployer SA from your laptop:

```bash
# Token issuance.
gcloud auth print-access-token \
  --impersonate-service-account="${DEPLOYER_SA_EMAIL}" \
  | head -c 20 ; echo "...(token truncated)"

# Bucket access.
gcloud storage ls "gs://${STATE_BUCKET}" \
  --impersonate-service-account="${DEPLOYER_SA_EMAIL}"
```

Both should succeed.

> Local impersonation needs `roles/iam.serviceAccountTokenCreator` on the SA for your own Google identity. Project owners have it by default. Otherwise:
> ```bash
> gcloud iam service-accounts add-iam-policy-binding "${DEPLOYER_SA_EMAIL}" \
>   --member="user:chandu@intelops.ai" \
>   --role="roles/iam.serviceAccountTokenCreator"
> ```
> This is local-debugging only — GitHub Actions uses the WIF binding from Step 8.

---

## Teardown (only if starting completely over)

In reverse order:

```bash
# Budget
gcloud billing budgets list --billing-account="${BILLING_ACCOUNT_ID}"  # find ID
gcloud billing budgets delete BUDGET_ID --billing-account="${BILLING_ACCOUNT_ID}"

# WIF provider + pool
gcloud iam workload-identity-pools providers delete "${WIF_PROVIDER_ID}" \
  --project="${PROJECT_ID}" --location="global" \
  --workload-identity-pool="${WIF_POOL_ID}"
gcloud iam workload-identity-pools delete "${WIF_POOL_ID}" \
  --project="${PROJECT_ID}" --location="global"

# Deployer SA
gcloud iam service-accounts delete "${DEPLOYER_SA_EMAIL}" --project="${PROJECT_ID}"

# State bucket (deletes ALL Terraform state)
gcloud storage rm -r "gs://${STATE_BUCKET}"

# Nuclear: deletes the project
gcloud projects delete "${PROJECT_ID}"
```

WIF pools and providers are soft-deleted for 30 days; recreate with the same ID inside that window via `--undelete`.

Cloud Identity tenant deletion is intentionally not scripted — it requires admin-console action and affects every user in the tenant.

---

## Phase 0 is done when

- [ ] Cloud Identity Free tenant exists with `intelops.dev` (primary) + `intelops.ai` (secondary) verified.
- [ ] 2FA enforced with a 7-day grace period.
- [ ] Four working user accounts created (`example1@intelops.dev`, `example2@intelops.dev`, `example3@intelops.dev`, `chandu@intelops.ai`).
- [ ] GCP project exists with billing linked.
- [ ] All required APIs enabled.
- [ ] Versioned state bucket exists with the lifecycle policy.
- [ ] Deployer SA has all six project roles + bucket roles.
- [ ] WIF pool + provider exist; attribute condition pinned to `devopstoday11/remote-dev-servers` + `refs/heads/main`.
- [ ] Deployer SA has the `workloadIdentityUser` binding.
- [ ] Billing budget created with $10–$100 tiered alerts.
- [ ] `down` and `nuke` GitHub Environments exist with required-reviewer rules.
- [ ] All six GitHub repo Variables set.
- [ ] Step 13 smoke test passes.

→ Continue to **Phase 1 — Networking module** (Terraform code for VPC, subnet, Cloud Router, Cloud NAT, IAP-scoped firewall).
