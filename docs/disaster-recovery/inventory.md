# Homelab Persistent-Data Inventory

This document is the repository-safe disaster-recovery inventory for issue #82.
It records recovery requirements without exposing credentials, exact infrastructure
locations, or encryption-key material.

## Security boundary

This file is safe to commit because it contains logical resource names and
recovery classifications only.

Do not add any of the following:

- Secret values, passwords, tokens, private keys, or WireGuard configuration
- SOPS age private keys or backup repository passwords
- Authenticated URLs or database connection strings
- Exact host filesystem paths, backup bucket names, account identifiers, or
  encryption-key recovery locations
- Raw output from `kubectl`, Docker, Proxmox, or filesystem inspection

Sensitive runtime details belong in a separately encrypted private inventory.
Use opaque references such as `PRIVATE-DR-K8S-001` when this document needs to
refer to that material.

## Data classes

| Class | Description | Default RPO | Default RTO |
|---|---|---:|---:|
| Critical | Identity, credentials, databases, automation state, and bootstrap material | 24 hours | 8 hours |
| Important | Application configuration and difficult-to-recreate state | 24 hours | 24 hours |
| Bulk or replaceable | Large data that can be reacquired or regenerated | 7 days | 72 hours |
| Disposable | Caches, temporary downloads, test data, and short-retention metrics | None | Recreate |

These are initial targets. The disaster-recovery ADR in #81 must approve or
replace them.

## Kubernetes persistent data

The requested sizes and storage classes below come from the GitOps manifests.
Runtime PVC presence and binding status were verified against the production
cluster on 2026-09-20. Node ownership and actual filesystem consumption remain
in the encrypted private inventory workflow.

| Workload | Namespace | Logical volume | Declared storage | Requested size | Class | Initial RPO | Initial RTO | Proposed protection | Runtime status |
|---|---|---|---|---:|---|---:|---:|---|---|
| Keycloak PostgreSQL | keycloak | keycloak-postgres-data | local-path | 10 GiB | Critical | 24 hours | 8 hours | Native PostgreSQL dump | Bound; verified 2026-09-20 |
| Rocket.Chat MongoDB | rocketchat | data-volume-rocketchat-mongodb-0 | local-path | 10 GiB | Critical | 24 hours | 8 hours | Native MongoDB dump | Bound; verified 2026-09-20 |
| Rocket.Chat MongoDB logs | rocketchat | logs-volume-rocketchat-mongodb-0 | local-path | 2 GB | Disposable | None | Recreate | Excluded | Bound; runtime-discovered 2026-09-20 |
| Jellyfin | jellyfin | jellyfin-config | local-path | 10 GiB | Important | 24 hours | 24 hours | Velero/Kopia configuration backup | Bound; verified 2026-09-20 |
| Jellyfin | jellyfin | jellyfin-cache | local-path | 20 GiB | Disposable | None | Recreate | Excluded | Bound; verified 2026-09-20 |
| Jellyfin | jellyfin | jellyfin-media | mac-nfs | 100 GiB requested | Bulk or replaceable | Decision required | 72 hours | Decision required in #81 | Bound; verified 2026-09-20 |
| qBittorrent | qbittorrent | qbittorrent-config | local-path | 5 GiB | Important | 24 hours | 24 hours | Velero/Kopia configuration backup | Bound; verified 2026-09-20 |
| qBittorrent | qbittorrent | qbittorrent-downloads | mac-nfs | 100 GiB requested | Disposable | None | Recreate | Excluded | Bound; verified 2026-09-20 |
| Grafana | monitoring | kube-prometheus-stack-grafana | local-path | 2 GiB | Important | 24 hours | 24 hours | Velero/Kopia or Git provisioning | Bound; verified 2026-09-20 |
| Prometheus | monitoring | prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0 | local-path | 5 GiB | Disposable | None | Recreate | Excluded | Bound; verified 2026-09-20 |
| Alertmanager | monitoring | alertmanager-kube-prometheus-stack-alertmanager-db-alertmanager-kube-prometheus-stack-alertmanager-0 | local-path | 1 GiB | Disposable | None | Recreate | Excluded | Bound; verified 2026-09-20 |
| Storage test | storage-test | storage-test-data | local-path | 1 GiB | Disposable | None | Recreate | Excluded | Bound; verified 2026-09-20 |
| NFS storage test | nfs-storage-test | downloads-test-pvc | mac-nfs | 10 GiB | Disposable | None | Recreate | Excluded; workload is not enabled by default | Not present; verified 2026-09-20 |

### Verified runtime summary

- Active PVCs: 12
- Bound PVCs: 12
- Node-local `local-path` PVCs: 10
- Mac NFS PVCs: 2
- Unbound PVCs: 0
- Runtime-only finding: the MongoDB operator created
  `logs-volume-rocketchat-mongodb-0`, which is classified as disposable.
- The optional `nfs-storage-test` PVC is not deployed.

### Required private runtime fields

Store these fields only in the encrypted private inventory:

- Current owner node for each node-local PV
- Exact PV identifier when it reveals environment-specific infrastructure
- Exact NFS server and export path
- Actual filesystem consumption
- Storage-device and VM mapping
- Backup repository and account identifiers

Private reference: `PRIVATE-DR-K8S-001`.

## Secret metadata

Only names and required key names are recorded. Secret values must never be
added to this inventory.

| Namespace | Secret | Required keys or purpose | Class | Recovery method |
|---|---|---|---|---|
| flux-system | flux-system | Git authentication material | Critical | SOPS/age recovery design in #18 |
| cert-manager | cloudflare-api-token-secret | api-token | Critical | SOPS/age recovery design in #18 |
| cloudflared | cloudflared-token | TUNNEL_TOKEN | Critical | SOPS/age recovery design in #18 |
| keycloak | keycloak-db-secret | POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD | Critical | SOPS/age recovery design in #18 |
| keycloak | keycloak-admin-secret | KC_BOOTSTRAP_ADMIN_USERNAME, KC_BOOTSTRAP_ADMIN_PASSWORD | Critical | SOPS/age recovery design in #18 |
| qbittorrent | gluetun-wireguard | wg0.conf | Critical | SOPS/age recovery design in #18 |
| rocketchat | rocketchat-mongodb-user | MongoDB user password | Critical | SOPS/age recovery design in #18 |
| rocketchat | rocketchat-mongodb-connection | MongoDB connection fields required by the chart | Critical | SOPS/age recovery design in #18 |

TLS secrets issued by cert-manager are regenerated and are not authoritative
backup artifacts.

## Standalone services and hypervisor state

Exact VM identifiers, hostnames, addresses, paths, and storage-device mappings
belong in the encrypted private inventory.

| Component | State requiring protection | Initial class | Initial RPO | Initial RTO | Proposed protection | Runtime status |
|---|---|---|---:|---:|---|---|
| n8n | Database, workflows, credentials, and encryption key | Critical | 24 hours | 8 hours | Application-aware backup plus VM backup | Runtime details pending |
| Nexus | Database, configuration, and blob stores | Important | 24 hours | 24 hours | Application-aware backup plus VM backup | Runtime details pending |
| Proxmox VMs | VM configuration and virtual disks | Important | 24 hours | 24 hours | Proxmox Backup Server | VM inventory pending |
| Proxmox hosts | Cluster, network, and storage configuration | Critical | 24 hours | 8 hours | Encrypted host-configuration export | Host inventory pending |
| Mac NFS host | NFS configuration and selected irreplaceable files | Important | Decision required | 72 hours | Kopia or approved ADR method | Capacity and top-level usage verified 2026-09-20 |

### Mac NFS runtime summary

Verified locally on 2026-09-20:

| Measurement | Reported value |
|---|---:|
| Filesystem capacity | 931 GiB |
| Filesystem used | 152 GiB |
| Filesystem available | 779 GiB |
| Filesystem utilization | 17% |
| Jellyfin media directory | 105 GB reported by `du` |
| qBittorrent downloads directory | 117 GB reported by `du` |

The two directory measurements must not be added together and treated as exact
physical allocation without accounting for filesystem behavior such as clones,
sparse files, snapshots, or block sharing. The filesystem-level `df` result is
the authoritative physical-capacity view.

Both NFS PVCs request 100 GiB, but their backing static PVs advertise 900 GiB
and the directories can grow beyond the PVC request. The requested PVC size is
therefore descriptive for these static NFS volumes, not an enforced quota.

qBittorrent downloads remain classified as disposable. Jellyfin media remains
`Bulk or replaceable` until its recovery requirement is confirmed.

Private references:

- `PRIVATE-DR-DOCKER-001`
- `PRIVATE-DR-PROXMOX-001`
- `PRIVATE-DR-NFS-001`

## Runtime collection

Run the collector from the Mac or another administrative workstation that has
SSH access to the k3s control node:

```bash
bash scripts/disaster-recovery/collect-kubernetes-inventory.sh
```

It uses the same remote kubectl pattern as `k3s-health-monitor`:

```bash
ssh "$K3S_CONTROL_HOST" sudo k3s kubectl
```

Override the default SSH target when required:

```bash
K3S_CONTROL_HOST="user@control-node" \
  bash scripts/disaster-recovery/collect-kubernetes-inventory.sh
```

The collector:

- Runs only read operations through the control node over SSH
- Does not copy the collector or inventory files to the cluster
- Never requests Kubernetes Secret objects
- Creates a sanitized public PVC summary locally
- Writes node and PV bindings to local files marked private
- Uses restrictive local permissions
- Defaults to a local temporary directory outside the repository

Review all output manually. Do not commit files prefixed with
`private-runtime-`.

## Open decisions and gaps

- [ ] Run the collector against production and staging.
- [ ] Record node ownership and actual consumption in the encrypted private inventory.
- [ ] Confirm whether Jellyfin media is irreplaceable or reacquirable.
- [ ] Inventory n8n storage, database type, and encryption-key custody.
- [ ] Inventory Nexus database, configuration, and blob-store locations.
- [ ] Inventory Proxmox VMs and host configuration.
- [x] Inventory Mac NFS capacity and top-level directory usage.
- [ ] Identify which Jellyfin media, if any, is irreplaceable.
- [ ] Confirm all active Secret names and required key names without reading values.
- [ ] Approve RPO and RTO targets through #81.
- [ ] Reconcile this document with runtime findings before closing #82.
