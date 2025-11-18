#!/usr/bin/env bash
# APKG Maintenance Script - GP Team
# Performs update / reinstall / repair / delete for APKG binary.

set -euo pipefail

APKG_URL="https://raw.githubusercontent.com/gpteamofficial/apkg/main/apkg.sh"
APKG_DEST="/bin/apkg"
APKG_BAK="/bin/apkg.bak"

# ------------------ helpers ------------------

log() {
  printf '[apkg-maint] %s\n' "$*" >&2
}

fail() {
  printf '[apkg-maint][ERROR] %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    fail "This script must be run as root. Try: sudo $0 $*"
  fi
}

detect_pkg_mgr() {
  if command -v pacman >/dev/null 2>&1; then
    PKG_MGR="pacman"
    PKG_FAMILY="arch"
  elif command -v apt-get >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
    PKG_MGR="apt-get"
    PKG_FAMILY="debian"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
    PKG_FAMILY="redhat"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MGR="yum"
    PKG_FAMILY="redhat"
  elif command -v zypper >/dev/null 2>&1; then
    PKG_MGR="zypper"
    PKG_FAMILY="suse"
  elif command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
    PKG_FAMILY="alpine"
  else
    PKG_MGR=""
    PKG_FAMILY=""
  fi
}

install_curl_if_needed() {
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    return 0
  fi

  detect_pkg_mgr

  if [ -z "${PKG_MGR}" ]; then
    fail "No supported package manager found to install curl (pacman/apt/dnf/yum/zypper/apk). Install curl or wget manually and rerun."
  fi

  log "Neither curl nor wget found. Installing curl using ${PKG_MGR}..."

  case "${PKG_FAMILY}" in
    debian)
      ${PKG_MGR} update -y || ${PKG_MGR} update || true
      ${PKG_MGR} install -y curl
      ;;
    arch)
      pacman -Sy --noconfirm curl
      ;;
    redhat)
      ${PKG_MGR} install -y curl
      ;;
    suse)
      zypper refresh || true
      zypper install -y curl
      ;;
    alpine)
      apk update || true
      apk add curl
      ;;
    *)
      fail "Unsupported package manager family '${PKG_FAMILY}' for installing curl."
      ;;
  esac

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    fail "Failed to install curl. Please install curl or wget manually, then rerun."
  fi
}

download_apkg() {
  tmpfile="$(mktemp /tmp/apkg.XXXXXX.sh)"

  if command -v curl >/dev/null 2>&1; then
    log "Downloading APKG using curl..."
    curl -fsSL "${APKG_URL}" -o "${tmpfile}"
  elif command -v wget >/dev/null 2>&1; then
    log "Downloading APKG using wget..."
    wget -qO "${tmpfile}" "${APKG_URL}"
  else
    fail "Neither curl nor wget available after installation step. Aborting."
  fi

  if [ ! -s "${tmpfile}" ]; then
    rm -f "${tmpfile}"
    fail "Downloaded file is empty. Check network or APKG_URL."
  fi

  echo "${tmpfile}"
}

install_apkg() {
  local src="$1"

  log "Installing APKG to ${APKG_DEST} ..."
  mkdir -p "$(dirname "${APKG_DEST}")"

  # backup old if exists
  if [ -f "${APKG_DEST}" ]; then
    log "Backing up existing APKG to ${APKG_BAK}"
    cp -f "${APKG_DEST}" "${APKG_BAK}" || true
  fi

  mv "${src}" "${APKG_DEST}"
  chmod 0755 "${APKG_DEST}"

  log "APKG installed successfully at: ${APKG_DEST}"
}

# ------------------ operations ------------------

op_update() {
  if [ ! -f "${APKG_DEST}" ]; then
    log "APKG not found at ${APKG_DEST}. Performing fresh install instead of update."
  else
    log "Updating existing APKG at ${APKG_DEST} ..."
  fi

  install_curl_if_needed
  tmpfile="$(download_apkg)"
  install_apkg "${tmpfile}"

  log "Update completed."
}

op_reinstall() {
  log "Reinstalling APKG ..."

  if [ -f "${APKG_DEST}" ]; then
    log "Removing existing APKG at ${APKG_DEST}"
    rm -f "${APKG_DEST}"
  fi

  install_curl_if_needed
  tmpfile="$(download_apkg)"
  install_apkg "${tmpfile}"

  log "Reinstall completed."
}

op_repair() {
  log "Repairing APKG installation ..."

  install_curl_if_needed

  local needs_fix=0

  if [ ! -f "${APKG_DEST}" ]; then
    log "APKG binary missing."
    needs_fix=1
  elif [ ! -s "${APKG_DEST}" ]; then
    log "APKG binary is empty."
    needs_fix=1
  elif [ ! -x "${APKG_DEST}" ]; then
    log "APKG binary is not executable. Fixing permissions..."
    chmod 0755 "${APKG_DEST}" || needs_fix=1
  fi

  # optional: simple integrity check (is it a shell script?)
  if [ -f "${APKG_DEST}" ] && ! head -n1 "${APKG_DEST}" | grep -q "bash"; then
    log "APKG binary does not look like a shell script. Replacing..."
    needs_fix=1
  fi

  if [ "${needs_fix}" -eq 1 ]; then
    log "Re-downloading APKG to repair installation..."
    tmpfile="$(download_apkg)"
    install_apkg "${tmpfile}"
  else
    log "APKG binary looks fine. No reinstall needed."
  fi

  log "Repair step finished."
}

op_delete() {
  log "Deleting APKG ..."

  if [ -f "${APKG_DEST}" ]; then
    rm -f "${APKG_DEST}"
    log "Removed ${APKG_DEST}"
  else
    log "APKG not found at ${APKG_DEST}. Nothing to delete."
  fi

  # keep backup if exists; user can delete manually
  if [ -f "${APKG_BAK}" ]; then
    log "Backup still present at ${APKG_BAK} (not removed)."
  fi

  log "Delete operation completed."
}

print_usage() {
  cat <<EOF
APKG Maintenance Script

Usage:
  $0 update      - Download and update APKG binary (or install if missing)
  $0 reinstall   - Remove existing APKG and reinstall from scratch
  $0 repair      - Try to repair APKG (re-download if corrupted/missing)
  $0 delete      - Remove APKG binary from the system
  $0 help        - Show this help

Note: Must be run as root (use sudo).
EOF
}

# ------------------ main ------------------

main() {
  if [ "$#" -lt 1 ]; then
    print_usage
    exit 1
  fi

  local cmd="$1"
  shift || true

  case "${cmd}" in
    update)
      require_root
      op_update
      ;;
    reinstall)
      require_root
      op_reinstall
      ;;
    repair)
      require_root
      op_repair
      ;;
    delete|remove|uninstall)
      require_root
      op_delete
      ;;
    help|-h|--help)
      print_usage
      ;;
    *)
      fail "Unknown command '${cmd}'. Use: update | reinstall | repair | delete | help"
      ;;
  esac
}

main "$@"
