# OCI Block Volume CSI

The platform does not provision block volumes itself; it installs the CSI driver
so tenants can request them via a `PersistentVolumeClaim`.

## 1. Install the CSI driver

Follow Oracle's current OKE CSI install (the driver is `blockvolume.csi.oraclecloud.com`):

<https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengstorage.htm>

If you prefer Helm, OKE publishes a chart for the CSI driver under the
`oci` repo. Verify the exact chart name against the link above before running.

## 2. Create the StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: oci-bv
provisioner: blockvolume.csi.oraclecloud.com
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  attachment-type: "paravirtualized"
```

```sh
kubectl apply -f storageclass.yaml
```

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
> block-backed PVCs across the whole tenancy. Size PVCs accordingly — a 51 GB
> request will bill you.
