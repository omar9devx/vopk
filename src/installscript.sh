#!/usr/bin/env sh
# VOPK Installer - Omar9Dev
# Installs vopk into /usr/local/bin/vopk and prepares dependencies per distro.
# - Non-root installer (uses sudo where required)
# - On Arch: temporary 'aurbuild' user to install yay, then cleanup
# - Colored output via printf
# - POSIX sh compatible

set -eu

VOPK_URL="https://raw.githubusercontent.com/omar9devx/vopk/main/bin/vopk"
VOPK_DEST="/usr/local/bin/vopk"

PKG_MGR=""
PKG_FAMILY=""
AUR_USER_CREATED=0
AUTO_YES=0

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

# --------------- detect package manager ---------------
detect_pkg_mgr() {
  if command -v pacman >/dev/null 2>&1; then
    PKG_MGR="sudo pacman"
    PKG_FAMILY="arch"
  elif command -v apt-get >/dev/null 2>&1; then
    PKG_MGR="sudo apt-get"
    PKG_FAMILY="debian"
  elif command -v apt >/dev/null 2>&1; then
    PKG_MGR="sudo apt"
    PKG_FAMILY="debian"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MGR="sudo dnf"
    PKG_FAMILY="redhat"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MGR="sudo yum"
    PKG_FAMILY="redhat"
  elif command -v zypper >/dev/null 2>&1; then
    PKG_MGR="sudo zypper"
    PKG_FAMILY="suse"
  elif command -v apk >/dev/null 2>&1; then
    PKG_MGR="sudo apk"
    PKG_FAMILY="alpine"
  elif command -v brew >/dev/null 2>&1; then
    PKG_MGR="brew"
    PKG_FAMILY="brew"
  elif command -v pkg >/dev/null 2>&1; then
    PKG_MGR="sudo pkg"
    PKG_FAMILY="freebsd"
  elif command -v pkg_add >/dev/null 2>&1; then
    PKG_MGR="sudo pkg_add"
    PKG_FAMILY="openbsd"
  else
    PKG_MGR=""
    PKG_FAMILY=""
  fi
}

# --------------- confirmation prompt ---------------
read_from_tty() {
  var=$1
  [ -r /dev/tty ] && IFS= read -r "$var" </dev/tty && return 0 || return 1
}

ask_confirmation() {
  msg=$1
  default=${2:-N}

  [ "$AUTO_YES" -eq 1 ] && log "AUTO_YES enabled → auto-confirmed: $msg" && return 0

  case "$default" in
    Y|y) prompt="[Y/n]" def="Y" ;;
    *)   prompt="[y/N]" def="N" ;;
  esac

  printf "%s[vopk-installer][PROMPT]%s %s %s " "$C_WARN" "$C_RESET" "$msg" "$prompt" >&2

  ans=""
  read_from_tty ans || warn "No TTY detected → assuming NO." && return 1
  [ -z "$ans" ] && ans="$def"

  case "$ans" in Y|y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# --------------- install curl if needed ---------------
install_curl_if_needed() {
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    return 0
  fi

  detect_pkg_mgr
  [ -z "$PKG_MGR" ] && fail "No package manager found to install curl/wget."

  log "Installing curl..."
  case "$PKG_FAMILY" in
    debian)  $PKG_MGR update -y 2>/dev/null || true; $PKG_MGR install -y curl ;;
    arch)    sudo pacman -Sy --noconfirm curl ;;
    redhat)  $PKG_MGR install -y curl ;;
    suse)    sudo zypper refresh || true; sudo zypper install -y curl ;;
    alpine)  sudo apk update || true; sudo apk add --no-cache curl ;;
    brew)    brew update || true; brew install curl ;;
    freebsd) sudo pkg update -y || true; sudo pkg install -y curl ;;
    openbsd) sudo pkg_add curl || true ;;
    *)       fail "Unsupported package manager family '$PKG_FAMILY' for installing curl." ;;
  esac

  command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || fail "curl installation failed."
  ok "curl ready."
}

# --------------- download VOPK ---------------
download_vopk() {
  tmpfile="$(mktemp /tmp/vopk.XXXXXX)"
  log "Downloading vopk..."
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$VOPK_URL" -o "$tmpfile" || fail "Download failed (curl)"
  else
    wget -qO "$tmpfile" "$VOPK_URL" || fail "Download failed (wget)"
  fi

  [ -s "$tmpfile" ] || fail "Downloaded file is empty."
  ok "Downloaded."
  printf "%s\n" "$tmpfile"
}

# --------------- install yay on arch ---------------
install_yay_arch() {
  [ "$PKG_FAMILY" = "arch" ] || return 0
  command -v yay >/dev/null 2>&1 && ok "yay exists → skip" && return 0

  log "Creating aurbuild user..."
  if id -u aurbuild >/dev/null 2>&1; then
    warn "aurbuild exists → reuse, won't delete later"
  else
    sudo useradd -m -r -s /bin/bash aurbuild && AUR_USER_CREATED=1 || fail "useradd failed"
    ok "aurbuild created."
  fi

  sudo pacman -Sy --needed --noconfirm base-devel git

  su - aurbuild <<'EOF'
  set -eu
  d=$(mktemp -d /tmp/yay.XXXX)
  cd "$d"
  git clone --depth=1 https://aur.archlinux.org/yay-bin.git
  cd yay-bin
  makepkg -si --noconfirm
EOF

  ok "yay installed."

  [ "$AUR_USER_CREATED" -eq 1 ] && sudo userdel -r aurbuild 2>/dev/null && ok "aurbuild removed." || warn "aurbuild not removed."
}

# --------------- install vopk ---------------
install_vopk() {
  src=$1
  log "Installing to $VOPK_DEST ..."
  sudo mkdir -p "$(dirname "$VOPK_DEST")"
  sudo mv "$src" "$VOPK_DEST"
  sudo chmod 0755 "$VOPK_DEST"
  ok "Installed at $VOPK_DEST"
}

print_summary() {
  printf "\n%sVOPK installation completed.%s\n\n" "$C_OK" "$C_RESET"
  printf "Run:\n  vopk help\n"
}

# --------------- args ---------------
usage() {
  printf "Usage: %s [OPTIONS]\n" "$0"
}

# --------------- main ---------------
main() {
  parse_args "$@"
  detect_pkg_mgr
  log "Welcome to installer."

  if ! ask_confirmation "Continue installation?" "N"; then
    warn "Aborted."; exit 0
  fi

  install_curl_if_needed
  install_yay_arch
  t="$(download_vopk)"
  install_vopk "$t"
  print_summary
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -y|--yes|--assume-yes) AUTO_YES=1 ;;
      -h|--help) usage; exit 0 ;;
      *) warn "Unknown option: $1" ;;
    esac
    shift
  done
}

main "$@"
