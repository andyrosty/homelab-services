<div align="center">

# Homelab Services

Declarative GitOps configuration for my k3s-based homelab. Flux CD keeps the
cluster reconciled using the manifests in this repository, provisioning the
networking building blocks (MetalLB + NGINX Ingress) and a set of applications
including a homepage dashboard and a smoke-test app to verify that the ingress
path is healthy.

</div>

## Repository layout

```
.
├── apps/                # Application manifests
│   ├── homepage/        # Homepage dashboard (Flux-managed HelmRelease)
│   ├── smoke-test/      # Minimal nginx deployment + ingress rule
│   └── storage-test/    # Busybox writer + PVC to verify storage
├── clusters/
│   └── homelab/         # Cluster entrypoint: Flux + infra + apps
│       └── flux-system/ # Flux controllers and GitRepository/Kustomization
├── infrastructure/
│   ├── metallb/         # Bare-metal LoadBalancer implementation
│   ├── nginx-ingress/   # NGINX Ingress Controller with LoadBalancer service
│   ├── cert-manager/    # Helm-managed cert-manager + ClusterIssuer
│   ├── monitoring/      # kube-prometheus-stack (Prometheus + Grafana)
│   └── nfs-storage/     # Static PersistentVolumes backed by Mac NFS shares
└── Makefile             # Helper targets for syncing and applying manifests
```

Everything is wired together through `clusters/homelab/kustomization.yaml`, so
`kubectl apply -k clusters/homelab` (or the `make deploy` target) is all that is
required to seed a new cluster.

## Prerequisites

| Requirement | Purpose |
|-------------|---------|
| Linux node with k3s | Target control node referenced in the `Makefile`. |
| `kubectl` & `flux` CLI | Used locally (and on the cluster) to manage Flux. |
| SSH access | `make` targets copy manifests and run remote commands. |
| Git credentials | Flux GitRepository (`flux-system/secret`) needs access to this repo. |

> Update `CONTROL_NODE` and `REMOTE_DIR` in the `Makefile` if your control node
> differs from the defaults.

## Bootstrapping a new cluster

1. **Clone the repository**
   ```bash
   git clone git@github.com:andyrosty/homelab-services.git
   cd homelab-services
   ```
   
   If you are accessing the cluster from a Mac mini (or any machine without
   internal DNS records for your ingress hosts), update your local `/etc/hosts`
   file so that ingress hostnames resolve to the MetalLB IP (adjust the IP and
   hostnames to match your setup):

   ```bash
   sudo vim /etc/hosts
   # Examples:
   192.168.50.240 smoke-test.dev-andrew.com
   192.168.50.240 homepage.dev-andrew.com
   ```

2. **Configure Git credentials for Flux** – on the cluster, create the
   `flux-system` namespace and secret so Flux can read this repository:
   ```bash
   kubectl create namespace flux-system
   flux create secret git flux-system \
     --namespace=flux-system \
     --url=https://github.com/andyrosty/homelab-services.git \
     --username=$GITHUB_USER \
     --password=$GITHUB_TOKEN
   ```
   (Any other `flux create secret git` options such as deploy keys are fine as
   long as the GitRepository in `gotk-sync.yaml` can authenticate.)

3. **Deploy everything** from your local workstation:
   ```bash
   make deploy
   ```
   This target copies the repo to the control node, applies the Kustomize stack,
   and installs Flux, MetalLB, NGINX Ingress, and the smoke-test workload.

4. **Watch Flux reconcile**
   ```bash
   kubectl get pods -n flux-system
   flux reconcile kustomization flux-system --with-source
   ```
   Once reconciliation succeeds, any new commit pushed to `main` will be
   continuously applied to the cluster without re-running `make deploy`.

## Infrastructure components

- **MetalLB (`infrastructure/metallb`)** – installs the upstream manifests and
  advertises the `192.168.50.240-192.168.50.250` pool by default. Adjust the
  address range to match your network before deploying.
- **NGINX Ingress Controller (`infrastructure/nginx-ingress`)** – pulls the
  upstream deployment from the `nginx/kubernetes-ingress` repo and patches the
  service type to `LoadBalancer` so it receives an IP from MetalLB.
- **cert-manager (`infrastructure/cert-manager`)** – deploys cert-manager via a
  Flux `HelmRelease` and provisions a `letsencrypt-cloudflare` ClusterIssuer for
  DNS-01 challenges. Update the email and Cloudflare token secret to match your
  environment.
- **Monitoring stack (`infrastructure/monitoring`)** – installs the
  `kube-prometheus-stack` chart with persistence enabled for Prometheus,
  Alertmanager, and Grafana. Grafana is exposed through the ingress controller
  with TLS certificates issued by cert-manager.
- **Mac NFS volumes (`infrastructure/nfs-storage`)** – defines static
  `PersistentVolume` objects that mount NFS exports from the Mac mini at
  `192.168.50.227`. Edit `persistent-volumes.yaml` if your NAS IP, export paths,
  or desired storage classes differ.

## Applications

### Homepage dashboard (`apps/homepage`)

The `homepage` app is managed via a Flux `HelmRelease` and `HelmRepository`:

- Exposes a web UI at `homepage.dev-andrew.com`.
- Uses the `nginx` ingress controller with a `ClusterIP` service on port `3000`.
- Provides a personalized homelab dashboard with links to infrastructure
  services (Proxmox, OPNsense, smoke-test, etc.).

Update the hostnames, links, and visual settings in
`apps/homepage/helmrelease.yaml` under the `values.config` section to match your
environment.

### Smoke test (`apps/smoke-test`)

`apps/smoke-test` deploys a namespace-scoped nginx Deployment, Service, and an
Ingress rule for `smoke-test.dev-andrew.com`. This is intended purely for
validating that ingress is functional. Update the hostname or extend the
`apps/` directory with additional services following the same Kustomize
pattern.

### Storage test (`apps/storage-test`)

`apps/storage-test` deploys a simple BusyBox pod that continuously writes to a
`PersistentVolumeClaim`. The workload defaults to the `local-path` storage class
and is useful for validating that PersistentVolumes are bound and remain
read/write healthy over time. Point the PVC at a different storage class (for
example the `mac-nfs` PVs) if you want to exercise other backends.

## Makefile shortcuts

| Target | Description |
|--------|-------------|
| `make sync` | rsync-like copy of `apps/` and `clusters/` to the control node. |
| `make deploy` | Sync + `kubectl apply -k clusters/homelab` on the control node. |
| `make status` | Shows nodes, pods, and services from the remote cluster. |
| `make delete` | Removes all resources defined in `clusters/homelab`. |
| `make install-ingress` | One-off helper that installs the upstream NGINX ingress controller (used before Flux managed it). |

## Development workflow

1. Edit manifests locally and commit the changes.
2. Run `kubectl kustomize clusters/homelab` (optional) to validate the rendered
   output.
3. Push to `main` (or whichever branch Flux tracks).
4. Flux reconciles automatically; check progress with
   `flux get kustomizations --watch`.

## Continuous validation

Every push or pull request against `main` triggers the **Validate GitOps
Manifests** GitHub Actions workflow. It enforces a few safety nets before
changes land on the cluster:

- `yamllint` runs across the repository to catch YAML syntax issues early.
- `kustomize build clusters/homelab` renders the full stack to ensure it still
  composes cleanly.
- `kubeconform` validates the rendered manifests against Kubernetes schemas in
  strict mode.
- `trivy config` scans the manifests for HIGH/CRITICAL misconfigurations while
  skipping vendor directories such as `infrastructure/metallb/manifests` and the
  bootstrapped Flux manifests under `clusters/homelab/flux-system`.

Running the same commands locally (see the workflow at
`.github/workflows/validate.yaml`) helps surface failures before pushing.

## Troubleshooting tips

- Ensure the MetalLB address pool is outside of your DHCP scope to avoid IP
  conflicts.
- If Flux cannot clone the repository, re-create the `flux-system` secret with a
  valid PAT or deploy key.
- When testing ingress, confirm that the DNS record for
  `smoke-test.dev-andrew.com` points to the MetalLB-assigned IP.

Happy homelabbing!

