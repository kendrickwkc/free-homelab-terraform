#!/usr/bin/env bash
# Open a bastion port-forward tunnel to the private OKE API endpoint.
#
# This is the BOOTSTRAP / BREAK-GLASS path. The daily-driver access method is
# Tailscale (see docs/tailscale.md): use this script once to install the
# Tailscale operator on a fresh cluster, and whenever Tailscale itself is
# unavailable.
#
# Usage:
#   ./scripts/connect-k8s.sh
#
# This script does NOT manage a kubeconfig file. Configure your cluster context
# once (see docs/bastion.md) so it lives in ~/.kube/config,
# then switch to it and use kubectl against the tunnel while this script runs:
#
#   kubectl config use-context homelab
#   kubectl get nodes
#
# Environment overrides:
#   SSH_KEY         private SSH key (default: ~/.ssh/id_rsa)
#   SSH_PUB_KEY     public SSH key (default: ${SSH_KEY}.pub)
#   SESSION_TTL     bastion session TTL in seconds (default: 3600, max 10800)
#   CONNECT_DEBUG=1 print the ssh command (redacted) and run with -vvv

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$REPO_ROOT/platform"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
SSH_PUB_KEY="${SSH_PUB_KEY:-${SSH_KEY}.pub}"
SESSION_TTL="${SESSION_TTL:-3600}"
API_PORT=6443
LOCAL_PORT=6443

export OCI_CLI_NO_COLOR=1

# ── Preconditions ─────────────────────────────────────────
for cmd in oci ssh terraform python3; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: '$cmd' not found in PATH"; exit 1; }
done

if [[ ! -f "$SSH_KEY" ]]; then
  echo "ERROR: private key not found: $SSH_KEY"
  echo "Set SSH_KEY to the private key matching the public key in $SSH_PUB_KEY"
  exit 1
fi

if [[ ! -f "$SSH_PUB_KEY" ]]; then
  echo "ERROR: public key not found: $SSH_PUB_KEY"
  exit 1
fi

if [[ "$SESSION_TTL" -lt 1800 ]]; then
  echo "WARNING: OCI Bastion session TTL must be >= 1800s; using 1800s"
  SESSION_TTL=1800
fi

# Ensure the SSH key is available to the agent. This is required for the
# bastion tunnel to authenticate in non-interactive contexts.
key_fp=$(ssh-keygen -lf "$SSH_PUB_KEY" 2>/dev/null | awk '{print $2}')
if ! ssh-add -l 2>/dev/null | grep -q "$key_fp"; then
  echo "Loading SSH key into agent..."
  ssh-add "$SSH_KEY" >/dev/null 2>&1 || echo "WARNING: could not add $SSH_KEY to ssh-agent; relying on -i flag"
fi

# ── Cluster API private endpoint (authoritative, from platform state) ──
cd "$TF_DIR"
api_endpoint=$(terraform output -raw cluster_private_endpoint)
if [[ -z "$api_endpoint" ]]; then
  echo "ERROR: could not find cluster private endpoint in Terraform state"
  exit 1
fi
api_ip=$(echo "$api_endpoint" | sed -E 's|:6443||')
echo "Cluster API endpoint: $api_ip:$API_PORT"

# ── Bastion details ───────────────────────────────────────
bastion_id=$(terraform output -raw bastion_id)
echo "Bastion OCID: $bastion_id"

# ── Existing listener check ───────────────────────────────
if command -v lsof >/dev/null 2>&1 && lsof -Pi :$LOCAL_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
  echo "WARNING: something is already listening on localhost:$LOCAL_PORT"
  read -r -p "Continue anyway? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || exit 0
fi

# ── Create bastion session ────────────────────────────────
echo "Creating OCI Bastion port-forwarding session (TTL ${SESSION_TTL}s)..."
session_json=$(oci bastion session create-port-forwarding \
  --bastion-id "$bastion_id" \
  --target-private-ip "$api_ip" \
  --target-port "$API_PORT" \
  --session-ttl "$SESSION_TTL" \
  --ssh-public-key-file "$SSH_PUB_KEY" \
  --display-name "connect-k8s-$(date +%s)" \
  --output json 2>/dev/null)

session_id=$(echo "$session_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['id'])")
echo "Session OCID: $session_id"

# Poll until ACTIVE (or terminal failure)
echo -n "Waiting for session to become ACTIVE"
for i in {1..30}; do
  state=$(oci bastion session get --session-id "$session_id" --output json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['lifecycle-state'])")
  echo -n "."
  if [[ "$state" == "ACTIVE" ]]; then
    echo " ACTIVE"
    break
  fi
  if [[ "$state" == "FAILED" || "$state" == "DELETED" || "$state" == "CANCELING" ]]; then
    echo
    echo "ERROR: bastion session entered $state state"
    exit 1
  fi
  sleep 2
done

# The bastion registers the session's public key shortly after ACTIVE; sshing
# immediately can transiently fail with "Permission denied (publickey)". Give it
# a moment to settle before the first attempt (the retry below is the backstop).
sleep 2

ssh_meta_cmd=$(oci bastion session get --session-id "$session_id" --output json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['ssh-metadata']['command'])")

# Extract the bastion SSH target ("<session>@host.bastion.<region>.oci.oraclecloud.com")
# from OCI's command, so we don't depend on its exact placeholder format.
bastion_target=$(printf '%s' "$ssh_meta_cmd" | grep -oE '[^[:space:]]+@host\.bastion\.[^[:space:]]+' | head -1)
if [[ -z "$bastion_target" ]]; then
  echo "ERROR: could not determine bastion SSH target from OCI command" >&2
  exit 1
fi

# Build our own robust tunnel command instead of substituting placeholders into
# OCI's command. IdentitiesOnly + explicit -i guarantee the exact key uploaded to
# the session is always presented, avoiding ssh-agent key-order and OCI
# placeholder-substitution failures that cause "Permission denied (publickey)".
# 127.0.0.1 is used as the forward target host (the bastion session enforces the
# real target private IP; the loopback host keeps local binding deterministic).
ssh_args=(
  -o IdentitiesOnly=yes
  -o ExitOnForwardFailure=yes
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=3
  -i "$SSH_KEY"
  -N
  -L "$LOCAL_PORT:127.0.0.1:$API_PORT"
  "$bastion_target"
)
if [[ "${CONNECT_DEBUG:-0}" == "1" ]]; then
  printf '%s\n' "=== DEBUG: ssh command (session id redacted) ==="
  printf 'ssh %s\n' "${ssh_args[*]}" | sed -E 's/[a-f0-9]{20,}/<SESSION>/g'
  ssh_args=("-vvv" "${ssh_args[@]}")
fi

# ── Cleanup on exit ───────────────────────────────────────
cleanup() {
  echo
  echo "Closing bastion session and tunnel..."
  oci bastion session delete --session-id "$session_id" --force >/dev/null 2>&1 || true
}
trap cleanup INT TERM EXIT

# ── Open SSH tunnel (with retry on transient failures) ────
echo "Opening SSH tunnel to $api_ip:$API_PORT on localhost:$LOCAL_PORT (Ctrl-C to close)..."
echo
echo "Once connected, run kubectl in another terminal:"
echo "  kubectl config use-context homelab"
echo "  kubectl get nodes"
echo

# ── Success notification (background) ─────────────────────
# ssh -N blocks silently once connected, which can look like a hang. Poll the
# local port and print a clear confirmation as soon as the tunnel is up.
(
  for i in {1..30}; do
    if lsof -Pi :$LOCAL_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
      echo
      echo "=== tunnel is up on localhost:$LOCAL_PORT ==="
      break
    fi
    sleep 1
  done
) &

attempt=1
max_attempts=5
while :; do
  if ssh "${ssh_args[@]}"; then
    break
  fi
  if [[ $attempt -ge $max_attempts ]]; then
    echo "ERROR: SSH tunnel failed after $max_attempts attempts" >&2
    exit 1
  fi
  echo "SSH tunnel attempt $attempt failed; retrying in 3s..."
  attempt=$((attempt + 1))
  sleep 3
done
