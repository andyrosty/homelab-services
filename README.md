# Homelab Services

Declarative GitOps config for a k3s homelab. Flux CD continuously reconciles the
cluster from this repository, including networking, TLS, monitoring, storage,
and media/service workloads.

## Repository layout

```
.
├── apps/
│   ├── cloudflared/      # Cloudflare Tunnel connector
│   ├── homepage/         # Homepage dashboard (HelmRelease)
│   ├── jellyfin/         # Jellyfin deployment + ingress + PVCs
│   ├── nfs-storage-test/ # Optional pod/PVC for mac-nfs validation
│   ├── qbittorrent/      # qBittorrent deployment + ingress + PVCs
│   ├── smoke-test/       # Minimal nginx app for ingress checks
│   └── storage-test/     # BusyBox writer + PVC for storage checks
├── clusters/
│   └── homelab/
│       ├── flux-system/  # Flux bootstrap manifests (gotk)
│       └── kustomization.yaml
├── infrastructure/
│   ├── cert-manager/     # cert-manager + Cloudflare ClusterIssuer
│   ├── metallb/          # Bare-metal LoadBalancer IP assignment
│   ├── monitoring/       # kube-prometheus-stack (Prometheus/Grafana)
│   ├── nfs-storage/      # Static PVs backed by NFS shares
│   └── nginx-ingress/    # NGINX Ingress Controller (HelmRelease)
└── Makefile              # Remote sync/deploy/status helpers
```

The cluster entrypoint is `clusters/homelab/kustomization.yaml`.

## Active stack (what gets applied)

`clusters/homelab/kustomization.yaml` currently includes:

- Infrastructure: MetalLB, NGINX Ingress, cert-manager, monitoring, NFS storage.
- Apps: qBittorrent, smoke-test, Jellyfin, Homepage, storage-test, cloudflared.

`apps/nfs-storage-test` is available for manual testing but is not part of the
default cluster kustomization.

## Prerequisites

| Requirement | Purpose |
|-------------|---------|
| k3s control node | Remote cluster where manifests are applied. |
| `kubectl` + `flux` CLI | Bootstrap, reconciliation, and troubleshooting. |
| SSH access to control node | Required by `make` helper targets. |
| Git credentials/token | Required for Flux `GitRepository` authentication. |

Update `CONTROL_NODE` and `REMOTE_DIR` in `Makefile` for your environment.

## Bootstrap flow

1. Clone the repo:

   ```bash
   git clone git@github.com:andyrosty/homelab-services.git
   cd homelab-services
   ```

2. (Optional) If local DNS is not configured, map ingress hosts in `/etc/hosts`
   to your MetalLB IP:

   ```bash
   sudo vim /etc/hosts
   # Example entries
   192.168.50.240 smoke-test.dev-andrew.com homepage.dev-andrew.com
   192.168.50.240 jellyfin.dev-andrew.com qbittorrent.dev-andrew.com
   192.168.50.240 grafana.dev-andrew.com
   ```

3. Create Flux Git credentials in `flux-system`:

   ```bash
   kubectl create namespace flux-system
   flux create secret git flux-system \
     --namespace=flux-system \
     --url=https://github.com/andyrosty/homelab-services.git \
     --username=$GITHUB_USER \
     --password=$GITHUB_TOKEN
   ```

4. Apply manifests from your workstation:

   ```bash
   make deploy
   ```

5. Verify reconciliation:

   ```bash
   kubectl get pods -n flux-system
   flux reconcile kustomization flux-system --with-source
   flux get kustomizations --watch
   ```

## Main components

- `infrastructure/metallb`: advertises `192.168.50.240-192.168.50.250` by
  default (adjust for your LAN).
- `infrastructure/nginx-ingress`: NGINX Ingress Controller with `LoadBalancer`
  service so it receives an IP from MetalLB.
- `infrastructure/cert-manager`: cert-manager plus
  `letsencrypt-cloudflare` ClusterIssuer for DNS-01.
- `infrastructure/monitoring`: `kube-prometheus-stack` with persisted
  Prometheus, Alertmanager, and Grafana.
- `infrastructure/nfs-storage`: static `PersistentVolume` objects pointing at
  NFS exports (storage class `mac-nfs`).

## Applications

- `apps/homepage`: dashboard UI served at `homepage.dev-andrew.com`.
- `apps/smoke-test`: simple nginx ingress validation at
  `smoke-test.dev-andrew.com`.
- `apps/storage-test`: write-loop pod for quick PVC/storage checks.
- `apps/jellyfin`: media server with config/cache/media PVCs and TLS ingress.
- `apps/qbittorrent`: torrent client with config/download PVCs and TLS ingress.
- `apps/cloudflared`: Cloudflare tunnel connector using token secret.

## Makefile shortcuts

| Target | Description |
|--------|-------------|
| `make sync` | Copies `apps/` and `clusters/` to the control node. |
| `make deploy` | Runs `make sync` then applies `clusters/homelab` remotely. |
| `make status` | Shows nodes, pods, and services from the remote cluster. |
| `make delete` | Deletes resources defined by `clusters/homelab`. |
| `make install-ingress` | Legacy one-off helper for manual ingress install. |

## Validation pipeline

`.github/workflows/validate.yaml` runs on pushes/PRs and includes:

- `yamllint`
- `kustomize build clusters/homelab`
- `kubeconform` (strict schema checks)
- `trivy config` (HIGH/CRITICAL misconfiguration scan)

Running the same checks locally before push helps catch issues early.

## Troubleshooting

- Keep MetalLB IP ranges outside DHCP scope.
- Recreate Flux git credentials if source reconciliation fails.
- Confirm ingress hostnames resolve to the assigned MetalLB IP.
