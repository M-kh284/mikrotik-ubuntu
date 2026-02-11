#!/usr/bin/env bash
set -euo pipefail

# Bare-metal MikroTik CHR installer for Ubuntu live/rescue environments.
# WARNING: This script will overwrite the target disk and remove Ubuntu.

CHR_VERSION="7.16.2"
TARGET_DISK=""
TEMP_DIR="/tmp/mikrotik-install"
FORCE=false
REBOOT_AFTER_INSTALL=false

usage() {
  cat <<USAGE
Usage: sudo $0 --target-disk /dev/sdX [options]

This script installs MikroTik CHR directly on a server disk.
Ubuntu and all data on the target disk will be destroyed.

Required:
  --target-disk DISK      Target block device (example: /dev/sda, /dev/nvme0n1)

Options:
  --chr-version VERSION   MikroTik CHR version (default: ${CHR_VERSION})
  --temp-dir PATH         Temporary working directory (default: ${TEMP_DIR})
  --force                 Skip final interactive confirmation
  --reboot                Reboot automatically after successful install
  -h, --help              Show this help

Example:
  sudo $0 --target-disk /dev/sda --chr-version 7.16.2 --reboot
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
      --target-disk)
        TARGET_DISK="$2"; shift 2 ;;
      --chr-version)
        CHR_VERSION="$2"; shift 2 ;;
      --temp-dir)
        TEMP_DIR="$2"; shift 2 ;;
      --force)
        FORCE=true; shift ;;
      --reboot)
        REBOOT_AFTER_INSTALL=true; shift ;;
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
  if [[ -z "${TARGET_DISK}" ]]; then
    echo "[ERROR] --target-disk is required." >&2
    usage
    exit 1
  fi

  if [[ ! -b "${TARGET_DISK}" ]]; then
    echo "[ERROR] Target '${TARGET_DISK}' is not a valid block device." >&2
    exit 1
  fi

  if mount | grep -q "^${TARGET_DISK}"; then
    echo "[ERROR] Target disk '${TARGET_DISK}' appears to be mounted. Unmount it first." >&2
    exit 1
  fi

  # Ensure none of the target partitions are mounted
  while IFS= read -r part; do
    if mount | awk '{print $1}' | grep -qx "${part}"; then
      echo "[ERROR] Partition '${part}' is mounted. Unmount all partitions of ${TARGET_DISK} first." >&2
      exit 1
    fi
  done < <(lsblk -ln -o NAME "${TARGET_DISK}" | tail -n +2 | sed 's#^#/dev/#')
}

confirm_destruction() {
  echo
  echo "[WARNING] You are about to install MikroTik CHR on: ${TARGET_DISK}"
  lsblk "${TARGET_DISK}" || true
  echo "[WARNING] ALL DATA on ${TARGET_DISK} will be permanently deleted."

  if [[ "${FORCE}" == "true" ]]; then
    echo "[INFO] --force supplied, skipping interactive confirmation."
    return
  fi

  read -r -p "Type 'ERASE' to continue: " answer
  if [[ "${answer}" != "ERASE" ]]; then
    echo "[INFO] Installation canceled by user."
    exit 1
  fi
}

install_dependencies() {
  echo "[INFO] Installing required tools..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y curl unzip coreutils util-linux
}

download_and_extract_chr() {
  local zip_url="https://download.mikrotik.com/routeros/${CHR_VERSION}/chr-${CHR_VERSION}.img.zip"
  local zip_path="${TEMP_DIR}/chr-${CHR_VERSION}.img.zip"
  local img_path="${TEMP_DIR}/chr-${CHR_VERSION}.img"

  mkdir -p "${TEMP_DIR}"

  echo "[INFO] Downloading CHR image: ${zip_url}"
  curl -fL "${zip_url}" -o "${zip_path}"

  echo "[INFO] Extracting CHR image..."
  unzip -o "${zip_path}" -d "${TEMP_DIR}"

  if [[ ! -f "${img_path}" ]]; then
    echo "[ERROR] Expected image '${img_path}' not found after extraction." >&2
    exit 1
  fi
}

wipe_signatures() {
  echo "[INFO] Removing old filesystem signatures from ${TARGET_DISK}..."
  wipefs -a "${TARGET_DISK}"
}

write_image_to_disk() {
  local img_path="${TEMP_DIR}/chr-${CHR_VERSION}.img"

  echo "[INFO] Writing CHR image to ${TARGET_DISK} (this may take a few minutes)..."
  dd if="${img_path}" of="${TARGET_DISK}" bs=4M conv=fsync status=progress
  sync

  echo "[INFO] Installation image written successfully."
}

cleanup() {
  echo "[INFO] Cleaning temporary files..."
  rm -rf "${TEMP_DIR}"
}

show_next_steps() {
  echo
  echo "[DONE] MikroTik CHR was installed on ${TARGET_DISK}."
  echo "[DONE] Remove Ubuntu boot media/rescue ISO before reboot."
  echo "[DONE] Default login: user=admin password=(empty)"

  if [[ "${REBOOT_AFTER_INSTALL}" == "true" ]]; then
    echo "[INFO] Rebooting system in 5 seconds..."
    sleep 5
    reboot
  else
    echo "[INFO] Reboot manually when ready."
  fi
}

main() {
  require_root
  parse_args "$@"
  validate_inputs
  confirm_destruction
  install_dependencies
  download_and_extract_chr
  wipe_signatures
  write_image_to_disk
  cleanup
  show_next_steps
}

main "$@"
