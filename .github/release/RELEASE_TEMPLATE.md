# Homelab Services Release

## Release
- Version:
- Git commit:
- Release date:
- Released by:

## Included platform capabilities
- Flux GitOps
- MetalLB
- ingress-nginx
- cert-manager with Cloudflare DNS-01
- Homepage
- Prometheus and Grafana
- Persistent storage validation
- CI validation pipeline

## Validation evidence
- YAML lint:
- Kustomize build:
- Kubernetes schema validation:
- Trivy configuration scan:
- Rendered manifest artifact:
- Nexus release bundle:

## Known exceptions / accepted risks
- 

## Rollback
Revert the faulty commit on `main`, push the revert, and let Flux reconcile the corrected desired state.
