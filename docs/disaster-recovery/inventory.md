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
Runtime ownership, actual consumption, and bound-volume details remain pending
until the collector is run against the cluster.

| Workload | Namespace | Logical volume | Declared storage | Requested size | Class | Initial RPO | Initial RTO | Proposed protection | Runtime status |
|---|---|---|---|---:|---|---:|---:|---|---|
| Keycloak PostgreSQL | keycloak | keycloak-postgres-data | local-path | 10 GiB | Critical | 24 hours | 8 hours | Native PostgreSQL dump | Pending runtime verification |
| Rocket.Chat MongoDB | rocketchat | data-volume template | local-path | 10 GiB | Critical | 24 hours | 8 hours | Native MongoDB dump | Pending runtime verification |
| Jellyfin | jellyfin | jellyfin-config | local-path | 10 GiB | Important | 24 hours | 24 hours | Velero/Kopia configuration backup | Pending runtime verification |
| Jellyfin | jellyfin | jellyfin-cache | local-path | 20 GiB | Disposable | None | Recreate | Excluded | Pending runtime verification |
| Jellyfin | jellyfin | jellyfin-media | mac-nfs | 100 GiB requested | Bulk or replaceable | Decision required | 72 hours | Decision required in #81 | Pending runtime verification |
| qBittorrent | qbittorrent | qbittorrent-config | local-path | 5 GiB | Important | 24 hours | 24 hours | Velero/Kopia configuration backup | Pending runtime verification |
| qBittorrent | qbittorrent | qbittorrent-downloads | mac-nfs | 100 GiB requested | Disposable | None | Recreate | Excluded | Pending runtime verification |
| Grafana | monitoring | chart-managed PVC | local-path | 2 GiB | Important | 24 hours | 24 hours | Velero/Kopia or Git provisioning | Pending runtime verification |
| Prometheus | monitoring | chart-managed PVC | local-path | 5 GiB | Disposable | None | Recreate | Excluded | Pending runtime verification |
| Alertmanager | monitoring | chart-managed PVC | local-path | 1 GiB | Disposable | None | Recreate | Excluded | Pending runtime verification |
| Storage test | storage-test | storage-test-data | local-path | 1 GiB | Disposable | None | Recreate | Excluded | Pending runtime verification |
| NFS storage test | nfs-storage-test | downloads-test-pvc | mac-nfs | 10 GiB | Disposable | None | Recreate | Excluded; workload is not enabled by default | Pending runtime verification |

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
| Mac NFS host | NFS configuration and selected irreplaceable files | Important | Decision required | 72 hours | Kopia or approved ADR method | Filesystem inventory pending |

Private references:

- `PRIVATE-DR-DOCKER-001`
- `PRIVATE-DR-PROXMOX-001`
- `PRIVATE-DR-NFS-001`

## Runtime collection

Run the collector locally from an administrative workstation:

```bash
bash scripts/disaster-recovery/collect-kubernetes-inventory.sh
```

The collector:

- Uses only read operations
- Never requests Kubernetes Secret objects
- Creates a sanitized public PVC summary
- Writes node and PV bindings to files marked private
- Uses restrictive local permissions
- Defaults to a temporary directory outside the repository

Review all output manually. Do not commit files prefixed with
`private-runtime-`.

## Open decisions and gaps

- [ ] Run the collector against production and staging.
- [ ] Record node ownership and actual consumption in the encrypted private inventory.
- [ ] Confirm whether Jellyfin media is irreplaceable or reacquirable.
- [ ] Inventory n8n storage, database type, and encryption-key custody.
- [ ] Inventory Nexus database, configuration, and blob-store locations.
- [ ] Inventory Proxmox VMs and host configuration.
- [ ] Inventory Mac NFS capacity and identify irreplaceable directories.
- [ ] Confirm all active Secret names and required key names without reading values.
- [ ] Approve RPO and RTO targets through #81.
- [ ] Reconcile this document with runtime findings before closing #82.
