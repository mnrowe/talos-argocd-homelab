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

## Upgrading Talos — always use the Image Factory image

These nodes run a custom Image Factory build carrying three system extensions:

| Extension | Needed for |
|---|---|
| `i915` | Intel GPU / QuickSync — Jellyfin hardware transcode (`/dev/dri`) |
| `iscsi-tools` | Longhorn volume attach |
| `util-linux-tools` | — |

Schematic ID: `0751f1135eff2bc906854a62cc450c94f3dc65428d42110fc7998db8959dd5e5`

**Upgrading with the stock `ghcr.io/siderolabs/installer` image silently strips
all three extensions.** That breaks Longhorn on the node (`CSINode ... does not
contain driver driver.longhorn.io`, longhorn-manager CrashLoop on a missing
`iscsiadm`) and removes `/dev/dri`, so Jellyfin loses hardware transcode. Node
data is unaffected — re-running the upgrade with the correct image restores it.

Always upgrade with:

```bash
IMG=factory.talos.dev/metal-installer/0751f1135eff2bc906854a62cc450c94f3dc65428d42110fc7998db8959dd5e5:vX.Y.Z
talosctl -n <node-ip> upgrade --image $IMG --wait
```

One node at a time; Talos refuses to proceed if it would break etcd quorum.
Upgrade the etcd leader last (`talosctl -n <ip> etcd status` shows the leader).
Verify afterwards:

```bash
talosctl -n <node-ip> get extensions   # expect i915, iscsi-tools, util-linux-tools
talosctl -n <node-ip> ls /dev/dri      # expect card0 + renderD128 on GPU nodes
```

**Note:** `machine.install.image` is set to the factory image on all three nodes
via `install-image-patch.yaml`. Keep its tag in step when upgrading, and still
pass `--image` explicitly to `talosctl upgrade` — the config value is only
consulted at install time, so it is a safety net, not the mechanism.

## OOM Controller (historical)

Talos v1.12.0/v1.12.1 shipped a userspace OOM controller that SIGKILLed
Burstable/BestEffort pod cgroups while nodes still had ~10Gi free
(siderolabs/talos#12526). It killed Longhorn instance-managers, which detached
volumes, which made Longhorn delete every workload pod on a loop.

Resolved by upgrading to **v1.12.11**. Note that the `OOMConfig` machine config
document is *not* honoured on v1.12.x — the resource is not registered
(`talosctl get oomconfig` returns NotFound), so tuning the controller via config
is not an option on this release; upgrading is.

## Bootstrap Order

1. Install Talos on all nodes
2. Apply disk patches (this directory)
3. Reboot nodes
4. Bootstrap Kubernetes cluster
5. Install Cilium CNI
6. Deploy ArgoCD and infrastructure (see main README)

## Security

Full machine configs contain sensitive data (certificates, tokens) and are **not** stored in this repository. Only the disk configuration patches are version controlled.
