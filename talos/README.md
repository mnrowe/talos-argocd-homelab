# Talos Configuration

This directory contains Talos machine configuration patches for the cluster nodes.

## Disk Configuration

Additional disks are configured for Longhorn storage on specific nodes:

- **Node 192.168.5.104**: `/dev/nvme0n1` (512 GB) mounted at `/var/mnt/longhorn-nvme`

## Applying Patches

After initial Talos installation, apply the disk patches:

```bash
# Node 104 - Add nvme disk
talosctl -n 192.168.5.104 patch machineconfig --patch @talos/node-104-disk-patch.yaml
```

**Note:** These patches require a node reboot to take effect.

## OOM Controller Workaround

`oom-controller-patch.yaml` is applied to **all three nodes** and does **not**
require a reboot. It works around siderolabs/talos#12526 on v1.12.1, where the
default userspace OOM controller SIGKILLed Burstable/BestEffort pod cgroups
while nodes still had ~10Gi free — killing Longhorn instance-managers, which
detached volumes, which made Longhorn delete every workload pod on a loop.

```bash
for n in 192.168.5.104 192.168.5.106 192.168.5.115; do
  talosctl -n $n patch machineconfig --patch-file talos/oom-controller-patch.yaml
done
```

**Remove this patch after upgrading to Talos >= v1.12.2**, which fixes the root
cause. See the header comment in the patch file for full detail.

## Bootstrap Order

1. Install Talos on all nodes
2. Apply disk patches (this directory)
3. Reboot nodes
4. Bootstrap Kubernetes cluster
5. Install Cilium CNI
6. Deploy ArgoCD and infrastructure (see main README)

## Security

Full machine configs contain sensitive data (certificates, tokens) and are **not** stored in this repository. Only the disk configuration patches are version controlled.
