#!/usr/bin/env bash
# Install the Sealed Secrets controller into kube-system and back up its
# sealing key. Run once per cluster; re-running upgrades the controller.
#
# The sealing key is the ONLY way to decrypt sealed secrets — losing it (and
# recreating the controller) makes every tenant's sealed secrets undecryptable.
# The backup is written to ~/.sealed-secrets-keys/ (outside the repo); copy it
# somewhere safe and OFFLINE.
#
# Requires: kubectl, and network access to GitHub.
#
# Environment overrides:
#   SEALED_SECRETS_VERSION  controller release (default: v0.39.1)
#   SEALED_SECRETS_NAMESPACE  install namespace (default: kube-system)
#   KEY_BACKUP              backup path (default: ~/.sealed-secrets-keys/homelab-key-<version>.yaml)
#   FORCE=1                 allow overwriting an existing backup file
set -euo pipefail

VERSION="${SEALED_SECRETS_VERSION:-v0.39.1}"
NAMESPACE="${SEALED_SECRETS_NAMESPACE:-kube-system}"
MANIFEST="https://github.com/bitnami-labs/sealed-secrets/releases/download/${VERSION}/controller.yaml"
KEY_BACKUP="${KEY_BACKUP:-$HOME/.sealed-secrets-keys/homelab-key-${VERSION}.yaml}"

command -v kubectl >/dev/null 2>&1 || { echo "ERROR: 'kubectl' not found in PATH"; exit 1; }

if [[ -f "$KEY_BACKUP" && "${FORCE:-0}" != "1" ]]; then
  echo "ERROR: backup already exists: $KEY_BACKUP"
  echo "Refusing to overwrite (it may hold the ONLY copy of the sealing key)."
  echo "Set FORCE=1 if you are sure."
  exit 1
fi

echo "==> Installing Sealed Secrets controller ${VERSION} into ${NAMESPACE}"
kubectl apply -f "${MANIFEST}"

echo "==> Waiting for the controller to be ready"
kubectl rollout status deployment/sealed-secrets-controller -n "${NAMESPACE}"

mkdir -p "$(dirname "$KEY_BACKUP")"
echo "==> Backing up the sealing key -> ${KEY_BACKUP}"
kubectl get secret -n "${NAMESPACE}" \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > "${KEY_BACKUP}"

echo
echo "DONE. Sealing key saved to ${KEY_BACKUP}."
echo "Store it somewhere safe and OFFLINE (outside this repo, never commit it)."
echo
echo "Sanity check:"
echo "  kubeseal --controller-name sealed-secrets-controller --controller-namespace ${NAMESPACE} --fetch-cert"
