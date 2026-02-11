#!/usr/bin/env bash
set -euo pipefail

# MikroTik CHR installer for Ubuntu servers.
# This script installs virtualization dependencies, downloads a CHR image,
# converts it to qcow2 and creates a VM with virt-install.

VM_NAME="mikrotik-chr"
RAM_MB=512
VCPUS=1
DISK_SIZE_GB=2
BRIDGE_IFACE=""
CHR_VERSION="7.16.2"
WORKDIR="/var/lib/libvirt/images"
AUTO_START=true

usage() {
  cat <<USAGE
Usage: sudo $0 [options]

Options:
  --vm-name NAME          Virtual machine name (default: ${VM_NAME})
  --ram MB                RAM in MB (default: ${RAM_MB})
  --vcpus N               Number of vCPUs (default: ${VCPUS})
  --disk-size GB          VM disk size in GB after conversion (default: ${DISK_SIZE_GB})
  --bridge IFACE          Linux bridge interface name (required for bridged networking)
  --chr-version VERSION   MikroTik CHR version (default: ${CHR_VERSION})
  --workdir PATH          Working directory for image files (default: ${WORKDIR})
  --no-autostart          Do not enable VM autostart
  -h, --help              Show this help

Example:
  sudo $0 --bridge br0 --vm-name chr-office --ram 1024 --vcpus 2
USAGE
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "[ERROR] This script must be run as root (use sudo)." >&2
    exit 1
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --vm-name)
        VM_NAME="$2"; shift 2 ;;
      --ram)
        RAM_MB="$2"; shift 2 ;;
      --vcpus)
        VCPUS="$2"; shift 2 ;;
      --disk-size)
        DISK_SIZE_GB="$2"; shift 2 ;;
      --bridge)
        BRIDGE_IFACE="$2"; shift 2 ;;
      --chr-version)
        CHR_VERSION="$2"; shift 2 ;;
      --workdir)
        WORKDIR="$2"; shift 2 ;;
      --no-autostart)
        AUTO_START=false; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        echo "[ERROR] Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

validate_inputs() {
  if [[ -z "${BRIDGE_IFACE}" ]]; then
    echo "[ERROR] --bridge is required. Example: --bridge br0" >&2
    exit 1
  fi

  if ! ip link show "${BRIDGE_IFACE}" >/dev/null 2>&1; then
    echo "[ERROR] Bridge interface '${BRIDGE_IFACE}' was not found." >&2
    exit 1
  fi

  if ! [[ "${RAM_MB}" =~ ^[0-9]+$ && "${RAM_MB}" -ge 256 ]]; then
    echo "[ERROR] --ram must be a number >= 256." >&2
    exit 1
  fi

  if ! [[ "${VCPUS}" =~ ^[0-9]+$ && "${VCPUS}" -ge 1 ]]; then
    echo "[ERROR] --vcpus must be a number >= 1." >&2
    exit 1
  fi

  if ! [[ "${DISK_SIZE_GB}" =~ ^[0-9]+$ && "${DISK_SIZE_GB}" -ge 1 ]]; then
    echo "[ERROR] --disk-size must be a number >= 1." >&2
    exit 1
  fi
}

install_dependencies() {
  echo "[INFO] Installing dependencies..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst bridge-utils curl unzip
  systemctl enable --now libvirtd
}

download_chr_image() {
  local zip_url="https://download.mikrotik.com/routeros/${CHR_VERSION}/chr-${CHR_VERSION}.img.zip"
  local zip_path="${WORKDIR}/chr-${CHR_VERSION}.img.zip"
  local raw_img="${WORKDIR}/chr-${CHR_VERSION}.img"
  local qcow2_img="${WORKDIR}/${VM_NAME}.qcow2"

  mkdir -p "${WORKDIR}"

  echo "[INFO] Downloading CHR image: ${zip_url}"
  curl -fL "${zip_url}" -o "${zip_path}"

  echo "[INFO] Extracting image..."
  unzip -o "${zip_path}" -d "${WORKDIR}"

  if [[ ! -f "${raw_img}" ]]; then
    echo "[ERROR] Expected image '${raw_img}' not found after unzip." >&2
    exit 1
  fi

  echo "[INFO] Converting image to qcow2: ${qcow2_img}"
  qemu-img convert -f raw -O qcow2 "${raw_img}" "${qcow2_img}"

  echo "[INFO] Resizing disk to ${DISK_SIZE_GB}G"
  qemu-img resize "${qcow2_img}" "${DISK_SIZE_GB}G"

  rm -f "${zip_path}" "${raw_img}"
}

ensure_vm_not_exists() {
  if virsh dominfo "${VM_NAME}" >/dev/null 2>&1; then
    echo "[ERROR] VM '${VM_NAME}' already exists. Use another --vm-name or remove old VM first." >&2
    exit 1
  fi
}

create_vm() {
  local qcow2_img="${WORKDIR}/${VM_NAME}.qcow2"

  echo "[INFO] Creating VM '${VM_NAME}'..."
  virt-install \
    --name "${VM_NAME}" \
    --memory "${RAM_MB}" \
    --vcpus "${VCPUS}" \
    --cpu host \
    --import \
    --disk "path=${qcow2_img},format=qcow2,bus=virtio" \
    --network "bridge=${BRIDGE_IFACE},model=virtio" \
    --graphics none \
    --noautoconsole

  if [[ "${AUTO_START}" == "true" ]]; then
    virsh autostart "${VM_NAME}"
  fi

  echo "[INFO] VM '${VM_NAME}' created successfully."
  echo "[INFO] First login -> user: admin, password: (empty)"
  echo "[INFO] Use this command to open serial console: virsh console ${VM_NAME}"
}

main() {
  require_root
  parse_args "$@"
  validate_inputs
  install_dependencies
  ensure_vm_not_exists
  download_chr_image
  create_vm
}

main "$@"
