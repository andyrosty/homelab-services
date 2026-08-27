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
│   ├── keycloak/         # Keycloak identity provider + PostgreSQL
│   ├── nfs-storage-test/ # Optional pod/PVC for mac-nfs validation
│   ├── qbittorrent/      # qBittorrent + Keycloak OIDC proxy + PVCs
│   ├── rocketchat/       # Rocket.Chat + MongoDB Community Operator
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
- Apps: qBittorrent (protected by oauth2-proxy), smoke-test, Jellyfin,
  Homepage, storage-test, cloudflared, Keycloak, and Rocket.Chat.

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
   192.168.50.240 jellyfin.dev-andrew.com qbittorrent.dev-andrew.com keycloak.dev-andrew.com
   192.168.50.240 grafana.dev-andrew.com
   192.168.50.240 rocketchat.dev-andrew.com
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

   Before reconciling the full stack, also create the application and
   infrastructure secrets described in [Required secrets](#required-secrets).

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
  NFS exports (storage class `mac-nfs`). The media and downloads volumes use
  `192.168.50.227` and retain their data when claims are released.

## Applications

- `apps/homepage`: dashboard UI served at `homepage.dev-andrew.com`.
- `apps/smoke-test`: simple nginx ingress validation at
  `smoke-test.dev-andrew.com`.
- `apps/storage-test`: write-loop pod for quick PVC/storage checks.
- `apps/jellyfin`: media server with config/cache/media PVCs and TLS ingress.
- `apps/keycloak`: identity provider backed by PostgreSQL, served at
  `keycloak.dev-andrew.com`.
- `apps/qbittorrent`: torrent client with config/download PVCs and TLS ingress;
  its UI is protected by an oauth2-proxy using the Keycloak `homelab` realm.
- `apps/cloudflared`: Cloudflare tunnel connector using token secret.
- `apps/rocketchat`: Rocket.Chat, exposed at `rocketchat.dev-andrew.com`, with
  a single-member MongoDB replica set managed by MongoDB Community Operator.
  MongoDB data uses the `local-path` storage class; the application and
  database workloads target nodes labelled `workload=applications` and
  `workload=database`, respectively.

## Required secrets

Secrets are intentionally not committed. Create these before enabling the
corresponding component:

| Namespace | Secret | Required keys / purpose |
|-----------|--------|-------------------------|
| `cert-manager` | `cloudflare-api-token-secret` | `api-token` for the Cloudflare DNS-01 issuer. |
| `cloudflared` | `cloudflared-token` | `TUNNEL_TOKEN` for the Cloudflare tunnel. |
| `keycloak` | `keycloak-db-secret` | `POSTGRES_DB`, `POSTGRES_USER`, and `POSTGRES_PASSWORD`. |
| `keycloak` | `keycloak-admin-secret` | `KC_BOOTSTRAP_ADMIN_USERNAME` and `KC_BOOTSTRAP_ADMIN_PASSWORD`. |
| `qbittorrent` | `gluetun-wireguard` | `wg0.conf` WireGuard configuration. |
| `rocketchat` | `rocketchat-mongodb-user` | MongoDB user password used by the Community Operator. |
| `rocketchat` | `rocketchat-mongodb-connection` | Rocket.Chat MongoDB connection details expected by the chart. |

Flux Git credentials are created separately in `flux-system` during bootstrap.
TLS secrets are issued automatically by cert-manager after the Cloudflare token
is available and DNS is configured.

## Adding an application

Each application is a self-contained Kustomize package under `apps/<app-name>`.
Use an existing app such as `apps/smoke-test` as a starting point, then:

1. Create `apps/<app-name>/kustomization.yaml` and list every manifest it owns.
   At minimum, include a namespace and workload; add a Service, Ingress, PVCs, or
   Flux `HelmRepository`/`HelmRelease` resources as needed.

   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization

   resources:
     - namespace.yaml
     - deployment.yaml
     - service.yaml
     - ingress.yaml
   ```

2. Keep all resources scoped to the app namespace. If the app needs persistent
   storage, request the appropriate storage class: `mac-nfs` for the static
   NFS-backed media/download volumes or `local-path` for node-local data. For
   HTTP apps, point the Ingress at the app Service and use a hostname that
   resolves to the MetalLB ingress IP.

3. Do not commit credentials, API tokens, or private keys. Create required
   Kubernetes secrets in the target namespace separately, and reference their
   names from the manifests. Document any required secret keys alongside the app.

4. Enable the application by adding its directory to the `resources` list in
   `clusters/homelab/kustomization.yaml`:

   ```yaml
   resources:
     # ...existing infrastructure and apps...
     - ../../apps/<app-name>
   ```

5. Test the change on the `staging` branch. All testing phases, including
   manifest validation and deployment testing, must be completed on `staging`
   before the change is promoted to `main`:

   ```bash
   git switch staging
   kustomize build clusters/homelab
   make deploy
   flux reconcile kustomization flux-system --with-source
   kubectl get pods -n <app-name>
   ```

   Merge or open a pull request from `staging` to `main` only after the staging
   checks and application-specific verification succeed.

An app directory can remain in `apps/` without being deployed; omit it from
`clusters/homelab/kustomization.yaml` until it is ready to enable.

## Makefile shortcuts

| Target | Description |
|--------|-------------|
| `make sync` | Re-creates the remote working directory and copies `apps/` and `clusters/` to the control node. |
| `make deploy` | Runs `make sync` then applies `clusters/homelab` remotely. The current target does not copy `infrastructure/`, so update the target before relying on it for a clean remote directory. |
| `make status` | Shows nodes, pods, and services from the remote cluster. |
| `make delete` | Deletes resources defined by `clusters/homelab`. |
| `make install-ingress` | Legacy one-off helper for manual ingress install. |

## Validation pipeline

`.github/workflows/validate.yaml` runs on pushes and pull requests to `main`.
The `staging` branch contains the staging validation workflow and is the
required environment for every testing phase before promotion to `main`.

The validation workflow includes:

- `yamllint`
- `kustomize build clusters/homelab`
- `kubeconform` (strict schema checks)
- `trivy config` (HIGH/CRITICAL misconfiguration scan)

Running the same checks locally before push helps catch issues early.

## Troubleshooting

- Keep MetalLB IP ranges outside DHCP scope.
- Recreate Flux git credentials if source reconciliation fails.
- Confirm ingress hostnames resolve to the assigned MetalLB IP.
