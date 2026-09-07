#!/usr/bin/env bash
# Install or upgrade the Tailscale Kubernetes operator with the API-server
# proxy enabled (noauth mode: Tailscale provides the network path, your
# existing kubeconfig credentials keep authenticating you).
#
# Run once per cluster through the bastion tunnel (see docs/tailscale.md);
# re-running performs a helm upgrade.
#
# Required environment (never commit these values):
#   OAUTH_CLIENT_ID      OAuth client ID from the Tailscale admin console
#                        (scopes: Devices->Core RW, Keys->Auth Keys RW)
#   OAUTH_CLIENT_SECRET  matching client secret
#
# Optional overrides:
#   OPERATOR_HOSTNAME    proxy hostname (default: homelab-k8s); the API server
#                        becomes https://<hostname>.<tailnet>.ts.net
#   TAILSCALE_NAMESPACE  namespace to install into (default: tailscale)
set -euo pipefail

NAMESPACE="${TAILSCALE_NAMESPACE:-tailscale}"
OPERATOR_HOSTNAME="${OPERATOR_HOSTNAME:-homelab-k8s}"

: "${OAUTH_CLIENT_ID:?Set OAUTH_CLIENT_ID from the Tailscale admin console}"
: "${OAUTH_CLIENT_SECRET:?Set OAUTH_CLIENT_SECRET from the Tailscale admin console}"

for cmd in helm kubectl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: '$cmd' not found in PATH"; exit 1; }
done

echo "==> Adding the Tailscale Helm repository"
helm repo add tailscale https://pkgs.tailscale.com/helmcharts --force-update >/dev/null
helm repo update >/dev/null

# OKE 1.36+ worker images run CRI-O with short-name mode "enforcing": the
# default DockerHub-style short names exist in multiple registries and are
# refused as ambiguous. Pin the synced ghcr.io images instead.
echo "==> Installing tailscale-operator into namespace '${NAMESPACE}'"
helm upgrade --install tailscale-operator tailscale/tailscale-operator \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --set-string "oauth.clientId=${OAUTH_CLIENT_ID}" \
  --set-string "oauth.clientSecret=${OAUTH_CLIENT_SECRET}" \
  --set-string "operatorConfig.hostname=${OPERATOR_HOSTNAME}" \
  --set-string "apiServerProxyConfig.mode=noauth" \
  --set "operatorConfig.image.repository=ghcr.io/tailscale/k8s-operator" \
  --set "proxyConfig.image.repository=ghcr.io/tailscale/tailscale" \
  --wait

echo "==> Operator pods"
kubectl get pods -n "${NAMESPACE}"

echo
echo "DONE. Next steps (docs/tailscale.md):"
echo "  1. Apply the Connector (subnet router) once its advertiseRoutes are filled in"
echo "  2. Approve the advertised routes in the Tailscale Machines page"
echo "  3. Point your kubecontext at https://${OPERATOR_HOSTNAME}.<tailnet>.ts.net"
