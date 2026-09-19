#!/usr/bin/env bash

set -euo pipefail
umask 077

usage() {
  cat <<'USAGE'
Usage:
  collect-kubernetes-inventory.sh [output-directory]

Collects persistent-volume metadata using read-only Kubernetes API operations.

The default output directory is created under TMPDIR or /tmp. Files beginning
with "private-runtime-" contain environment-specific bindings and must not be
committed to the repository.

This script never requests Kubernetes Secret objects or secret values.
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

for command_name in kubectl jq; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}" >&2
    exit 1
  fi
done

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
output_dir="${1:-${TMPDIR:-/tmp}/homelab-dr-inventory-${timestamp}}"

mkdir -p -- "${output_dir}"
chmod 700 "${output_dir}"

for resource in persistentvolumeclaims persistentvolumes pods; do
  if [[ "$(kubectl auth can-i list "${resource}" --all-namespaces)" != "yes" ]]; then
    echo "Current Kubernetes identity cannot list ${resource}." >&2
    exit 1
  fi
done

public_pvc_file="${output_dir}/public-pvc-summary.tsv"
private_pv_file="${output_dir}/private-runtime-pv-bindings.tsv"
private_pod_file="${output_dir}/private-runtime-pod-pvc-mounts.tsv"
warning_file="${output_dir}/DO_NOT_COMMIT_PRIVATE_RUNTIME_FILES.txt"

printf '%s\n'   "Review every generated file before use."   "Do not commit files beginning with private-runtime-."   "These files contain node names and bound-volume identifiers."   "Move required details into the approved encrypted private inventory."   > "${warning_file}"

printf 'namespace\tpvc\tstorage_class\trequested_capacity\taccess_modes\tstatus\n'   > "${public_pvc_file}"

kubectl get persistentvolumeclaims --all-namespaces -o json |
  jq -r '
    .items[]
    | [
        .metadata.namespace,
        .metadata.name,
        (.spec.storageClassName // "unset"),
        (.spec.resources.requests.storage // "unknown"),
        ((.spec.accessModes // []) | join(",")),
        (.status.phase // "unknown")
      ]
    | @tsv
  ' >> "${public_pvc_file}"

printf 'pv\tclaim_namespace\tclaim_name\tstorage_class\tcapacity\treclaim_policy\tvolume_type\towner_nodes\n'   > "${private_pv_file}"

kubectl get persistentvolumes -o json |
  jq -r '
    .items[]
    | [
        .metadata.name,
        (.spec.claimRef.namespace // "unbound"),
        (.spec.claimRef.name // "unbound"),
        (.spec.storageClassName // "unset"),
        (.spec.capacity.storage // "unknown"),
        (.spec.persistentVolumeReclaimPolicy // "unknown"),
        (
          if .spec.hostPath then "hostPath"
          elif .spec.local then "local"
          elif .spec.nfs then "nfs"
          elif .spec.csi then "csi"
          else "other"
          end
        ),
        (
          [
            .spec.nodeAffinity.required.nodeSelectorTerms[]?
            | .matchExpressions[]?
            | select(.key == "kubernetes.io/hostname")
            | .values[]?
          ]
          | unique
          | join(",")
        )
      ]
    | @tsv
  ' >> "${private_pv_file}"

printf 'namespace\tpod\tnode\tpvc\n' > "${private_pod_file}"

kubectl get pods --all-namespaces -o json |
  jq -r '
    .items[] as $pod
    | $pod.spec.volumes[]?
    | select(.persistentVolumeClaim != null)
    | [
        $pod.metadata.namespace,
        $pod.metadata.name,
        ($pod.spec.nodeName // "unscheduled"),
        .persistentVolumeClaim.claimName
      ]
    | @tsv
  ' >> "${private_pod_file}"

chmod 600   "${public_pvc_file}"   "${private_pv_file}"   "${private_pod_file}"   "${warning_file}"

cat <<RESULT
Inventory collection completed.

Output directory:
  ${output_dir}

Repository-safe starting point:
  ${public_pvc_file}

Private runtime files; do not commit:
  ${private_pv_file}
  ${private_pod_file}

The collector did not request Kubernetes Secret objects.
Review and sanitize all output before moving any information into Git.
RESULT
