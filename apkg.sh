#!/usr/bin/env bash
# apkg - unified package manager frontend
# Supports: apt/apt-get, pacman(+yay), dnf, yum, zypper, apk (Alpine),
#           xbps (Void), emerge (Gentoo)

set -euo pipefail

APKG_VERSION="0.3.0"

# ------------- logging helpers -------------

log()  { printf '[apkg] %s\n' "$*" >&2; }
warn() { printf '[apkg][WARN] %s\n' "$*" >&2; }
die()  { printf '[apkg][ERROR] %s\n' "$*" >&2; exit 1; }

# ------------- sudo handling -------------

SUDO=""

init_sudo() {
  # Allow overriding sudo via env (APKG_SUDO="").
  if [[ "${APKG_SUDO-}" != "" ]]; then
    if [[ "${APKG_SUDO}" == "" ]]; then
      SUDO=""
    else
      if command -v "${APKG_SUDO}" >/dev/null 2>&1; then
        SUDO="${APKG_SUDO}"
      else
        warn "APKG_SUDO='${APKG_SUDO}' not found in PATH."
        if [[ ${EUID} -eq 0 ]]; then
          warn "Running as root – continuing without sudo."
          SUDO=""
        else
          if command -v sudo >/dev/null 2>&1; then
            warn "Falling back to 'sudo'."
            SUDO="sudo"
          elif command -v doas >/dev/null 2>&1; then
            warn "Falling back to 'doas'."
            SUDO="doas"
          else
            die "No working privilege escalation tool (sudo/doas) found and not running as root."
          fi
        fi
      fi
    fi
  else
    # Auto-detect
    if [[ ${EUID} -eq 0 ]]; then
      SUDO=""
    else
      if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
      elif command -v doas >/dev/null 2>&1; then
        warn "'sudo' not found, using 'doas' instead."
        SUDO="doas"
      else
        warn "Neither sudo nor doas found, and not running as root."
        warn "Commands requiring root may fail. Consider installing sudo or doas."
        SUDO=""
      fi
    fi
  fi
}

# ------------- package manager detection -------------

PKG_MGR=""
PKG_MGR_FAMILY=""   # debian, arch, redhat, suse, alpine, void, gentoo

detect_pkg_mgr() {
  if command -v pacman >/dev/null 2>&1; then
    PKG_MGR="pacman"
    PKG_MGR_FAMILY="arch"
  elif command -v apt-get >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
    # force apt-get usage
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
  elif command -v xbps-install >/dev/null 2>&1; then
    PKG_MGR="xbps-install"
    PKG_MGR_FAMILY="void"
  elif command -v emerge >/dev/null 2>&1; then
    PKG_MGR="emerge"
    PKG_MGR_FAMILY="gentoo"
  else
    die "No supported package manager found (pacman/apt-get/dnf/yum/zypper/apk/xbps/emerge)."
  fi
}

ensure_pkg_mgr() {
  if [[ -z "${PKG_MGR}" ]]; then
    detect_pkg_mgr
  fi
}

usage() {
  cat <<EOF
apkg - unified package manager frontend

Usage: apkg <command> [arguments...]

Core commands (mapped per distro):

  apkg update             Update package database
  apkg upgrade            Upgrade installed packages (safe/normal)
  apkg full-upgrade       Full upgrade (dist-upgrade / Syu / world)

  apkg install PKG...     Install one or more packages
  apkg remove PKG...      Remove packages
  apkg purge PKG...       Remove packages + configs (if supported)
  apkg autoremove         Remove unused/orphan dependencies

  apkg search PATTERN     Search packages
  apkg list               List installed packages
  apkg show PKG           Show detailed package info
  apkg clean              Clean cache (if supported)

Repo management (best-effort, distro-dependent):

  apkg repos-list         List configured repositories
  apkg add-repo ARGS...   Add a repository (delegates to distro tools when possible)
  apkg remove-repo PAT    Remove / disable repos matching PATTERN (best-effort)

Dev / troubleshooting:

  apkg install-dev-kit    Install basic development tools (compiler, make, git, etc.)
  apkg fix-dns            Try to fix common DNS issues (backup /etc/resolv.conf, set public DNS)

System helpers (non-package-manager):

  apkg sys-info           Basic system information
  apkg kernel             Show kernel version
  apkg disk               Show disk usage (df -h)
  apkg mem                Show memory usage (free -h)
  apkg top                Run htop if available, else top
  apkg ps                 Top 15 processes by memory
  apkg ip                 Show network info (ip addr/route)

General:

  apkg -v | --version     Show apkg version
  apkg help               Show this help

Environment:

  APKG_SUDO=""            Disable sudo/doas inside apkg (run as root)
  APKG_SUDO="doas"        Use doas instead of sudo, etc.

EOF
}

# ------------- helpers for package errors -------------

print_pkg_not_found_msgs() {
  # $@ = pkgs
  for p in "$@"; do
    printf 'apkg: The Package "%s" Not Found\n' "$p" >&2
  done
}

# ------------- Arch: pacman + yay fallback -------------

install_yay_if_needed() {
  if command -v yay >/dev/null 2>&1; then
    return 0
  fi

  log "Trying to install 'yay' (AUR helper)..."

  # طريقة بسيطة وآمنة نسبياً: لو yay موجود في الريبو الرسمي
  if pacman -Si yay >/dev/null 2>&1; then
    if ! yay_out="$(${SUDO} pacman -S --needed yay 2>&1)"; then
      warn "Failed to install yay via pacman:"
      printf '%s\n' "$yay_out" >&2
      return 1
    fi
    printf '%s\n' "$yay_out"
    return 0
  fi

  warn "'yay' is not available in official repos."
  warn "Automatic AUR bootstrap (git/makepkg) not implemented for safety."
  return 1
}

arch_install_with_yay() {
  local pkgs=("$@")
  local out

  # أولاً جرّب pacman
  if out="$(${SUDO} pacman -S --needed "${pkgs[@]}" 2>&1)"; then
    printf '%s\n' "$out"
    return 0
  fi

  # لو الخطأ أن التارجت مش موجود → جرّب yay
  if grep -qiE 'target not found|could not find|no such package' <<< "$out"; then
    log "Some packages not found in official repos, trying yay (AUR)..."

    if ! install_yay_if_needed; then
      print_pkg_not_found_msgs "${pkgs[@]}"
      return 1
    fi

    if yay_out="$(yay -S --needed "${pkgs[@]}" 2>&1)"; then
      printf '%s\n' "$yay_out"
      return 0
    else
      if grep -qiE 'not found|could not find|no such package' <<< "$yay_out"; then
        print_pkg_not_found_msgs "${pkgs[@]}"
        return 1
      fi
      warn "Error while installing via yay:"
      printf '%s\n' "$yay_out" >&2
      return 1
    fi
  fi

  # أي خطأ آخر من pacman
  warn "Error while installing via pacman:"
  printf '%s\n' "$out" >&2
  return 1
}

# ------------- core package commands -------------

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
    void)
      ${SUDO} xbps-install -S
      ;;
    gentoo)
      ${SUDO} emerge --sync
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
    void)
      ${SUDO} xbps-install -Su
      ;;
    gentoo)
      ${SUDO} emerge -uD @world
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
    void)
      ${SUDO} xbps-install -Su
      ;;
    gentoo)
      ${SUDO} emerge -uD @world
      ;;
  esac
}

cmd_install() {
  ensure_pkg_mgr
  if [[ $# -eq 0 ]]; then
    die "You must specify at least one package to install."
  fi

  case "${PKG_MGR_FAMILY}" in
    arch)
      arch_install_with_yay "$@"
      ;;
    debian)
      if out="$(${SUDO} ${PKG_MGR} install -y "$@" 2>&1)"; then
        printf '%s\n' "$out"
      else
        if grep -qi 'Unable to locate package' <<< "$out"; then
          print_pkg_not_found_msgs "$@"
        else
          warn "Install failed:"
          printf '%s\n' "$out" >&2
        fi
        return 1
      fi
      ;;
    redhat)
      if out="$(${SUDO} ${PKG_MGR} install -y "$@" 2>&1)"; then
        printf '%s\n' "$out"
      else
        if grep -qiE 'No match for argument|Unable to find a match' <<< "$out"; then
          print_pkg_not_found_msgs "$@"
        else
          warn "Install failed:"
          printf '%s\n' "$out" >&2
        fi
        return 1
      fi
      ;;
    suse)
      if out="$(${SUDO} zypper install -y "$@" 2>&1)"; then
        printf '%s\n' "$out"
      else
        if grep -qi 'not found in package names' <<< "$out"; then
          print_pkg_not_found_msgs "$@"
        else
          warn "Install failed:"
          printf '%s\n' "$out" >&2
        fi
        return 1
      fi
      ;;
    alpine)
      if out="$(${SUDO} apk add "$@" 2>&1)"; then
        printf '%s\n' "$out"
      else
        if grep -qi 'not found' <<< "$out"; then
          print_pkg_not_found_msgs "$@"
        else
          warn "Install failed:"
          printf '%s\n' "$out" >&2
        fi
        return 1
      fi
      ;;
    void)
      if out="$(${SUDO} xbps-install -y "$@" 2>&1)"; then
        printf '%s\n' "$out"
      else
        if grep -qi 'not found in repository pool' <<< "$out"; then
          print_pkg_not_found_msgs "$@"
        else
          warn "Install failed:"
          printf '%s\n' "$out" >&2
        fi
        return 1
      fi
      ;;
    gentoo)
      if out="$(${SUDO} emerge "$@" 2>&1)"; then
        printf '%s\n' "$out"
      else
        if grep -qi 'emerge: there are no ebuilds to satisfy' <<< "$out"; then
          print_pkg_not_found_msgs "$@"
        else
          warn "Install failed:"
          printf '%s\n' "$out" >&2
        fi
        return 1
      fi
      ;;
  esac
}

cmd_remove() {
  ensure_pkg_mgr
  if [[ $# -eq 0 ]]; then
    die "You must specify at least one package to remove."
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
    void)
      if command -v xbps-remove >/dev/null 2>&1; then
        ${SUDO} xbps-remove -y "$@"
      else
        die "xbps-remove not found."
      fi
      ;;
    gentoo)
      ${SUDO} emerge -C "$@"
      ;;
  esac
}

cmd_purge() {
  ensure_pkg_mgr
  if [[ $# -eq 0 ]]; then
    die "You must specify at least one package to purge."
  fi
  case "${PKG_MGR_FAMILY}" in
    debian)
      ${SUDO} ${PKG_MGR} purge -y "$@"
      ;;
    arch)
      ${SUDO} pacman -Rns "$@"
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
    void)
      if command -v xbps-remove >/dev/null 2>&1; then
        ${SUDO} xbps-remove -y "$@"
      else
        die "xbps-remove not found."
      fi
      ;;
    gentoo)
      ${SUDO} emerge -C "$@"
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
      local ORPHANS
      ORPHANS=$(pacman -Qdtq 2>/dev/null || true)
      if [[ -n "${ORPHANS}" ]]; then
        log "Removing orphaned packages:"
        printf '%s\n' "${ORPHANS}"
        ${SUDO} pacman -Rns ${ORPHANS}
      else
        log "No orphaned packages found."
      fi
      ;;
    redhat)
      if [[ "${PKG_MGR}" == "dnf" ]]; then
        ${SUDO} dnf autoremove -y
      else
        warn "Autoremove not explicitly supported for ${PKG_MGR}."
      fi
      ;;
    suse)
      warn "Autoremove not explicitly supported for zypper (manual cleanup required)."
      ;;
    alpine)
      warn "Autoremove not explicitly supported for apk."
      ;;
    void|gentoo)
      warn "Autoremove/orphan cleanup not implemented for ${PKG_MGR_FAMILY}."
      ;;
  esac
}

cmd_search() {
  ensure_pkg_mgr
  if [[ $# -eq 0 ]]; then
    die "You must provide a search pattern."
  fi
  case "${PKG_MGR_FAMILY}" in
    debian)
      apt-cache search "$@"
      ;;
    arch)
      # pacman search ثم لو مفيش حاجة ممكن المستخدم يستخدم yay يدويًا
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
    void)
      xbps-query -Rs "$@"
      ;;
    gentoo)
      emerge -s "$@"
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
    void)
      xbps-query -l
      ;;
    gentoo)
      if command -v qlist >/dev/null 2>&1; then
        qlist -I
      else
        warn "qlist not found, cannot list installed packages cleanly."
      fi
      ;;
  esac
}

cmd_show() {
  ensure_pkg_mgr
  if [[ $# -eq 0 ]]; then
    die "You must specify a package name."
  fi
  case "${PKG_MGR_FAMILY}" in
    debian)
      if out="$(apt-cache show "$@" 2>&1)"; then
        printf '%s\n' "$out"
      else
        if grep -qi 'E: No packages found' <<< "$out"; then
          print_pkg_not_found_msgs "$@"
        else
          warn "Show failed:"
          printf '%s\n' "$out" >&2
        fi
        return 1
      fi
      ;;
    arch)
      if out="$(pacman -Si "$@" 2>&1)"; then
        printf '%s\n' "$out"
      else
        if grep -qi 'target not found' <<< "$out"; then
          print_pkg_not_found_msgs "$@"
        else
          warn "Show failed:"
          printf '%s\n' "$out" >&2
        fi
        return 1
      fi
      ;;
    redhat)
      if out="$(${PKG_MGR} info "$@" 2>&1)"; then
        printf '%s\n' "$out"
      else
        if grep -qiE 'No matching Packages to list|Error: No matching Packages' <<< "$out"; then
          print_pkg_not_found_msgs "$@"
        else
          warn "Show failed:"
          printf '%s\n' "$out" >&2
        fi
        return 1
      fi
      ;;
    suse)
      if out="$(zypper info "$@" 2>&1)"; then
        printf '%s\n' "$out"
      else
        if grep -qi 'not found in package names' <<< "$out"; then
          print_pkg_not_found_msgs "$@"
        else
          warn "Show failed:"
          printf '%s\n' "$out" >&2
        fi
        return 1
      fi
      ;;
    alpine)
      if out="$(apk info -a "$@" 2>&1)"; then
        printf '%s\n' "$out"
      else
        if grep -qi 'not found' <<< "$out"; then
          print_pkg_not_found_msgs "$@"
        else
          warn "Show failed:"
          printf '%s\n' "$out" >&2
        fi
        return 1
      fi
      ;;
    void)
      if out="$(xbps-query -RS "$@" 2>&1)"; then
        printf '%s\n' "$out"
      else
        if grep -qi 'not found in repository pool' <<< "$out"; then
          print_pkg_not_found_msgs "$@"
        else
          warn "Show failed:"
          printf '%s\n' "$out" >&2
        fi
        return 1
      fi
      ;;
    gentoo)
      # مفيش أمر موحّد بسيط، نخلي المستخدم يعتمد على equery لو موجود
      if command -v equery >/dev/null 2>&1; then
        equery meta "$@"
      else
        warn "equery not found, show not implemented for Gentoo."
      fi
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
      warn "apk cache cleaning depends on your setup (e.g. /var/cache/apk)."
      ;;
    void)
      if command -v xbps-remove >/dev/null 2>&1; then
        ${SUDO} xbps-remove -O
      else
        warn "xbps-remove not found, cannot clean cache."
      fi
      ;;
    gentoo)
      warn "Clean not implemented for Gentoo (use eclean/distclean tools)."
      ;;
  esac
}

# ------------- repo management commands -------------

cmd_repos_list() {
  ensure_pkg_mgr
  case "${PKG_MGR_FAMILY}" in
    debian)
      echo "=== /etc/apt/sources.list ==="
      [[ -f /etc/apt/sources.list ]] && cat /etc/apt/sources.list || echo "Not found."
      echo
      echo "=== /etc/apt/sources.list.d/*.list ==="
      ls /etc/apt/sources.list.d/*.list 2>/dev/null || echo "No extra list files."
      ;;
    arch)
      echo "=== /etc/pacman.conf (repos sections) ==="
      if [[ -f /etc/pacman.conf ]]; then
        grep -E '^\[.+\]' /etc/pacman.conf || true
      else
        echo "pacman.conf not found."
      fi
      ;;
    redhat)
      echo "=== /etc/yum.repos.d/*.repo ==="
      ls /etc/yum.repos.d/*.repo 2>/dev/null || echo "No repo files found."
      ;;
    suse)
      echo "=== zypper repos ==="
      zypper lr
      ;;
    alpine)
      echo "=== /etc/apk/repositories ==="
      [[ -f /etc/apk/repositories ]] && cat /etc/apk/repositories || echo "Not found."
      ;;
    void)
      echo "=== /etc/xbps.d/*.conf ==="
      ls /etc/xbps.d/*.conf 2>/dev/null || echo "No repo config files."
      ;;
    gentoo)
      echo "Repos are defined in /etc/portage/repos.conf and /etc/portage/make.conf."
      ;;
  esac
}

cmd_add_repo() {
  ensure_pkg_mgr
  if [[ $# -eq 0 ]]; then
    die "Usage: apkg add-repo <repo-spec-or-url>"
  fi
  case "${PKG_MGR_FAMILY}" in
    debian)
      if command -v add-apt-repository >/dev/null 2>&1; then
        ${SUDO} add-apt-repository "$@"
      else
        warn "add-apt-repository not found. You may need to install 'software-properties-common'."
        die "Automatic repo add not supported. Edit /etc/apt/sources.list or /etc/apt/sources.list.d manually."
      fi
      ;;
    arch)
      warn "Automatic repo management for pacman is not supported by apkg."
      warn "Edit /etc/pacman.conf manually and run 'apkg update'."
      ;;
    redhat)
      if command -v dnf >/dev/null 2>&1 && command -v dnf-config-manager >/dev/null 2>&1; then
        ${SUDO} dnf config-manager --add-repo "$1"
      elif command -v yum-config-manager >/dev/null 2>&1; then
        ${SUDO} yum-config-manager --add-repo "$1"
      else
        die "No config manager (dnf-config-manager/yum-config-manager) found. Add repo manually under /etc/yum.repos.d."
      fi
      ;;
    suse)
      if [[ $# -lt 2 ]]; then
        die "Usage (suse): apkg add-repo <url> <alias>"
      fi
      ${SUDO} zypper ar "$1" "$2"
      ;;
    alpine)
      if [[ $# -ne 1 ]]; then
        die "Usage (alpine): apkg add-repo <repo-url-line>"
      fi
      if [[ ! -f /etc/apk/repositories ]]; then
        die "/etc/apk/repositories not found."
      fi
      ${SUDO} sh -c "echo '$1' >> /etc/apk/repositories"
      log "Added repo line to /etc/apk/repositories. Run 'apkg update'."
      ;;
    void|gentoo)
      warn "Repo add not automated for ${PKG_MGR_FAMILY}. Please edit config files manually."
      ;;
  esac
}

cmd_remove_repo() {
  ensure_pkg_mgr
  if [[ $# -eq 0 ]]; then
    die "Usage: apkg remove-repo <pattern>"
  fi
  local pattern="$1"

  case "${PKG_MGR_FAMILY}" in
    debian)
      warn "Will comment out lines matching '${pattern}' in /etc/apt/sources.list*."
      for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
        [[ -f "$f" ]] || continue
        ${SUDO} sed -i.bak "/${pattern}/ s/^/# disabled by apkg: /" "$f" || true
      done
      log "Done. Check *.bak backups if needed. Run 'apkg update'."
      ;;
    arch)
      warn "Automatic repo removal on pacman.conf is not supported."
      warn "Edit /etc/pacman.conf manually."
      ;;
    redhat)
      warn "Automatic repo removal is not fully supported."
      warn "You can disable .repo files under /etc/yum.repos.d/ manually."
      ;;
    suse)
      warn "Use 'zypper rr <alias>' directly for precise control."
      ;;
    alpine)
      if [[ ! -f /etc/apk/repositories ]]; then
        die "/etc/apk/repositories not found."
      fi
      ${SUDO} sed -i.bak "/${pattern}/d" /etc/apk/repositories
      log "Removed lines matching '${pattern}' from /etc/apk/repositories (backup: .bak)."
      ;;
    void|gentoo)
      warn "Repo removal not automated for ${PKG_MGR_FAMILY}; please edit config files manually."
      ;;
  esac
}

# ------------- dev kit -------------

cmd_install_dev_kit() {
  ensure_pkg_mgr
  log "Installing basic development tools (best-effort for ${PKG_MGR_FAMILY})..."
  case "${PKG_MGR_FAMILY}" in
    debian)
      ${SUDO} ${PKG_MGR} update
      ${SUDO} ${PKG_MGR} install -y build-essential git curl wget pkg-config
      ;;
    arch)
      arch_install_with_yay base-devel git curl wget pkgconf
      ;;
    redhat)
      ${SUDO} ${PKG_MGR} groupinstall -y "Development Tools" || true
      ${SUDO} ${PKG_MGR} install -y git curl wget pkgconfig
      ;;
    suse)
      ${SUDO} zypper install -y -t pattern devel_basis || true
      ${SUDO} zypper install -y git curl wget pkg-config
      ;;
    alpine)
      ${SUDO} apk add build-base git curl wget pkgconf
      ;;
    void)
      ${SUDO} xbps-install -y base-devel git curl wget pkg-config || true
      ;;
    gentoo)
      log "On Gentoo, dev tools are usually already present; ensure system profile includes them."
      ;;
  esac
  log "Dev kit installation finished."
}

# ------------- DNS fixer -------------

cmd_fix_dns() {
  log "Attempting to fix DNS issues (best-effort)."

  if [[ -L /etc/resolv.conf ]]; then
    warn "/etc/resolv.conf is a symlink. This usually means systemd-resolved or similar is managing DNS."
    if command -v systemctl >/dev/null 2>&1; then
      warn "Trying to restart systemd-resolved / NetworkManager if present."
      ${SUDO} systemctl restart systemd-resolved 2>/dev/null || true
      ${SUDO} systemctl restart NetworkManager 2>/dev/null || true
    fi
    log "Done basic service restarts. If DNS still broken, check your network manager settings."
    return 0
  fi

  if [[ -f /etc/resolv.conf ]]; then
    local backup="/etc/resolv.conf.apkg-backup-$(date +%Y%m%d%H%M%S)"
    log "Backing up /etc/resolv.conf to ${backup}"
    ${SUDO} cp /etc/resolv.conf "${backup}"
  fi

  log "Writing new /etc/resolv.conf with public DNS servers..."
  ${SUDO} sh -c 'cat > /etc/resolv.conf' <<EOF
# Generated by apkg fix-dns on $(date)
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 9.9.9.9
EOF

  log "New /etc/resolv.conf written. Try 'ping 1.1.1.1' then 'ping google.com' to verify connectivity."
}

# ------------- system helpers -------------

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

# ------------- main dispatch -------------

main() {
  case "${1-}" in
    -v|--version)
      echo "apkg ${APKG_VERSION}"
      exit 0
      ;;
  esac

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

    repos-list)     cmd_repos_list "$@" ;;
    add-repo)       cmd_add_repo "$@" ;;
    remove-repo)    cmd_remove_repo "$@" ;;

    install-dev-kit) cmd_install_dev_kit "$@" ;;
    fix-dns)        cmd_fix_dns "$@" ;;

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
      die "Unknown command: ${cmd}"
      ;;
  esac
}

init_sudo
main "$@"
