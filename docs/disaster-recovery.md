# Disaster Recovery Guide

This guide explains how to recover PVC data from Kopia backups in your homelab cluster.

## Overview

The cluster has **automatic disaster recovery** enabled for any PVC labeled with `backup: "daily"` or `backup: "hourly"`. If a backed-up PVC is deleted, it will automatically restore from the latest Kopia backup when recreated.

## Automatic Restore (Zero-Touch)

This is the **primary recovery method** and requires no manual intervention.

### How It Works

1. A PVC with backup label (e.g., `jellyfin-config`) gets deleted
2. ArgoCD automatically recreates the PVC from Git
3. Kyverno detects the backup exists (via pvc-plumber)
4. Kyverno adds `dataSourceRef` to the PVC spec
5. VolSync volume populator restores data from Kopia
6. Pod starts with fully restored data

### Example: Jellyfin Config Recovery

If the `jellyfin-config` PVC is lost:

```bash
# Delete the PVC (disaster scenario)
kubectl delete pvc jellyfin-config -n jellyfin

# ArgoCD will recreate it automatically
# Kyverno will detect backup exists and trigger restore
# Wait for restore to complete (typically 3-5 minutes for 3.5 GB)

# Verify restore completed
kubectl get pvc jellyfin-config -n jellyfin
# Should show STATUS: Bound

# Check pod is running
kubectl get pods -n jellyfin
```

### Verification

Check the PVC events to see restore progress:

```bash
kubectl describe pvc <pvc-name> -n <namespace>
```

Look for these events:
- `VolSyncPopulatorPVCCreated` - Restore started
- `VolSyncPopulatorFinished` - Restore completed

## Manual Restore (Special Cases)

Use manual restore only when:
- You want to restore to a **different PVC name** (testing, migration)
- You need to restore while the original PVC still exists
- You want to restore a specific backup snapshot (not latest)

### Method 1: Trigger Restore on Existing ReplicationDestination

If the ReplicationDestination already exists:

```bash
# Trigger the restore
kubectl patch replicationdestination <pvc-name>-backup -n <namespace> \
  --type merge \
  -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'

# Wait for restore job to complete (example: 3.5 GB takes ~3-5 min)
kubectl wait --for=condition=complete --timeout=10m \
  job/volsync-dst-<pvc-name>-backup -n <namespace>

# Check the snapshot was created
kubectl get volumesnapshot -n <namespace>

# Create a new PVC from the snapshot
kubectl get replicationdestination <pvc-name>-backup -n <namespace> \
  -o jsonpath='{.status.latestImage.name}'
```

Then create a PVC with `dataSource` pointing to that snapshot.

### Method 2: Restore to Different PVC Name

Create a new PVC manifest with `dataSourceRef`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jellyfin-config-restored  # Different name
  namespace: jellyfin
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  dataSourceRef:
    apiGroup: volsync.backube
    kind: ReplicationDestination
    name: jellyfin-config-backup  # Points to original backup
  resources:
    requests:
      storage: 10Gi
```

Apply and the volume populator will restore:

```bash
kubectl apply -f restore-pvc.yaml
kubectl get pvc jellyfin-config-restored -n jellyfin -w
```

## Backup Schedule & Retention

Current configuration for PVCs labeled `backup: "daily"`:

- **Schedule**: Daily at 3:00 AM EST
- **Retention**:
  - Keep 2 daily backups
  - Keep 1 weekly backup
  - Keep 1 monthly backup

## Checking Backup Status

### View Backup Jobs

```bash
# Check ReplicationSource status
kubectl get replicationsource -n <namespace>

# View recent backup jobs
kubectl get jobs -n <namespace> | grep volsync-src

# Check last backup time
kubectl get replicationsource <pvc-name>-backup -n <namespace> \
  -o jsonpath='{.status.lastSyncTime}'
```

### View Backups in Kopia UI

1. Access Kopia UI at: `https://kopia.your-domain.com`
2. Navigate to **Snapshots**
3. Find snapshots named: `<pvc-name>-backup@<namespace>:/data`
4. Example: `jellyfin-config-backup@jellyfin:/data`

### Using Kopia CLI

Access the Kopia repository directly:

```bash
# Exec into kopia-ui pod
kubectl exec -it deployment/kopia-ui -n kopia -- sh

# List all snapshots
kopia snapshot list

# List snapshots for specific PVC
kopia snapshot list <pvc-name>-backup@<namespace>:/data

# Show snapshot details
kopia snapshot show <snapshot-id>
```

## Troubleshooting

### PVC Stuck in Pending After Restore

**Symptom**: PVC shows `STATUS: Pending` after restore job completes

**Check**:
```bash
# View PVC events
kubectl describe pvc <pvc-name> -n <namespace>

# Check for VolumeSnapshot
kubectl get volumesnapshot -n <namespace>

# Check ReplicationDestination has latestImage
kubectl get replicationdestination <pvc-name>-backup -n <namespace> \
  -o jsonpath='{.status.latestImage}'
```

**Solution**: Usually resolves automatically once the VolumeSnapshot is ready (1-2 minutes). If stuck, check Longhorn CSI provisioner logs.

### Backup Not Running

**Check if ReplicationSource exists**:
```bash
kubectl get replicationsource -n <namespace>
```

**If missing**, verify:
1. PVC has `backup: "daily"` or `backup: "hourly"` label
2. Kyverno policies are running: `kubectl get clusterpolicy`
3. Check Kyverno logs: `kubectl logs -n kyverno -l app.kubernetes.io/component=background-controller`

### Restore Job Failed

**View job logs**:
```bash
# Find the restore job
kubectl get jobs -n <namespace> | grep volsync-dst

# View logs
kubectl logs job/volsync-dst-<pvc-name>-backup -n <namespace>
```

**Common issues**:
- **Kopia password mismatch**: Check secret `volsync-<pvc-name>` has correct password
- **Repository not found**: Verify NFS mount at `/mnt/pool/share/volsync-kopia` is accessible
- **Insufficient permissions**: Check pod runs as UID/GID 568

## Recovery Time Estimates

Based on restore performance (~47 MB/s):

| Data Size | Estimated Restore Time |
|-----------|------------------------|
| 1 GB      | ~30 seconds            |
| 3.5 GB    | ~3-5 minutes           |
| 10 GB     | ~5-10 minutes          |
| 50 GB     | ~20-30 minutes         |

Actual times depend on NFS network speed and Kopia deduplication/compression efficiency.

## What Gets Backed Up

Only PVCs with these labels are backed up:
- `backup: "hourly"` - Hourly backups (if configured)
- `backup: "daily"` - Daily backups at 3 AM

### Excluded from Backups

- **Cache PVCs**: `jellyfin-cache` (regenerable data)
- **NFS-backed PVCs**: `jellyfin-media` (already on NFS, not Longhorn)
- **Unlabeled PVCs**: Any PVC without a backup label

## Where Backups Are Stored

- **Storage Backend**: NFS at `192.168.5.10:/mnt/pool/share/volsync-kopia`
- **Format**: Kopia repository (encrypted, deduplicated, compressed)
- **Accessible via**: Kopia UI pod in `kopia` namespace

## Emergency: Complete Cluster Rebuild

If the entire cluster is lost:

1. **Rebuild cluster** (Talos, ArgoCD, core infrastructure)
2. **Deploy storage stack** (Longhorn, VolSync, Kyverno, pvc-plumber)
3. **Manually apply Kopia secret**:
   ```bash
   sops --decrypt infrastructure/storage/volsync/volsync-kopia-secret.yaml | kubectl apply -f -
   ```
4. **Deploy applications** via ArgoCD
5. **Automatic restore triggers** for all labeled PVCs

All application data will automatically restore from the NFS-backed Kopia repository.
