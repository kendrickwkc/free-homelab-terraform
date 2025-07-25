# Bastion access

The OKE API endpoint and MySQL are private. Use the OCI Bastion to create
short-lived port-forward sessions rather than exposing anything publicly.

## Kubeconfig (private API endpoint)

```sh
oci ce cluster create-kubeconfig \
  --cluster-id <cluster-ocid> \
  --file kubeconfig \
  --region <region> \
  --token-version 2.0.0 \
  --kube-endpoint PRIVATE_ENDPOINT
```

`kubectl` then reaches the API through a bastion port-forward session to the
private API endpoint IP on port 6443 (same flow as MySQL below, target port 6443).

## MySQL (manual per-tenant DB/user creation)

1. Find the MySQL private IP:

   ```sh
   oci mysql db-system get --db-system-id <db-system-ocid> --query 'data.endpoints[0].ip-address'
   ```

2. Create a port-forward session:

   ```sh
   oci bastion session create-port-forwarding \
     --bastion-id <bastion-ocid> \
     --target-private-ip <mysql-private-ip> \
     --target-port 3306 \
     --local-port 3306 \
     --key-type PUB \
     --ssh-public-key-file ~/.ssh/id_ed25519.pub \
     --session-ttl 10800
   ```

3. Fetch the SSH command for the session:

   ```sh
   oci bastion session get --session-id <session-ocid> --query 'data.ssh_metadata.command'
   ```

4. Run that SSH command to open the tunnel, then connect locally:

   ```sh
   mysql -h 127.0.0.1 -P 3306 -u admin -p
   ```

   ```sql
   CREATE DATABASE myproject;
   CREATE USER 'myproject'@'%' IDENTIFIED BY '<password>';
   GRANT ALL PRIVILEGES ON myproject.* TO 'myproject'@'%';
   ```

5. Close the session when done (sessions auto-expire at the TTL).
