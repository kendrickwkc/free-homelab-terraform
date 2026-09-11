# Tailscale — daily-driver cluster access

Tailscale replaces the bastion tunnel for everyday work: the cluster API, pod
IPs and service ClusterIPs become directly reachable from any device on your
tailnet — no port-forwards. The OCI Bastion remains the **bootstrap and
break-glass** path (see [bastion.md](bastion.md)): you need it once to install
the operator on a fresh cluster.

Architecture (all in the `tailscale` namespace):

- **Operator** — Helm-installed; provisions Tailscale devices from Kubernetes
  resources. Authenticates with a non-expiring OAuth client.
- **API-server proxy** (noauth mode) — exposes the Kubernetes API at
  `https://homelab-k8s.<tailnet>.ts.net` with a Let's Encrypt cert. Your
  existing OKE kubeconfig credentials keep working unchanged.
- **Subnet router** (`cluster/tailscale-connector.yaml`) — advertises the service CIDR,
  the pod CIDRs and the private subnet (`10.0.1.0/24`), so ClusterIPs and
  private-VCN services (e.g. MySQL) are reachable from your tailnet.

## Prerequisites

1. A Tailscale account; laptop client installed and logged in (`tailscale status`).
2. MagicDNS and HTTPS certificates enabled for the tailnet (admin console ->
   DNS), so `*.ts.net` names and certs are issued.
3. In the tailnet policy file, let the operator manage its devices:

   ```json
   "tagOwners": {
     "tag:k8s-operator": [],
     "tag:k8s": ["tag:k8s-operator"]
   }
   ```

4. Create an OAuth client (admin console -> Settings -> OAuth clients) with
   scopes **Devices -> Core** (Read/Write) and **Keys -> Auth Keys**
   (Read/Write). Store the secret in your password manager — it does not
   expire, but treat it as a credential and rotate on suspicion of leakage.
   Never commit it anywhere.
5. If you restrict ACLs, allow your devices TCP/443 to `tag:k8s`.

## Install (through the bastion tunnel)

```shell
./scripts/connect-k8s.sh                 # keep running; bootstrap path
kubectl config use-context homelab

OAUTH_CLIENT_ID=<id> OAUTH_CLIENT_SECRET=<secret> \
  ./scripts/install-tailscale-operator.sh
```

### Discover the CIDRs

Fill `advertiseRoutes` in `cluster/tailscale-connector.yaml`:

```shell
# Pod CIDR(s)
kubectl get nodes -o jsonpath='{range .items[*]}{.spec.podCIDR}{"\n"}{end}'
# Service CIDR (slow but authoritative)
kubectl cluster-info dump | grep -m1 service-cluster-ip-range
```

The subnet router reaches the private API endpoint through node routing, so no
extra route is needed for it beyond the above.

### Apply and approve

```shell
kubectl apply -f cluster/tailscale-connector.yaml
```

Approve the advertised routes once: Tailscale admin console -> Machines ->
`cluster-router` -> Edit route settings -> approve. (Skip approval entirely by
adding an `autoApprovers.routes` entry for `tag:k8s` to the policy file.)

## Point kubectl at the proxy

Start from your existing context (it carries the OKE token auth), then change
only the server and drop the CA bundle — the proxy's Let's Encrypt cert is
trusted by your OS:

```yaml
clusters:
  - cluster:
      server: https://homelab-k8s.<tailnet>.ts.net:443
      # remove certificate-authority-data
    name: homelab-ts
users:            # unchanged
  - name: homelab-user
    user:
      exec:
        command: oci ce cluster generate-token ...
contexts:
  - context: {cluster: homelab-ts, user: homelab-user}
    name: homelab-ts
```

Verify:

```shell
kubectl config use-context homelab-ts
kubectl get nodes
```

## Reaching workloads

With routes approved, services are reachable by ClusterIP from any tailnet
device — e.g. Meilisearch at `http://<clusterip>:7700`. Private-VCN addresses
(like the MySQL host) work too — see the
[example tenant's database step](../examples/example-tenant/README.md#5-database-optional)
for the per-tenant database flow. No port-forwarding.

## Upgrades / HA

Re-running `install-tailscale-operator.sh` performs a helm upgrade. For a
multi-replica API proxy later, migrate to a `ProxyGroup` resource
(`spec.type: kube-apiserver`) — see Tailscale's "High availability" docs.
