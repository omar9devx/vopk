#!/usr/bin/env bash
# apkg - unified package manager frontend
# Supports: apt/apt-get, pacman, dnf, yum, zypper, apk (Alpine)

set -euo pipefail

# Allow overriding sudo via env (APKG_SUDO="").
if [[ ${APKG_SUDO-} != "" ]]; then
  SUDO="${APKG_SUDO}"
else
  if [[ ${EUID} -eq 0 ]]; then
    SUDO=""
  else
    SUDO="sudo"
  fi
fi

PKG_MGR=""
PKG_MGR_FAMILY=""   # debian, arch, redhat, suse, alpine

detect_pkg_mgr() {
  if command -v pacman >/dev/null 2>&1; then
    PKG_MGR="pacman"
    PKG_MGR_FAMILY="arch"
  elif command -v apt-get >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
    PKG_MGR="apt-get"
    PKG_MGR_FAMILY="debian"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
    PKG_MGR_FAMILY="redhat"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MGR="yum"
    PKG_MGR_FAMILY="redhat"
  elif command -v zypper >/dev/null 2>&1; then
    PKG_MGR="zypper"
    PKG_MGR_FAMILY="suse"
  elif command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
    PKG_MGR_FAMILY="alpine"
  else
    echo "Error: no supported package manager found (pacman/apt/dnf/yum/zypper/apk)." >&2
    exit 1
  fi
}

usage() {
  cat <<EOF
apkg - unified package manager frontend

Usage: apkg <command> [arguments...]

Core commands (mapped per distro):

  apkg update             Update package database
  apkg upgrade            Upgrade installed packages (safe/normal)
  apkg full-upgrade       Full upgrade (dist-upgrade / Syu)

  apkg install PKG...     Install one or more packages
  apkg remove PKG...      Remove packages
  apkg purge PKG...       Remove packages + configs (if supported)
  apkg autoremove         Remove unused/orphan dependencies

  apkg search PATTERN     Search packages
  apkg list               List installed packages
  apkg show PKG           Show detailed package info
  apkg clean              Clean cache (if supported)

System helpers (non-package-manager):

  apkg sys-info           Basic system information
  apkg kernel             Show kernel version
  apkg disk               Show disk usage (df -h)
  apkg mem                Show memory usage (free -h)
  apkg top                Run htop if available, else top
  apkg ps                 Top 15 processes by memory
  apkg ip                 Show network info (ip addr/route)

General:

  apkg help               Show this help

Environment:

  APKG_SUDO=""            Disable sudo inside apkg (run as root)
  APKG_SUDO="doas"        Use doas instead of sudo, etc.

EOF
}

ensure_pkg_mgr() {
  if [[ -z "${PKG_MGR}" ]]; then
    detect_pkg_mgr
  fi
}

cmd_update() {
  ensure_pkg_mgr
  case "${PKG_MGR_FAMILY}" in
    debian)
      ${SUDO} ${PKG_MGR} update
      ;;
    arch)
      ${SUDO} pacman -Sy
      ;;
    redhat)
      ${SUDO} ${PKG_MGR} makecache
      ;;
    suse)
      ${SUDO} zypper refresh
      ;;
    alpine)
      ${SUDO} apk update
      ;;
  esac
}

cmd_upgrade() {
  ensure_pkg_mgr
  case "${PKG_MGR_FAMILY}" in
    debian)
      ${SUDO} ${PKG_MGR} upgrade -y
      ;;
    arch)
      ${SUDO} pacman -Su
      ;;
    redhat)
      ${SUDO} ${PKG_MGR} upgrade -y
      ;;
    suse)
      ${SUDO} zypper update -y
      ;;
    alpine)
      ${SUDO} apk upgrade
      ;;
  esac
}

cmd_full_upgrade() {
  ensure_pkg_mgr
  case "${PKG_MGR_FAMILY}" in
    debian)
      ${SUDO} ${PKG_MGR} dist-upgrade -y
      ;;
    arch)
      ${SUDO} pacman -Syu
      ;;
    redhat)
      ${SUDO} ${PKG_MGR} upgrade -y
      ;;
    suse)
      ${SUDO} zypper dist-upgrade -y || ${SUDO} zypper dup -y
      ;;
    alpine)
      ${SUDO} apk update
      ${SUDO} apk upgrade
      ;;
  esac
}

cmd_install() {
  ensure_pkg_mgr
  if [[ $# -eq 0 ]]; then
    echo "Error: you must specify at least one package to install." >&2
    exit 1
  fi
  case "${PKG_MGR_FAMILY}" in
    debian)
      ${SUDO} ${PKG_MGR} install -y "$@"
      ;;
    arch)
      ${SUDO} pacman -S --needed "$@"
      ;;
    redhat)
      ${SUDO} ${PKG_MGR} install -y "$@"
      ;;
    suse)
      ${SUDO} zypper install -y "$@"
      ;;
    alpine)
      ${SUDO} apk add "$@"
      ;;
  esac
}

cmd_remove() {
  ensure_pkg_mgr
  if [[ $# -eq 0 ]]; then
    echo "Error: you must specify at least one package to remove." >&2
    exit 1
  fi
  case "${PKG_MGR_FAMILY}" in
    debian)
      ${SUDO} ${PKG_MGR} remove -y "$@"
      ;;
    arch)
      ${SUDO} pacman -R "$@"
      ;;
    redhat)
      ${SUDO} ${PKG_MGR} remove -y "$@"
      ;;
    suse)
      ${SUDO} zypper remove -y "$@"
      ;;
    alpine)
      ${SUDO} apk del "$@"
      ;;
  esac
}

cmd_purge() {
  ensure_pkg_mgr
  if [[ $# -eq 0 ]]; then
    echo "Error: you must specify at least one package to purge." >&2
    exit 1
  fi
  case "${PKG_MGR_FAMILY}" in
    debian)
      ${SUDO} ${PKG_MGR} purge -y "$@"
      ;;
    arch)
      ${SUDO} pacman -Rns "$@"
      ;;
    redhat)
      # best effort: same as remove
      ${SUDO} ${PKG_MGR} remove -y "$@"
      ;;
    suse)
      ${SUDO} zypper remove -y "$@"
      ;;
    alpine)
      ${SUDO} apk del "$@"
      ;;
  esac
}

cmd_autoremove() {
  ensure_pkg_mgr
  case "${PKG_MGR_FAMILY}" in
    debian)
      ${SUDO} ${PKG_MGR} autoremove -y
      ;;
    arch)
      ORPHANS=$(pacman -Qdtq 2>/dev/null || true)
      if [[ -n "${ORPHANS}" ]]; then
        echo "Removing orphaned packages:"
        echo "${ORPHANS}"
        ${SUDO} pacman -Rns ${ORPHANS}
      else
        echo "No orphaned packages found."
      fi
      ;;
    redhat)
      # dnf has autoremove
      if [[ "${PKG_MGR}" == "dnf" ]]; then
        ${SUDO} dnf autoremove -y
      else
        echo "Autoremove not explicitly supported for ${PKG_MGR}."
      fi
      ;;
    suse)
      echo "Autoremove not explicitly supported for zypper (manual cleanup required)."
      ;;
    alpine)
      echo "Autoremove not explicitly supported for apk."
      ;;
  esac
}

cmd_search() {
  ensure_pkg_mgr
  if [[ $# -eq 0 ]]; then
    echo "Error: you must provide a search pattern." >&2
    exit 1
  fi
  case "${PKG_MGR_FAMILY}" in
    debian)
      apt-cache search "$@"
      ;;
    arch)
      pacman -Ss "$@"
      ;;
    redhat)
      ${PKG_MGR} search "$@"
      ;;
    suse)
      zypper search "$@"
      ;;
    alpine)
      apk search "$@"
      ;;
  esac
}

cmd_list() {
  ensure_pkg_mgr
  case "${PKG_MGR_FAMILY}" in
    debian)
      dpkg -l
      ;;
    arch)
      pacman -Q
      ;;
    redhat)
      ${PKG_MGR} list installed || rpm -qa
      ;;
    suse)
      zypper search --installed-only
      ;;
    alpine)
      apk info
      ;;
  esac
}

cmd_show() {
  ensure_pkg_mgr
  if [[ $# -eq 0 ]]; then
    echo "Error: you must specify a package name." >&2
    exit 1
  fi
  case "${PKG_MGR_FAMILY}" in
    debian)
      apt-cache show "$@"
      ;;
    arch)
      pacman -Si "$@"
      ;;
    redhat)
      ${PKG_MGR} info "$@"
      ;;
    suse)
      zypper info "$@"
      ;;
    alpine)
      apk info -a "$@"
      ;;
  esac
}

cmd_clean() {
  ensure_pkg_mgr
  case "${PKG_MGR_FAMILY}" in
    debian)
      ${SUDO} ${PKG_MGR} clean
      ;;
    arch)
      ${SUDO} pacman -Scc
      ;;
    redhat)
      ${SUDO} ${PKG_MGR} clean all
      ;;
    suse)
      ${SUDO} zypper clean --all
      ;;
    alpine)
      echo "apk cache cleaning depends on your setup (e.g. /var/cache/apk)."
      ;;
  esac
}

# -------- system helpers (non package-manager) --------

cmd_sys_info() {
  echo "=== System info ==="
  uname -a || true
  echo
  echo "=== CPU ==="
  grep -m1 'model name' /proc/cpuinfo 2>/dev/null || echo "CPU info unavailable"
  echo
  echo "=== Memory ==="
  free -h 2>/dev/null || echo "free not available"
  echo
  echo "=== Disk (/) ==="
  df -h / || df -h || true
}

cmd_kernel() {
  uname -a
}

cmd_disk() {
  df -h
}

cmd_mem() {
  free -h || echo "free not available"
}

cmd_top() {
  if command -v htop >/dev/null 2>&1; then
    htop
  else
    top
  fi
}

cmd_ps() {
  ps aux --sort=-%mem | head -n 15
}

cmd_ip() {
  if command -v ip >/dev/null 2>&1; then
    ip addr
    echo
    ip route || true
  else
    echo "'ip' command not found. Install iproute2 or equivalent."
  fi
}

# -------- main dispatch --------

main() {
  local cmd="${1:-}"
  shift || true

  case "${cmd}" in
    update)         cmd_update "$@" ;;
    upgrade)        cmd_upgrade "$@" ;;
    full-upgrade)   cmd_full_upgrade "$@" ;;
    dist-upgrade)   cmd_full_upgrade "$@" ;;

    install)        cmd_install "$@" ;;
    remove)         cmd_remove "$@" ;;
    purge)          cmd_purge "$@" ;;
    autoremove)     cmd_autoremove "$@" ;;

    search)         cmd_search "$@" ;;
    list)           cmd_list "$@" ;;
    show)           cmd_show "$@" ;;
    clean)          cmd_clean "$@" ;;

    sys-info)       cmd_sys_info ;;
    kernel)         cmd_kernel ;;
    disk)           cmd_disk ;;
    mem)            cmd_mem ;;
    top)            cmd_top ;;
    ps)             cmd_ps ;;
    ip)             cmd_ip ;;

    ""|help|-h|--help)
      usage
      ;;
    *)
      echo "Unknown command: ${cmd}" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
