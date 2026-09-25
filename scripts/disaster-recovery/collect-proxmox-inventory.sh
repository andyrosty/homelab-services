#!/usr/bin/env bash

set -euo pipefail
umask 077

usage() {
  cat <<'USAGE'
Usage:
  PROXMOX_API_URL="https://proxmox.example:8006" \
  PROXMOX_TOKEN_ID="dr-inventory@pve!collector" \
    collect-proxmox-inventory.sh [output-directory]

Collects read-only Proxmox inventory through the HTTPS API. The token secret is
prompted for interactively unless PROXMOX_TOKEN_SECRET is already set. Prefer
the prompt so the secret is not saved in shell history or a plaintext file.

Set PROXMOX_CACERT to a local CA certificate when the Proxmox certificate is not
trusted by the workstation. This script deliberately provides no insecure TLS
mode.

The default output directory is created locally under TMPDIR or /tmp. Files
beginning with "private-runtime-" contain environment-specific details and
must not be committed to the repository.
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

for command_name in curl jq; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required local command not found: ${command_name}" >&2
    exit 1
  fi
done

: "${PROXMOX_API_URL:?Set PROXMOX_API_URL to the Proxmox HTTPS endpoint}"
: "${PROXMOX_TOKEN_ID:?Set PROXMOX_TOKEN_ID to the full user and token ID}"

if [[ -z "${PROXMOX_TOKEN_SECRET:-}" ]]; then
  if [[ ! -t 0 ]]; then
    echo "PROXMOX_TOKEN_SECRET is unset and no interactive terminal is available." >&2
    exit 1
  fi

  read -r -s -p "Proxmox token secret: " PROXMOX_TOKEN_SECRET
  printf '\n'
fi

if [[ -z "${PROXMOX_TOKEN_SECRET}" ]]; then
  echo "The Proxmox token secret cannot be empty." >&2
  exit 1
fi

api_base="${PROXMOX_API_URL%/}"
if [[ "${api_base}" != */api2/json ]]; then
  api_base="${api_base}/api2/json"
fi

curl_options=(
  --fail
  --silent
  --show-error
  --connect-timeout 5
  --max-time 30
)

if [[ -n "${PROXMOX_CACERT:-}" ]]; then
  if [[ ! -r "${PROXMOX_CACERT}" ]]; then
    echo "PROXMOX_CACERT is not readable: ${PROXMOX_CACERT}" >&2
    exit 1
  fi
  curl_options+=(--cacert "${PROXMOX_CACERT}")
fi

api_get() {
  local api_path="$1"

  # Supplying the authorization header through stdin keeps the token secret out
  # of the curl process command line and the shell history.
  printf 'header = "Authorization: PVEAPIToken=%s=%s"\n' \
    "${PROXMOX_TOKEN_ID}" "${PROXMOX_TOKEN_SECRET}" |
    curl "${curl_options[@]}" --config - "${api_base}${api_path}"
}

if ! version_json="$(api_get /version)"; then
  cat >&2 <<ERROR
Cannot query the Proxmox API.

API endpoint: ${api_base}
Token ID: ${PROXMOX_TOKEN_ID}

Verify the endpoint, token permissions, network access, and TLS trust. If the
server uses a private CA, set PROXMOX_CACERT to a trusted local CA certificate.
The collector does not support disabling TLS verification.

No inventory files were created.
ERROR
  exit 1
fi

for api_response in "${version_json}"; do
  if ! jq -e '.data != null' >/dev/null 2>&1 <<<"${api_response}"; then
    echo "The Proxmox API returned an unexpected response." >&2
    exit 1
  fi
done

nodes_json="$(api_get /nodes)"
cluster_json="$(api_get /cluster/status)"
guests_json="$(api_get '/cluster/resources?type=vm')"
storage_json="$(api_get '/cluster/resources?type=storage')"
backup_json="$(api_get /cluster/backup)"

for api_response in \
  "${nodes_json}" \
  "${cluster_json}" \
  "${guests_json}" \
  "${storage_json}" \
  "${backup_json}"; do
  if ! jq -e '.data | type == "array"' >/dev/null 2>&1 <<<"${api_response}"; then
    echo "The Proxmox API returned an unexpected collection response." >&2
    exit 1
  fi
done

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
output_dir="${1:-${TMPDIR:-/tmp}/homelab-dr-inventory-${timestamp}}"
mkdir -p -- "${output_dir}"
chmod 700 "${output_dir}"

public_summary_file="${output_dir}/public-proxmox-summary.tsv"
private_cluster_file="${output_dir}/private-runtime-proxmox-cluster.tsv"
private_nodes_file="${output_dir}/private-runtime-proxmox-nodes.tsv"
private_guests_file="${output_dir}/private-runtime-proxmox-guests.tsv"
private_storage_file="${output_dir}/private-runtime-proxmox-storage.tsv"
private_backup_file="${output_dir}/private-runtime-proxmox-backup-jobs.tsv"
warning_file="${output_dir}/DO_NOT_COMMIT_PRIVATE_RUNTIME_FILES.txt"

printf '%s\n' \
  "Review every generated file before use." \
  "Do not commit files beginning with private-runtime-." \
  "These files contain host, guest, storage, and backup identifiers." \
  "Move required details into the approved encrypted private inventory." \
  > "${warning_file}"

version="$(jq -r '.data.version // "unknown"' <<<"${version_json}")"
release="$(jq -r '.data.release // "unknown"' <<<"${version_json}")"
node_total="$(jq '[.data[]] | length' <<<"${nodes_json}")"
node_online="$(jq '[.data[] | select(.status == "online")] | length' <<<"${nodes_json}")"
guest_total="$(jq '[.data[]] | length' <<<"${guests_json}")"
qemu_total="$(jq '[.data[] | select(.type == "qemu")] | length' <<<"${guests_json}")"
lxc_total="$(jq '[.data[] | select(.type == "lxc")] | length' <<<"${guests_json}")"
guest_running="$(jq '[.data[] | select(.status == "running")] | length' <<<"${guests_json}")"
guest_stopped="$(jq '[.data[] | select(.status == "stopped")] | length' <<<"${guests_json}")"
storage_total="$(jq '[.data[]] | length' <<<"${storage_json}")"
backup_total="$(jq '[.data[]] | length' <<<"${backup_json}")"
backup_enabled="$(jq '[.data[] | select((.enabled // 1) == 1)] | length' <<<"${backup_json}")"

printf 'metric\tvalue\n' > "${public_summary_file}"
printf '%s\t%s\n' \
  "proxmox_version" "${version}" \
  "proxmox_release" "${release}" \
  "nodes_total" "${node_total}" \
  "nodes_online" "${node_online}" \
  "nodes_offline" "$((node_total - node_online))" \
  "guests_total" "${guest_total}" \
  "qemu_guests" "${qemu_total}" \
  "lxc_guests" "${lxc_total}" \
  "guests_running" "${guest_running}" \
  "guests_stopped" "${guest_stopped}" \
  "storage_records" "${storage_total}" \
  "backup_jobs_total" "${backup_total}" \
  "backup_jobs_enabled" "${backup_enabled}" \
  >> "${public_summary_file}"

printf 'type\tname\tlocal\tnode_id\tnodes\tquorate\tversion\n' \
  > "${private_cluster_file}"
jq -r '
  .data[]
  | [
      (.type // "unknown"),
      (.name // "unknown"),
      (.local // ""),
      (.nodeid // ""),
      (.nodes // ""),
      (.quorate // ""),
      (.version // "")
    ]
  | @tsv
' <<<"${cluster_json}" >> "${private_cluster_file}"

printf 'node\tstatus\tcpu\tmax_cpu\tmemory_bytes\tmax_memory_bytes\tdisk_bytes\tmax_disk_bytes\tuptime_seconds\n' \
  > "${private_nodes_file}"
jq -r '
  .data[]
  | [
      (.node // "unknown"),
      (.status // "unknown"),
      (.cpu // 0),
      (.maxcpu // 0),
      (.mem // 0),
      (.maxmem // 0),
      (.disk // 0),
      (.maxdisk // 0),
      (.uptime // 0)
    ]
  | @tsv
' <<<"${nodes_json}" >> "${private_nodes_file}"

printf 'vmid\ttype\tname\tnode\tstatus\tpool\tmax_cpu\tmemory_bytes\tmax_memory_bytes\tdisk_bytes\tmax_disk_bytes\ttemplate\ttags\n' \
  > "${private_guests_file}"
jq -r '
  .data[]
  | [
      (.vmid // "unknown"),
      (.type // "unknown"),
      (.name // "unknown"),
      (.node // "unknown"),
      (.status // "unknown"),
      (.pool // ""),
      (.maxcpu // 0),
      (.mem // 0),
      (.maxmem // 0),
      (.disk // 0),
      (.maxdisk // 0),
      (.template // 0),
      (.tags // "")
    ]
  | @tsv
' <<<"${guests_json}" >> "${private_guests_file}"

printf 'storage\tnode\tstorage_type\tstatus\tcontent\tused_bytes\tcapacity_bytes\n' \
  > "${private_storage_file}"
jq -r '
  .data[]
  | [
      (.storage // "unknown"),
      (.node // "unknown"),
      (.plugintype // .storage_type // "unknown"),
      (.status // "unknown"),
      (.content // ""),
      (.disk // 0),
      (.maxdisk // 0)
    ]
  | @tsv
' <<<"${storage_json}" >> "${private_storage_file}"

printf 'job_id\tenabled\tschedule\tnode\tstorage\tmode\tall_guests\tvmids\texcluded_vmids\tpool\n' \
  > "${private_backup_file}"
jq -r '
  .data[]
  | [
      (.id // "unknown"),
      (.enabled // 1),
      (.schedule // "unknown"),
      (.node // "all"),
      (.storage // "unknown"),
      (.mode // "unknown"),
      (.all // 0),
      (.vmid // ""),
      (.exclude // ""),
      (.pool // "")
    ]
  | @tsv
' <<<"${backup_json}" >> "${private_backup_file}"

chmod 600 \
  "${public_summary_file}" \
  "${private_cluster_file}" \
  "${private_nodes_file}" \
  "${private_guests_file}" \
  "${private_storage_file}" \
  "${private_backup_file}" \
  "${warning_file}"

unset PROXMOX_TOKEN_SECRET

cat <<RESULT
Proxmox inventory collection completed.

Output directory:
  ${output_dir}

Repository-safe starting point:
  ${public_summary_file}

Private runtime files; do not commit:
  ${private_cluster_file}
  ${private_nodes_file}
  ${private_guests_file}
  ${private_storage_file}
  ${private_backup_file}

All API requests were read-only and all files were created locally. No files
were copied to or written on Proxmox. Review and sanitize all output before
moving any information into Git.
RESULT
