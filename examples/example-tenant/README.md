# Example tenant

A complete, copyable tenant for the
[free-homelab-terraform](https://github.com/kendrickwkc/free-homelab-terraform)
platform: Terraform creates the tenant's buckets, OCI identity, Cloudflare
Tunnel and assets Worker; the `k8s/` manifests deploy a demo app and the
tunnel connector. End result: **your app live at
`https://<hostname>.<your-domain>`**.

This repo is a **template** — use "Use this template" to create your own copy
first. Everything below runs inside your copy.

## What you get

- Private S3-compatible buckets (`<name>-assets`, `<name>-backups`)
- An OCI identity scoped to those buckets only
- A Cloudflare Tunnel + DNS record for your app (`name` = tenant name)
- An optional assets Worker serving the assets bucket at
  `assets.<your-domain>` (public by design — don't put private files there)
- A demo app (nginx) + the cloudflared connector wired to the tunnel

## Steps

### 0. Platform is running

The shared platform (VCN, OKE, Sealed Secrets, Tailscale access) is already
applied from the [platform README](../../README.md#quickstart). You need a
working `kubectl` against the cluster.

### 1. Copy this directory into your project repo

```sh
cp -r examples/example-tenant/ ~/src/myproject/infra
cd ~/src/myproject/infra
```

### 2. Configure

```sh
cp terraform.tfvars.example terraform.tfvars    # region, namespace, tenancy, zone, Cloudflare ids/token
cp backend.tfbackend.example backend.tfbackend  # set key = tenants/<name>/terraform.tfstate
terraform init -backend-config=backend.tfbackend
```

Point the module at **your** template copy (or `../../modules/tenant` when
developing inside the platform repo). Pin a tag; bump it later to pull module
fixes from upstream:

```hcl
source = "github.com/<your-username>/free-homelab-terraform//modules/tenant?ref=v1.1.0"
```

Then `terraform apply`. Outputs include `tunnel_token`, `s3_access_key`,
`s3_secret_key` (all sensitive).

### 3. Deploy to the cluster

The manifests create the namespace themselves (`example` — rename it to your
tenant name throughout `k8s/`). Seal the tunnel token per
`k8s/sealed-secret-example.yaml`, add the sealed file to
`k8s/kustomization.yaml`, then:

```sh
kubectl apply -k k8s/
```

The tunnel token is bridged from `terraform output` once — the plaintext
never touches git. Other Terraform-created secrets (the OCI S3 keys) follow
the same pattern — see
[Bridging Terraform outputs](#bridging-terraform-outputs-into-sealed-secrets)
below.

### 4. Add your app

Replace the demo app in `k8s/demo-app.yaml` with your real app. Conventions
the module assumes (both overridable via module inputs):

- A Kubernetes `Service` named after the tenant on port **8080**
  (`app_service = http://<name>:8080` by default).
- Bucket names are user-supplied in the tenancy's shared object-storage
  namespace — prefix them with the tenant name.

### 5. Database (optional)

Create the tenant's MySQL database and user directly from your workstation —
the platform's subnet router advertises the private subnet, so the DB is
reachable over the tailnet:

```sh
cd <platform-repo>/platform && terraform output -raw mysql_private_ip
mysql -h <mysql-private-ip> -u admin -p
```

```sql
CREATE DATABASE IF NOT EXISTS myproject CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'myproject'@'%' IDENTIFIED BY '<strong-password>';
GRANT ALL PRIVILEGES ON myproject.* TO 'myproject'@'%';
FLUSH PRIVILEGES;
```

Any MySQL GUI (TablePlus, DBeaver) works the same way. Before Tailscale is
running, use the bastion flow instead:
[docs/bastion.md](../../docs/bastion.md#mysql-break-glass-daily-driver-is-tailnet-access).

## Bridging Terraform outputs into sealed secrets

Secrets created by Terraform (the tunnel token, the S3 key) are rendered as
plaintext Secrets, sealed, then deleted — plaintext never touches git:

```sh
cd infra && TF_OUT=$(terraform output -json)

cat > /tmp/cloudflared-token.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloudflared-token
  namespace: example
type: Opaque
stringData:
  token: $(echo "$TF_OUT" | jq -r '.tunnel_token.value')
EOF

# Only if the app itself reads the tenant bucket:
cat > /tmp/s3-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: s3-secret
  namespace: example
type: Opaque
stringData:
  S3_ACCESS_KEY: $(echo "$TF_OUT" | jq -r '.s3_access_key.value')
  S3_SECRET_KEY: $(echo "$TF_OUT" | jq -r '.s3_secret_key.value')
EOF

for f in /tmp/cloudflared-token.yaml /tmp/s3-secret.yaml; do
  kubeseal --controller-name sealed-secrets-controller \
    --controller-namespace kube-system \
    < "$f" > k8s/sealed/$(basename "$f" .yaml)-sealed.yaml
done
rm /tmp/cloudflared-token.yaml /tmp/s3-secret.yaml
# then add k8s/sealed/*-sealed.yaml to k8s/kustomization.yaml
```

## Private registry pull secrets (OCIR)

If the app pulls images from a private registry (e.g. OCIR), generate its
pull secret with kubectl — the `auth` field is computed, so it must not be
written by hand:

```sh
kubectl -n example create secret docker-registry example-pull \
  --docker-server=<region-key>.ocir.io \
  --docker-username='<object-storage-namespace>/<oci-username>' \
  --docker-password='<auth-token>' \
  --dry-run=client -o yaml > /tmp/pull.yaml

kubeseal --controller-name sealed-secrets-controller \
  --controller-namespace kube-system \
  < /tmp/pull.yaml > k8s/sealed/pull-sealed.yaml
rm /tmp/pull.yaml
```

Reference the sealed secret as `imagePullSecrets` in your Deployment and add
it to `k8s/kustomization.yaml`.

## Notes

- The assets Worker reads the private bucket with the tenant's S3 key and
  serves it **publicly** (static assets only).
- If the app pulls from a private registry, see
  [Private registry pull secrets](#private-registry-pull-secrets-ocir).
