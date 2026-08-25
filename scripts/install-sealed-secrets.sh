#!/usr/bin/env bash
# Install the Sealed Secrets controller into kube-system and back up its
# sealing key. Run once per cluster; re-running upgrades the controller.
#
# The sealing key is the ONLY way to decrypt sealed secrets — losing it (and
# recreating the controller) makes every tenant's sealed secrets undecryptable.
#
# Requires: kubectl, and network access to GitHub.
set -euo pipefail

VERSION="${SEALED_SECRETS_VERSION:-v0.39.1}"
NAMESPACE="${SEALED_SECRETS_NAMESPACE:-kube-system}"
MANIFEST="https://github.com/bitnami-labs/sealed-secrets/releases/download/${VERSION}/controller.yaml"
KEY_BACKUP="${KEY_BACKUP:-sealed-secrets-key-${VERSION}.yaml}"

echo "==> Installing Sealed Secrets controller ${VERSION} into ${NAMESPACE}"
kubectl apply -f "${MANIFEST}"

echo "==> Waiting for the controller to be ready"
kubectl rollout status deployment/sealed-secrets-controller -n "${NAMESPACE}"

echo "==> Backing up the sealing key -> ${KEY_BACKUP}"
kubectl get secret -n "${NAMESPACE}" \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > "${KEY_BACKUP}"

echo
echo "DONE. Sealing key saved to ${KEY_BACKUP}."
echo "Store it somewhere safe and OFFLINE (it is gitignored, do not commit it)."
echo
echo "Sanity check:"
echo "  kubeseal --controller-name sealed-secrets-controller --controller-namespace ${NAMESPACE} --fetch-cert"