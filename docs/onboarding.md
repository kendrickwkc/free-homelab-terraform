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
[docs/bastion.md](bastion.md)), then record the credentials to seal in step 3.

## 3. Seal the secrets

Human secrets (DB creds, Kafka, API keys) — seal each and commit:

```sh
kubectl create namespace myproject
kubeseal --controller-name sealed-secrets --controller-namespace kube-system \
  < secrets/db.yaml > k8s/secrets/db-sealed.yaml
```

Terraform-generated secrets (tunnel token, S3 key) — bridge once from output:

```sh
cat > k8s/secrets/generated.yaml <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: cloudflared-secret
  namespace: myproject
type: Opaque
stringData:
  TUNNEL_TOKEN: __TUNNEL_TOKEN__
---
apiVersion: v1
kind: Secret
metadata:
  name: s3-secret
  namespace: myproject
type: Opaque
stringData:
  S3_ACCESS_KEY: __S3_ACCESS_KEY__
  S3_SECRET_KEY: __S3_SECRET_KEY__
EOF

TF_OUT=$(terraform output -json)
sed -e "s/__TUNNEL_TOKEN__/$(echo "$TF_OUT" | jq -r '.tunnel_token.value')/" \
    -e "s/__S3_ACCESS_KEY__/$(echo "$TF_OUT" | jq -r '.s3_access_key.value')/" \
    -e "s/__S3_SECRET_KEY__/$(echo "$TF_OUT" | jq -r '.s3_secret_key.value')/" \
    k8s/secrets/generated.yaml \
  | kubeseal --controller-name sealed-secrets --controller-namespace kube-system \
      -o yaml > k8s/secrets/generated-sealed.yaml

rm k8s/secrets/generated.yaml
git add k8s/secrets/*-sealed.yaml
```

> The plaintext `generated.yaml` must never be committed.

## 4. Deploy

```sh
kubectl apply -f k8s/
```

## Checklist

- [ ] `infra/terraform.tfvars` gitignored, secrets not committed
- [ ] unique state key under `tenants/<name>/`
- [ ] namespace created before applying sealed secrets
- [ ] MySQL DB + user created, creds sealed (not committed in plaintext)
- [ ] tunnel token + S3 key sealed from `terraform output` (not hardcoded)
- [ ] app pinned to `storage=true` node if it uses a block PVC
