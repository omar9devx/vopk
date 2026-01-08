#!/usr/bin/env sh
# VOPK Installer + Maintenance - Omar9DevX
# - Polite confirmation before doing anything (unless -y)
# - On Arch: temporary 'aurbuild' user to install yay, then cleanup
# - Colored output via printf
# - POSIX sh compatible
#
# Designed to work reliably even when piped, e.g.:
#   curl -fsSL ... | sh
#   curl -fsSL ... | sudo sh -s -- -y
#
# If not running as root, it will try to re-run itself as:
#   sudo bash <(curl -fsSL ...)

set -eu

VOPK_URL="https://raw.githubusercontent.com/omar9devx/vopk/main/bin/vopk"
VOPK_DEST="/usr/local/bin/vopk"
VOPK_BAK="/usr/local/bin/vopk.bak"

VOPK_UPDATE_SCRIPT_URL="https://raw.githubusercontent.com/vopkteam/vopk/main/src/updatescript.sh"

PKG_MGR=""
PKG_FAMILY=""
AUR_USER_CREATED=0
AUTO_YES=0
CMD=""

# ------------------ colors (TTY-safe) ------------------

if [ -t 2 ] && [ "${NO_COLOR:-0}" = "0" ]; then
  C_RESET="$(printf '\033[0m')"
  C_INFO="$(printf '\033[1;34m')"
  C_WARN="$(printf '\033[1;33m')"
  C_ERR="$(printf '\033[1;31m')"
  C_OK="$(printf '\033[1;32m')"
else
  C_RESET=''
  C_INFO=''
  C_WARN=''
  C_ERR=''
  C_OK=''
fi

# ------------------ helpers ------------------

log() {
  printf '%s[VOPK-INSTALLER]%s %s\n' "$C_INFO" "$C_RESET" "$*" >&2
}

warn() {
  printf '%s[VOPK-INSTALLER][WARN]%s %s\n' "$C_WARN" "$C_RESET" "$*" >&2
}

ok() {
  printf '%s[VOPK-INSTALLER][OK]%s %s\n' "$C_OK" "$C_RESET" "$*" >&2
}

fail() {
  printf '%s[VOPK-INSTALLER][ERROR]%s %s\n' "$C_ERR" "$C_RESET" "$*" >&2
  exit 1
}

log_install() {
  printf '%s[VOPK-INSTALLER][INSTALL]%s %s\n' "$C_OK" "$C_RESET" "$*" >&2
}

log_delete_msg() {
  printf '%s[VOPK-INSTALLER][DELETE]%s %s\n' "$C_ERR" "$C_RESET" "$*" >&2
}

usage() {
  printf 'Usage: %s [OPTIONS] [COMMAND]\n' "$0"
  printf '\nOptions:\n'
  printf '  -y, --yes, --assume-yes   Run non-interactively (assume "yes")\n'
  printf '  -h, --help                Show this help\n'
  printf '\nCommands:\n'
  printf '  install       Fresh install of VOPK\n'
  printf '  update        Update existing VOPK (or install if missing)\n'
  printf '  reinstall     Remove and install again\n'
  printf '  repair        Check/fix VOPK binary\n'
  printf '  delete        Delete VOPK (keep backup)\n'
  printf '  delete-all    Delete VOPK and backup\n'
  printf '  menu          Show interactive menu (default)\n'
}

# ❗ تم إلغاء إجبار root، لكن fallback سيظل يعمل كما هو إن وجد
require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    warn "Not running as root; commands will run with sudo where needed."

    if [ "${VOPK_SELF_FALLBACK:-0}" = "1" ]; then
      warn "Fallback already attempted; continuing without root."
      return 0
    fi

    if ! command -v sudo >/dev/null 2>&1; then
      fail "sudo not found. Install sudo or run with a full shell."
    fi

    if ! command -v bash >/dev/null 2>&1; then
      fail "bash not found. Install bash or run with a full shell."
    fi

    if ! command -v curl >/dev/null 2>&1; then
      fail "curl not found. Install curl and re-run with sudo."
    fi

    export VOPK_SELF_FALLBACK=1
    exec sudo bash -c "VOPK_SELF_FALLBACK=1 bash <(curl -fsSL '$VOPK_UPDATE_SCRIPT_URL')"
  fi
}

detect_pkg_mgr() {
  if command -v pacman >/dev/null 2>&1; then
    PKG_MGR="pacman"
    PKG_FAMILY="arch"
  elif command -v apt-get >/dev/null 2>&1; then
    PKG_MGR="apt-get"
    PKG_FAMILY="debian"
  elif command -v apt >/dev/null 2>&1; then
    PKG_MGR="apt"
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
  elif command -v brew >/dev/null 2>&1; then
    PKG_MGR="brew"
    PKG_FAMILY="brew"
  elif command -v pkg >/dev/null 2>&1; then
    PKG_MGR="pkg"
    PKG_FAMILY="freebsd"
  elif command -v pkgin >/dev/null 2>&1; then
    PKG_MGR="pkgin"
    PKG_FAMILY="netbsd"
  elif command -v pkg_add >/dev/null 2>&1; then
    PKG_MGR="pkg_add"
    PKG_FAMILY="openbsd"
  else
    PKG_MGR=""
    PKG_FAMILY=""
  fi
}

read_from_tty() {
  varname=$1
  if [ -r /dev/tty ]; then
    if IFS= read -r "$varname" 2>/dev/null </dev/tty; then
      return 0
    fi
  fi
  return 1
}

ask_confirmation() {
  msg=$1
  default=${2:-N}

  if [ "$AUTO_YES" -eq 1 ]; then
    log "AUTO_YES enabled; auto-confirming: $msg"
    return 0
  fi

  case "$default" in
    Y|y) prompt="[Y/n]"; def="Y" ;;
    *)   prompt="[y/N]"; def="N" ;;
  esac

  printf '%s[vopk-installer][PROMPT]%s %s %s ' "$C_WARN" "$C_RESET" "$msg" "$prompt" >&2

  ans=""
  if ! read_from_tty ans; then
    printf '\n' >&2
    warn "No interactive terminal available; assuming YES."
    warn "Proceeding as if you confirmed."
    return 0
  fi

  [ -z "$ans" ] && ans="$def"

  case "$ans" in
    Y|y|yes|YES|Yes|Yea|Yeah) return 0 ;;
    *)                       return 1 ;;
  esac
}

install_curl_if_needed() {
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    return 0
  fi

  detect_pkg_mgr

  if [ -z "$PKG_MGR" ]; then
    fail "No supported package manager found to install curl."
  fi

  log "Installing curl using ${PKG_MGR} with sudo..."

  case "$PKG_FAMILY" in
    debian)
      sudo $PKG_MGR update -y 2>/dev/null || sudo $PKG_MGR update || true
      sudo $PKG_MGR install -y curl
      ;;
    arch)
      sudo pacman -Sy --noconfirm curl
      ;;
    redhat)
      sudo $PKG_MGR install -y curl
      ;;
    suse)
      sudo zypper refresh || true
      sudo zypper install -y curl
      ;;
    alpine)
      sudo apk update || true
      sudo apk add --no-cache curl
      ;;
    brew)
      brew update || true
      brew install curl
      ;;
    freebsd)
      sudo pkg update -y || true
      sudo pkg install -y curl
      ;;
    netbsd)
      sudo pkgin -y update || true
      sudo pkgin -y install curl
      ;;
    openbsd)
      sudo pkg_add curl || true
      ;;
    *)
      fail "Unsupported family '$PKG_FAMILY' for installing curl."
      ;;
  esac

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    fail "Failed to install curl."
  fi

  ok "curl is now available."
}

download_vopk() {
  tmpfile="$(mktemp /tmp/vopk.XXXXXX.sh)"

  if command -v curl >/dev/null 2>&1; then
    log "Downloading VOPK using curl..."
    sudo curl -fsSL "$VOPK_URL" -o "$tmpfile"
  elif command -v wget >/dev/null 2>&1; then
    log "Downloading VOPK using wget..."
    sudo wget -qO "$tmpfile" "$VOPK_URL"
  else
    rm -f "$tmpfile"
    fail "Neither curl nor wget available."
  fi

  [ ! -s "$tmpfile" ] && fail "Downloaded file is empty."

  ok "VOPK downloaded."
  printf '%s\n' "$tmpfile"
}

install_vopk() {
  src=$1

  log_install "Installing VOPK to ${VOPK_DEST} ..."
  sudo mkdir -p "$(dirname "$VOPK_DEST")"

  if [ -f "$VOPK_DEST" ]; then
    log_install "Backing up existing VOPK to ${VOPK_BAK}"
    sudo cp -f "$VOPK_DEST" "$VOPK_BAK" || true
  fi

  sudo mv "$src" "$VOPK_DEST"
  sudo chmod 0755 "$VOPK_DEST"

  log_install "VOPK installed successfully at: ${VOPK_DEST}"
}

# ------------------ operations ------------------

op_install() {
  log_install "Starting VOPK fresh installation ..."
  install_curl_if_needed
  if [ "$PKG_FAMILY" = "arch" ]; then
    install_yay_arch
  fi
  tmpfile="$(download_vopk)"
  install_vopk "$tmpfile"
  print_summary
}

op_update() {
  if [ ! -f "$VOPK_DEST" ]; then
    log_install "VOPK not found. Fresh install instead of update."
    op_install
    return
  fi

  log_install "Updating existing VOPK ..."
  install_curl_if_needed
  if [ "$PKG_FAMILY" = "arch" ]; then
    install_yay_arch
  fi
  tmpfile="$(download_vopk)"
  install_vopk "$tmpfile"
  log_install "Update completed."
}

op_reinstall() {
  log_install "Reinstalling VOPK ..."
  if [ -f "$VOPK_DEST" ]; then
    log_install "Removing existing VOPK..."
    sudo rm -f "$VOPK_DEST"
  fi
  tmpfile="$(download_vopk)"
  install_vopk "$tmpfile"
  log_install "Reinstall completed."
}

op_repair() {
  log "Repairing VOPK installation ..."
  needs_fix=0

  if [ ! -f "$VOPK_DEST" ] || [ ! -s "$VOPK_DEST" ] || [ ! -x "$VOPK_DEST" ]; then
    warn "Binary missing/corrupt/not executable."
    needs_fix=1
  fi

  if [ "$needs_fix" -eq 1 ]; then
    tmpfile="$(download_vopk)"
    install_vopk "$tmpfile"
  else
    log "Binary looks fine. No repair needed."
  fi
  log "Repair step finished."
}

op_delete() {
  log_delete_msg "Deleting VOPK ..."
  sudo rm -f "$VOPK_DEST" 2>/dev/null || warn "Nothing to delete."
  log_delete_msg "Delete completed (backup kept)."
}

op_delete_all() {
  log_delete_msg "Deleting VOPK + backup ..."
  sudo rm -f "$VOPK_DEST" "$VOPK_BAK" 2>/dev/null || true
  log_delete_msg "Delete-all completed."
}

install_yay_arch() {
  if ! command -v pacman >/dev/null 2>&1; then return 0; fi
  if command -v yay >/dev/null 2>&1; then ok "yay exists; skip."; return 0; fi

  log_install "Preparing temporary AUR build user 'aurbuild' to install yay..."
  if id -u aurbuild >/dev/null 2>&1; then
    warn "aurbuild exists; reusing."
  else
    sudo useradd -m -r -s /bin/bash aurbuild
    AUR_USER_CREATED=1
    ok "aurbuild created."
  fi

  sudo pacman -Sy --needed --noconfirm base-devel git

  sudo su - aurbuild <<'EOF'
set -eu
workdir="$(mktemp -d /tmp/yay.XXXXXX)"
cd "$workdir"
git clone --depth=1 https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si --noconfirm
EOF

  ok "yay installed."

  if [ "$AUR_USER_CREATED" -eq 1 ]; then
    sudo userdel -r aurbuild 2>/dev/null && ok "aurbuild removed." || warn "Manual cleanup may be needed."
  else
    warn "Keeping existing aurbuild."
  fi
}

show_menu() {
  printf '\nChoose What You Want To Do:\n\n'
  printf '  1) Repair\n  2) Reinstall\n  3) Delete\n  4) Delete-all\n  5) Update\n  0) Exit\n\n[INPUT] -❯ : '
}

main() {
  parse_args "$@"
  detect_pkg_mgr
  log "Welcome to the VOPK installer & maintenance tool."

  if [ -n "$CMD" ] && [ "$CMD" != "menu" ]; then
    describe_and_confirm "$CMD"
    case "$CMD" in
      install)     op_install ;;
      update)      op_update ;;
      reinstall)   op_reinstall ;;
      repair)      op_repair ;;
      delete)      op_delete ;;
      delete-all)  op_delete_all ;;
    esac
    exit 0
  fi

  show_menu
  choice=""
  read_from_tty choice || { warn "No TTY; default update."; describe_and_confirm "update"; op_update; exit 0; }

  case "$choice" in
    1) describe_and_confirm "repair"; op_repair ;;
    2) describe_and_confirm "reinstall"; op_reinstall ;;
    3) describe_and_confirm "delete"; op_delete ;;
    4) describe_and_confirm "delete-all"; op_delete_all ;;
    5) describe_and_confirm "update"; op_update ;;
    0) exit 0 ;;
    *) fail "Invalid choice." ;;
  esac
}

main "$@"
