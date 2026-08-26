# Onboarding a new tenant

A tenant is a project repo with an `infra/` directory (Terraform) and a `k8s/`
directory (manifests). Start by copying `examples/example-tenant/` into your
project repo.

## 1. Infra

```sh
cd myproject/infra
cp terraform.tfvars.example terraform.tfvars
cp backend.tfbackend.example backend.tfbackend   # use a unique key: tenants/<name>/terraform.tfstate
terraform init -backend-config=backend.tfbackend
terraform apply
```

This creates the tenant's buckets, OCI identity (+ S3 customer secret key),
Cloudflare tunnel, DNS record, and (optionally) the assets Worker.

## 2. Manual MySQL database + user

Create the tenant's database and scoped user through the bastion (see
[docs/bastion.md](bastion.md)), then record the credentials to seal in step 4.

## 3. (Optional) shared Meilisearch API key

If the tenant uses shared Meilisearch, mint a per-tenant API key (see
[docs/meilisearch.md](meilisearch.md)).

## 4. Seal the secrets

Human secrets (DB creds, Kafka, API keys) — seal each and commit:

```sh
kubectl create namespace myproject
kubeseal --controller-name sealed-secrets-controller --controller-namespace kube-system \
  < secrets/db.yaml > k8s/secrets/db-sealed.yaml
```

If the tenant pulls images from a private registry (e.g. OCIR), generate its
pull secret with kubectl too — the `auth` field is computed, so it must not be
written by hand:

```sh
kubectl create secret docker-registry myproject-pull -n myproject \
  --docker-server=<region-key>.ocir.io \
  --docker-username='<tenancy-namespace>/<oci-username>' \
  --docker-password='<auth-token>' \
  --dry-run=client -o yaml > secrets/pull.yaml

kubeseal --controller-name sealed-secrets-controller --controller-namespace kube-system \
  < secrets/pull.yaml > k8s/secrets/pull-sealed.yaml
rm secrets/pull.yaml
```

Terraform-generated secrets (tunnel token, S3 key) — write one plaintext Secret
per file, seal each, then delete the plaintexts:

```sh
TF_OUT=$(terraform output -json)

cat > k8s/secrets/cloudflared-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloudflared-secret
  namespace: myproject
type: Opaque
stringData:
  TUNNEL_TOKEN: $(echo "$TF_OUT" | jq -r '.tunnel_token.value')
EOF

cat > k8s/secrets/s3-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: s3-secret
  namespace: myproject
type: Opaque
stringData:
  S3_ACCESS_KEY: $(echo "$TF_OUT" | jq -r '.s3_access_key.value')
  S3_SECRET_KEY: $(echo "$TF_OUT" | jq -r '.s3_secret_key.value')
EOF

for f in k8s/secrets/cloudflared-secret.yaml k8s/secrets/s3-secret.yaml; do
  kubeseal --controller-name sealed-secrets-controller --controller-namespace kube-system \
    < "$f" > "${f%.yaml}-sealed.yaml"
done

rm k8s/secrets/cloudflared-secret.yaml k8s/secrets/s3-secret.yaml
git add k8s/secrets/*-sealed.yaml
```

> Plaintext files are deleted immediately; only `-sealed.yaml` files are committed.

## 5. Deploy

```sh
kubectl apply -f k8s/
```

## Checklist

- [ ] `infra/terraform.tfvars` gitignored, secrets not committed
- [ ] unique state key under `tenants/<name>/`
- [ ] namespace created before applying sealed secrets
- [ ] MySQL DB + user created, creds sealed (not committed in plaintext)
- [ ] private-registry pull secret generated via `kubectl create secret docker-registry` (auth field computed)
- [ ] tunnel token + S3 key sealed from `terraform output` (not hardcoded)
- [ ] app pinned to `storage=true` node if it uses a block PVC
