#!/usr/bin/env sh
# VOPK Installer - Omar9DevX
# Installs vopk into /usr/local/bin/vopk (or ~/.local/bin/vopk)
# - Frictionless installation for one-liner execution
# - Seamless user-space fallback (~/.local/bin) if sudo is not available
# - Universal architecture fallback (x86_64 binary or pure-bash script)
# - Colored output via printf
# - POSIX sh compatible

set -eu

VOPK_BIN_URL="https://raw.githubusercontent.com/omar9devx/vopk/main/bin/vopk"
VOPK_SH_URL="https://raw.githubusercontent.com/omar9devx/vopk/main/src/vopk.sh"
VOPK_DEST="${VOPK_DEST:-}"

PKG_MGR=""
PKG_FAMILY=""
AUR_USER_CREATED=0

# --------------- colors ---------------
if [ -t 2 ] && [ "${NO_COLOR:-0}" = "0" ]; then
  C_RESET="$(printf '\033[0m')"
  C_INFO="$(printf '\033[1;34m')"
  C_WARN="$(printf '\033[1;33m')"
  C_ERR="$(printf '\033[1;31m')"
  C_OK="$(printf '\033[1;32m')"
else
  C_RESET='' C_INFO='' C_WARN='' C_ERR='' C_OK=''
fi

# --------------- logging helpers ---------------
log()  { printf '%s[vopk-installer]%s %s\n' "$C_INFO" "$C_RESET" "$*" >&2; }
warn() { printf '%s[vopk-installer][WARN]%s %s\n' "$C_WARN" "$C_RESET" "$*" >&2; }
ok()   { printf '%s[vopk-installer][OK]%s %s\n' "$C_OK" "$C_RESET" "$*" >&2; }
fail() { printf '%s[vopk-installer][ERROR]%s %s\n' "$C_ERR" "$C_RESET" "$*" >&2; exit 1; }

# --------------- destination detection ---------------
detect_dest() {
  if [ -z "${VOPK_DEST:-}" ]; then
    if [ "$(id -u)" -eq 0 ]; then
      VOPK_DEST="/usr/local/bin/vopk"
    elif [ -w "/usr/local/bin" ]; then
      VOPK_DEST="/usr/local/bin/vopk"
    elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
      VOPK_DEST="/usr/local/bin/vopk"
    else
      # Default user-space destination
      VOPK_DEST="$HOME/.local/bin/vopk"
      mkdir -p "$HOME/.local/bin"
    fi
  fi
}

# --------------- detect package manager ---------------
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
  elif command -v pkg_add >/dev/null 2>&1; then
    PKG_MGR="pkg_add"
    PKG_FAMILY="openbsd"
  else
    PKG_MGR=""
    PKG_FAMILY=""
  fi
}

# --------------- install curl if needed ---------------
install_curl_if_needed() {
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    return 0
  fi

  detect_pkg_mgr
  [ -z "$PKG_MGR" ] && fail "No package manager found to install curl/wget."

  log "Installing curl..."
  SUDO=""
  [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && SUDO="sudo"

  case "$PKG_FAMILY" in
    debian)  $SUDO $PKG_MGR update -y 2>/dev/null || true; $SUDO $PKG_MGR install -y curl ;;
    arch)    $SUDO pacman -Sy --noconfirm curl ;;
    redhat)  $SUDO $PKG_MGR install -y curl ;;
    suse)    $SUDO zypper refresh || true; $SUDO zypper install -y curl ;;
    alpine)  $SUDO apk update || true; $SUDO apk add --no-cache curl ;;
    brew)    brew update || true; brew install curl ;;
    freebsd) $SUDO pkg update -y || true; $SUDO pkg install -y curl ;;
    openbsd) $SUDO pkg_add curl || true ;;
    *)       fail "Unsupported package manager family '$PKG_FAMILY' for installing curl." ;;
  esac

  command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || fail "curl installation failed."
  ok "curl ready."
}

# --------------- download VOPK ---------------
download_vopk() {
  tmpfile="$(mktemp /tmp/vopk.XXXXXX)"
  log "Downloading vopk..."

  arch="$(uname -m)"
  target_url="$VOPK_BIN_URL"
  if [ "$arch" != "x86_64" ] && [ "$arch" != "amd64" ]; then
    log "Non-x86_64 architecture ($arch) detected; downloading universal pure-bash script..."
    target_url="$VOPK_SH_URL"
  fi

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$target_url" -o "$tmpfile" || fail "Download failed (curl)"
  else
    wget -qO "$tmpfile" "$target_url" || fail "Download failed (wget)"
  fi

  [ -s "$tmpfile" ] || fail "Downloaded file is empty."
  ok "Downloaded successfully."
  printf "%s\n" "$tmpfile"
}

# --------------- install yay on arch ---------------
install_yay_arch() {
  [ "$PKG_FAMILY" = "arch" ] || return 0
  command -v yay >/dev/null 2>&1 && return 0
  command -v paru >/dev/null 2>&1 && return 0

  if [ "$(id -u)" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
    warn "Neither yay nor paru found, and sudo is unavailable. Skipping AUR helper setup."
    return 0
  fi

  log "Setting up yay for Arch Linux AUR support..."
  if id -u aurbuild >/dev/null 2>&1; then
    warn "aurbuild user exists → reusing."
  else
    sudo useradd -m -r -s /bin/bash aurbuild && AUR_USER_CREATED=1 || {
      warn "Failed to create aurbuild user; skipping yay install."
      return 0
    }
  fi

  sudo pacman -Sy --needed --noconfirm base-devel git || true

  sudo su - aurbuild <<'EOF'
  set -eu
  d=$(mktemp -d /tmp/yay.XXXX)
  cd "$d"
  git clone --depth=1 https://aur.archlinux.org/yay-bin.git
  cd yay-bin
  makepkg -si --noconfirm
EOF

  ok "yay installed."

  [ "$AUR_USER_CREATED" -eq 1 ] && sudo userdel -r aurbuild 2>/dev/null || true
}

# --------------- install vopk ---------------
install_vopk() {
  src=$1
  dest_dir="$(dirname "$VOPK_DEST")"

  log "Installing to $VOPK_DEST ..."

  if [ -w "$dest_dir" ] || [ "$(id -u)" -eq 0 ]; then
    mkdir -p "$dest_dir"
    mv -f "$src" "$VOPK_DEST"
    chmod 0755 "$VOPK_DEST"
  elif command -v sudo >/dev/null 2>&1; then
    if sudo mkdir -p "$dest_dir" 2>/dev/null && sudo mv -f "$src" "$VOPK_DEST" 2>/dev/null; then
      sudo chmod 0755 "$VOPK_DEST"
    else
      # Sudo failed or cancelled: fallback cleanly to ~/.local/bin/vopk
      warn "Permission denied for $VOPK_DEST; installing to user-space at $HOME/.local/bin/vopk..."
      VOPK_DEST="$HOME/.local/bin/vopk"
      mkdir -p "$HOME/.local/bin"
      mv -f "$src" "$VOPK_DEST"
      chmod 0755 "$VOPK_DEST"
    fi
  else
    warn "Falling back to user-space install at $HOME/.local/bin/vopk..."
    VOPK_DEST="$HOME/.local/bin/vopk"
    mkdir -p "$HOME/.local/bin"
    mv -f "$src" "$VOPK_DEST"
    chmod 0755 "$VOPK_DEST"
  fi

  ok "Installed at $VOPK_DEST"
}

print_summary() {
  printf "\n%s==================================================%s\n" "$C_OK" "$C_RESET"
  printf "%s  VOPK 3.1.0 (Jammy) Installation Complete!  %s\n" "$C_OK" "$C_RESET"
  printf "%s==================================================%s\n\n" "$C_OK" "$C_RESET"
  printf "Installed binary: %s\n" "$VOPK_DEST"
  case ":$PATH:" in
    *":$(dirname "$VOPK_DEST"):*") ;;
    *) warn "$(dirname "$VOPK_DEST") is not in your PATH. Add it to ~/.bashrc or ~/.zshrc:\n  export PATH=\"$(dirname "$VOPK_DEST"):\$PATH\"" ;;
  esac
  printf "\nGet started:\n"
  printf "  vopk --version\n"
  printf "  vopk help\n"
  printf "  vopk sys-info\n"
  printf "  vopk doctor\n\n"
}

# --------------- args ---------------
usage() {
  printf "Usage: %s [OPTIONS]\n\n" "$0"
  printf "Options:\n"
  printf "  --dest PATH               Install destination (default: /usr/local/bin/vopk or ~/.local/bin/vopk)\n"
  printf "  -y, --yes, --assume-yes   Non-interactive mode\n"
  printf "  -h, --help                Show this help message\n"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dest)
        shift
        [ "$#" -gt 0 ] && VOPK_DEST="$1" || fail "--dest requires a path argument"
        ;;
      -y|--yes|--assume-yes)
        # Accepted for backwards compatibility
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        warn "Unknown option: $1"
        ;;
    esac
    shift
  done
}

# --------------- main ---------------
main() {
  parse_args "$@"
  detect_pkg_mgr
  detect_dest

  log "Starting VOPK installation (v3.1.0 Jammy)..."
  log "Target destination: $VOPK_DEST"

  install_curl_if_needed
  install_yay_arch
  t="$(download_vopk)"
  install_vopk "$t"
  print_summary
}

main "$@"
