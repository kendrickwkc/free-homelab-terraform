# free-homelab-terraform

A minimal, open-source platform for hosting multiple personal projects on
[Oracle Cloud Infrastructure](https://www.oracle.com/cloud/free/) **Always Free**
tier — a managed Kubernetes (OKE) cluster with multi-tenant isolation, Git-based
secrets, and per-project Cloudflare Tunnel ingress. Everything runs at **$0/month**
in your home region.

```
┌──────────────────────── platform (this repo, OCI-only) ──────────────────────────┐
│  VCN · OKE (basic, private) · OCI Block Volume CSI · MySQL (shared) · Bastion · Budget │
└──────────────────────────────────────────────────────────────────────────────────┘
                                        │  terraform_remote_state
                                        ▼
┌────────── tenants (each project's own repo) ──────────────────────────────────────┐
│  infra/  →  module "tenant"  (bucket · OCI identity · Cloudflare Tunnel + Worker)  │
│  k8s/    →  namespace · Sealed Secrets · app manifests                            │
└──────────────────────────────────────────────────────────────────────────────────┘
```

## What you get

| Component | Detail |
|---|---|
| **Kubernetes** | OKE basic cluster, private API endpoint, Tailscale daily-driver access (+ bastion bootstrap) |
| **Node pools** | `general` 1× 2 OCPU / 12 GB (labelled `storage=true`) · `small` 2× 1 OCPU / 6 GB |
| **Placement** | Single availability domain, spread across 3 fault domains |
| **Storage** | OCI Block Volume CSI + `oci-bv` StorageClass (`WaitForFirstConsumer`) |
| **Database** | Shared MySQL (`MySQL.Free`); per-tenant databases/users created manually |
| **Secrets** | [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) — encrypted in git, no external vault |
| **Ingress** | Per-tenant Cloudflare Tunnel + optional assets Worker |
| **Guardrails** | Budget + billable-spend alarm |

## Always Free limits (read this first)

Everything here fits the free tier **only in your tenancy's home region**. The
default topology consumes the limits *exactly*, with zero headroom:

- **Compute:** 4 OCPU / 24 GB total (A1 Flex). `1 OCPU` caps at 6 GB.
- **Storage:** 200 GB total. 3× 50 GB boot + 50 GB block = 200 GB. No
  boot-volume backups, no second block volume.
- **Object Storage:** 20 GB + 50K API requests/month (separate budget).
- **MySQL:** one `MySQL.Free` DB system per tenancy.

Deploying outside the home region, or adding a 51 GB volume, **bills you**. The
budget alarm (fires on any billable spend) is your tripwire.

## Prerequisites

- OCI account with the target region set as **home region**
- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm)
- `kubectl`, `helm`, [`kubeseal`](https://github.com/bitnami-labs/sealed-secrets#installation)
- A [Tailscale](https://tailscale.com) account (free plan is fine) with the
  client installed on your workstation
- One Cloudflare account (shared — all tenant zones live in it; each tenant
  holds a zone-scoped API token)

## Bootstrap

Create the remote-state bucket once, before any apply:

```sh
export OCI_COMPARTMENT_OCID="ocid1.compartment.oc1..xxx"
export OCI_NAMESPACE="$(oci os ns get --query 'data' --raw-output)"

oci os bucket create \
  --compartment-id "$OCI_COMPARTMENT_OCID" \
  --namespace-name "$OCI_NAMESPACE" \
  --name terraform-state \
  --public-access-type NoPublicAccess \
  --storage-tier Standard

oci os bucket update --namespace-name "$OCI_NAMESPACE" \
  --name terraform-state --versioning Enabled
```

## Platform

```sh
cd platform
cp terraform.tfvars.example terraform.tfvars      # compartment, ssh key, mysql admin, alert email
cp backend.tfbackend.example backend.tfbackend    # namespace, region
terraform init -backend-config=backend.tfbackend
terraform plan
terraform apply
```

Then bootstrap the cluster services:

```sh
# 1. OCI CSI driver + oci-bv StorageClass (see docs/csi.md)
# 2. Sealed Secrets controller -> installs + backs up the sealing key
./scripts/install-sealed-secrets.sh
# 3. Tailscale operator -> tailnet access to the private cluster (see docs/tailscale.md);
#    needs a one-time bastion tunnel first: ./scripts/connect-k8s.sh
OAUTH_CLIENT_ID=<id> OAUTH_CLIENT_SECRET=<secret> ./scripts/install-tailscale-operator.sh
kubectl apply -f tailscale-connector.yaml
# 4. (optional) shared Meilisearch, see docs/meilisearch.md
```

> **Critical:** `sealed-secrets-key.yaml` is the only way to decrypt your sealed
> secrets. Store it somewhere safe and offline.

## Cluster access

The cluster API, pod IPs and service ClusterIPs are private (no public IPs).

**Daily driver — Tailscale** ([docs/tailscale.md](docs/tailscale.md)): the
operator exposes the API at `https://homelab-k8s.<tailnet>.ts.net` and a subnet
router advertises the cluster CIDRs, so kubectl and direct service connections
work from any tailnet device with no tunnels or port-forwards.

**Bootstrap & break-glass — OCI Bastion** ([docs/bastion.md](docs/bastion.md)):
on-demand short-lived port-forward sessions via
`./scripts/connect-k8s.sh`. You need this once before Tailscale exists on the
cluster; afterwards keep it for emergencies and per-session MySQL admin.

See [docs/bastion.md](docs/bastion.md) for the exact `oci bastion session create`
commands.

## Tenants

Tenants live in **each project's own repo** (so your domains and app layout stay
out of this public one). Copy `examples/example-tenant/` into your project as
`infra/` and edit it. A tenant is a `module "tenant"` call plus Kubernetes
manifests:

```hcl
data "terraform_remote_state" "platform" {
  backend = "oci"
  config = { bucket = "terraform-state", namespace = var.oci_namespace, region = var.region, key = "platform/terraform.tfstate" }
}

module "tenant" {
  source = "github.com/your-github-username/free-homelab-terraform//modules/tenant?ref=main"

  name           = "myproject"
  zone           = "your-domain.example"
  cf_account_id  = var.cf_account_id
  compartment_id = data.terraform_remote_state.platform.outputs.compartment_id
  region         = var.region
  buckets        = ["myproject-assets", "myproject-backups"]
  worker_enabled = true
  assets_bucket  = "myproject-assets"
}
```

Replace `your-github-username` with your org and pin a release tag (e.g. `?ref=v1.0.0`)
once you cut one.

## Secrets (Sealed Secrets)

Plaintext never leaves your machine. Human secrets are sealed and committed:

```sh
kubectl create namespace myproject
kubeseal --controller-name sealed-secrets-controller --controller-namespace kube-system \
  < secret.yaml > secret-sealed.yaml
git add secret-sealed.yaml
```

Secrets created by Terraform (the Cloudflare tunnel token, the OCI S3 key) are
bridged once from `terraform output` — see [docs/onboarding.md](docs/onboarding.md).

## Repository layout

```
platform/            shared infrastructure (OCI only)
modules/tenant/      reusable tenant module (+ generic assets Worker)
examples/            copyable example tenant
scripts/             one-time cluster bootstrap (Sealed Secrets, Tailscale operator, bastion tunnel)
docs/                csi, meilisearch, tailscale, bastion, onboarding
```

## License

MIT — see [LICENSE](LICENSE).
