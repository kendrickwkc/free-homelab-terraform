# OCI Block Volume CSI

The platform does not provision block volumes itself; it installs the CSI driver
so tenants can request them via a `PersistentVolumeClaim`.

## 1. Install the CSI driver

Follow Oracle's current OKE CSI install (the driver is `blockvolume.csi.oraclecloud.com`):

<https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengstorage.htm>

If you prefer Helm, OKE publishes a chart for the CSI driver under the
`oci` repo. Verify the exact chart name against the link above before running.

## 2. Apply the StorageClass

OKE basic clusters already ship the Block Volume CSI driver and a default
`oci-bv` StorageClass. The committed [`storageclass.yaml`](../storageclass.yaml)
pins them explicitly (paravirtualized attachments, default-class annotation):

```sh
kubectl apply -f storageclass.yaml
```

StorageClass parameters are immutable: if an `oci-bv` already exists with
different parameters, delete it first, then re-apply (safe while no PVCs
reference it).

`WaitForFirstConsumer` delays volume provisioning until a pod is scheduled, so
the volume lands in the same AD as the node — which is also why stateful pods
should pin to the `storage=true` node via `nodeSelector`.

## 3. Requesting a volume

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-data
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: oci-bv
  resources:
    requests:
      storage: 10Gi
```

> **Ceiling:** the Always Free block-volume budget is 200 GB total, and 150 GB is
> already consumed by the three 50 GB boot volumes. That leaves **50 GB** for all
> block-backed PVCs across the whole tenancy. OCI Block Volumes also have a
> **50 GB minimum** — a smaller PVC request still provisions (and consumes) a
> full 50 GB volume, so plan for exactly one block-backed volume per tenancy.
> Size PVCs accordingly — a 51 GB request will bill you.
