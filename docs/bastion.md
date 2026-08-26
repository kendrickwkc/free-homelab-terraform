# Bastion access

The OKE API endpoint and MySQL are private. Use the OCI Bastion to create
short-lived port-forward sessions rather than exposing anything publicly.

## Cluster access (private API endpoint)

Keep the kubeconfig in `~/.kube/config` as a named context (e.g. `homelab`) so
`kubectl` works from any terminal without juggling `KUBECONFIG`. The cluster
credentials are an `exec` plugin that refreshes on demand, so this is a one-time
setup.

### One-time: add the cluster as a context

```sh
# 1. Generate a kubeconfig (run from a scratch dir; writes ./kubeconfig)
oci ce cluster create-kubeconfig \
  --cluster-id <cluster-ocid> \
  --file kubeconfig \
  --region <region> \
  --token-version 2.0.0 \
  --kube-endpoint PRIVATE_ENDPOINT

# 2. Merge it into ~/.kube/config and rename the context
KUBECONFIG=~/.kube/config:./kubeconfig kubectl config view --flatten > ~/.kube/config
kubectl config rename-context <generated-context-name> homelab

# 3. Point the cluster at the local tunnel. The private API endpoint is only
#    reachable through a bastion port-forward on 127.0.0.1:6443.
kubectl config set-cluster <cluster-name> --server=https://127.0.0.1:6443
```

### Every session: open the tunnel, then use the context

Open the bastion port-forward to the private API IP on port 6443 (the tenant's
`connect-k8s.sh` automates this, or create a manual `port-forwarding` session).
The script prints `=== tunnel is up on localhost:6443 ===` once connected; the
first ssh attempt can fail transiently while the session registers its key, and
the script retries automatically:

```sh
kubectl config use-context homelab
kubectl get nodes
```

The `homelab` context only works while the tunnel is up.

## MySQL (manual per-tenant DB/user creation)

1. Find the MySQL private IP:

   ```sh
   oci mysql db-system get --db-system-id <db-system-ocid> \
     --query 'data.endpoints[0]."ip-address"' --raw-output
   ```

2. Create a port-forward session (there is no local-port flag — the generated
   SSH command binds the same port number as `--target-port`):

   ```sh
   SESSION=$(oci bastion session create-port-forwarding \
     --bastion-id <bastion-ocid> \
     --target-private-ip <mysql-private-ip> \
     --target-port 3306 \
     --ssh-public-key-file ~/.ssh/id_rsa.pub \
     --session-ttl 10800 \
     --display-name "mysql-$(date +%s)" \
     --query 'data.id' --raw-output)
   echo "$SESSION"
   ```

3. Wait for the session to become ACTIVE, then fetch its SSH command template
   and substitute the `<privateKey>` and `<localPort>` placeholders:

   ```sh
   oci bastion session get --session-id "$SESSION" \
     --query 'data."lifecycle-state"' --raw-output      # wait for ACTIVE

   oci bastion session get --session-id "$SESSION" \
     --query 'data."ssh-metadata"."command"' --raw-output
   # ssh -i <privateKey> -N -L <localPort>:<ip>:3306 -p 22 ocid1.bastionsession...@host...
   ```

4. Run that SSH command (placeholders filled) in a dedicated terminal — it
   blocks while forwarding — then connect locally:

   ```sh
   lsof -nP -iTCP:3306 -sTCP:LISTEN         # confirm ssh holds 3306
   mysql -h 127.0.0.1 -P 3306 -u admin -p   # admin = var.mysql_admin_password
   ```

   ```sql
   CREATE DATABASE IF NOT EXISTS myproject CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   CREATE USER IF NOT EXISTS 'myproject'@'%' IDENTIFIED BY '<strong-password>';
   GRANT ALL PRIVILEGES ON myproject.* TO 'myproject'@'%';
   FLUSH PRIVILEGES;
   ```

5. Close the session when done (sessions auto-expire at the TTL).
