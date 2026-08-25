# Shared Meilisearch (optional)

A single Meilisearch instance runs in the `platform` namespace, pinned to the
`storage=true` node with a block-backed volume. Tenants query it cross-namespace
at `http://meilisearch.platform.svc.cluster.local:7700` and authenticate with
their own API keys (never the master key).

## 1. Seal the master key

```sh
kubectl create namespace platform
# write secret.yaml with MEILI_MASTER_KEY, then:
kubeseal --controller-name sealed-secrets --controller-namespace kube-system \
  < secret.yaml > meilisearch-master-key-sealed.yaml
kubectl apply -f meilisearch-master-key-sealed.yaml
```

## 2. Deploy

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: meilisearch-data
  namespace: platform
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: oci-bv
  resources:
    requests:
      storage: 50Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: meilisearch
  namespace: platform
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels: { app: meilisearch }
  template:
    metadata:
      labels: { app: meilisearch }
    spec:
      nodeSelector:
        storage: "true"
      containers:
        - name: meilisearch
          image: getmeili/meilisearch:v1.53.0
          ports: [{ containerPort: 7700 }]
          env:
            - name: MEILI_ENV
              value: production
            - name: MEILI_MASTER_KEY
              valueFrom:
                secretKeyRef:
                  name: meilisearch-master-key
                  key: MEILI_MASTER_KEY
          volumeMounts:
            - name: data
              mountPath: /meili_data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: meilisearch-data
---
apiVersion: v1
kind: Service
metadata:
  name: meilisearch
  namespace: platform
spec:
  selector: { app: meilisearch }
  ports: [{ port: 7700, targetPort: 7700 }]
```

> **Ceiling:** the 50 Gi above consumes the *entire* remaining block-volume
> budget (see docs/csi.md). If tenants also need block-backed volumes, shrink
> this PVC to leave headroom.

## 3. Per-tenant API keys

After deploy, mint a key per tenant using the Meili API and hand it to the
tenant to seal into their own namespace:

```sh
curl -X POST http://localhost:7700/keys \
  -H "Authorization: Bearer $MEILI_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{ "name": "myproject", "actions": ["*"], "indexes": ["myproject*"], "expiresAt": null }'
```
