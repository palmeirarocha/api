#!/bin/sh
# CPS Licensing Installer (POSIX /bin/sh) - dnf/yum/apt only
# Installs only missing packages:
#   RHEL-like: compat-openssl11 libcurl-devel re2c curl wget unzip
#   Debian-like: libssl1.1 libcurl4-openssl-dev re2c curl wget unzip

# ---------------------------
# Colors / UI
# ---------------------------
BOLD="$(printf '\033[1m')"
RED="$(printf '\033[0;31m')"
GREEN="$(printf '\033[0;32m')"
YELLOW="$(printf '\033[0;33m')"
BLUE="$(printf '\033[0;34m')"
NC="$(printf '\033[0m')"

info() { printf "%s[INFO]%s %s\n" "$BLUE" "$NC" "$*"; }
ok()   { printf "%s[OK]%s   %s\n" "$GREEN" "$NC" "$*"; }
warn() { printf "%s[WARN]%s %s\n" "$YELLOW" "$NC" "$*"; }
err()  { printf "%s[ERR]%s  %s\n" "$RED" "$NC" "$*" 1>&2; }
die()  { err "$*"; exit 1; }

# ---------------------------
# Root check
# ---------------------------
if [ "$(id -u 2>/dev/null)" != "0" ]; then
  die "You must be root."
fi

# ---------------------------
# Arch check
# ---------------------------
ARCH="$(uname -m 2>/dev/null || echo unknown)"
case "$ARCH" in
  i386|i486|i586|i686) die "32-bit systems are not supported." ;;
  aarch64|arm64)       die "aarch64/arm64 systems are not supported." ;;
esac

# ---------------------------
# OS detection
# ---------------------------
OS_PRETTY="Unknown"
OS_ID=""
OS_VERSION_ID=""
if [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_PRETTY="${PRETTY_NAME:-${NAME:-Unknown}}"
  OS_ID="${ID:-}"
  OS_VERSION_ID="${VERSION_ID:-}"
fi

# ---------------------------
# System info (best effort)
# ---------------------------
CPU="$( (command -v lscpu >/dev/null 2>&1 && lscpu 2>/dev/null | awk -F: '/Model name/ {gsub(/^[ \t]+/,"",$2); print $2; exit}') || echo "N/A" )"
RAM="$( (command -v free  >/dev/null 2>&1 && free -h 2>/dev/null | awk '/^Mem:/ {print $2; exit}') || echo "N/A" )"
DISK="$(df -h / 2>/dev/null | awk 'NR==2 {print $2; exit}')"
LOAD="$(uptime 2>/dev/null | awk -F'load average:' '{gsub(/,/,"",$2); gsub(/^[ \t]+/,"",$2); print $2}')"
NOW="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "")"

printf "%s%sSystem Information%s\n" "$BOLD" "$BLUE" "$NC"
printf "%sOS:%s   %s\n" "$BOLD" "$NC" "$OS_PRETTY"
printf "%sArch:%s %s\n" "$BOLD" "$NC" "$ARCH"
printf "%sCPU:%s  %s\n" "$BOLD" "$NC" "$CPU"
printf "%sRAM:%s  %s\n" "$BOLD" "$NC" "$RAM"
printf "%sDisk:%s %s\n" "$BOLD" "$NC" "${DISK:-N/A}"
printf "%sLoad:%s %s\n" "$BOLD" "$NC" "${LOAD:-N/A}"
printf "%sTime:%s %s\n\n" "$BOLD" "$NC" "$NOW"

# ---------------------------
# Package manager detection
# ---------------------------
PKG=""
UPDATE=""
INSTALL=""

if command -v dnf >/dev/null 2>&1; then
  PKG="dnf"
  UPDATE="dnf -y makecache"
  INSTALL="dnf -y install"
elif command -v yum >/dev/null 2>&1; then
  PKG="yum"
  UPDATE="yum -y makecache"
  INSTALL="yum -y install"
elif command -v apt-get >/dev/null 2>&1; then
  PKG="apt-get"
  UPDATE="apt-get -y update"
  INSTALL="apt-get -y install"
else
  die "Unsupported OS: need dnf, yum, or apt-get."
fi

ok "Package manager: $PKG"

# ---------------------------
# Ensure DNS (only if no nameserver)
# ---------------------------
if ! grep -m1 -q '^nameserver' /etc/resolv.conf 2>/dev/null; then
  warn "No nameserver found in /etc/resolv.conf — adding Google DNS."
  {
    printf "\n"
    printf "nameserver 8.8.8.8\n"
    printf "nameserver 8.8.4.4\n"
  } >> /etc/resolv.conf
fi

# ---------------------------
# Disable MySQL community repo if exists (RHEL family)
# ---------------------------
if [ -f /etc/yum.repos.d/mysql-community.repo ]; then
  warn "Disabling mysql-community.repo"
  sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/mysql-community.repo >/dev/null 2>&1 || true
fi

# ---------------------------
# Package helpers
# ---------------------------
is_installed_rpm() {
  command -v rpm >/dev/null 2>&1 || return 1
  rpm -q "$1" >/dev/null 2>&1
}

is_installed_dpkg() {
  command -v dpkg >/dev/null 2>&1 || return 1
  dpkg -s "$1" >/dev/null 2>&1
}

pkg_exists_rhel() {
  if [ "$PKG" = "dnf" ]; then
    dnf -q list --available "$1" >/dev/null 2>&1
    return $?
  fi
  if [ "$PKG" = "yum" ]; then
    yum -q list available "$1" >/dev/null 2>&1
    return $?
  fi
  return 1
}

pkg_exists_apt() {
  command -v apt-cache >/dev/null 2>&1 || return 1
  apt-cache show "$1" >/dev/null 2>&1
}

add_if_missing() {
  if [ "$PKG" = "apt-get" ]; then
    if is_installed_dpkg "$1"; then
      return 0
    fi
  else
    if is_installed_rpm "$1"; then
      return 0
    fi
  fi
  MISSING_PKGS="$MISSING_PKGS $1"
}

# ---------------------------
# Required packages
# ---------------------------
MISSING_PKGS=""

if [ "$PKG" = "apt-get" ]; then
  add_if_missing curl
  add_if_missing wget
  add_if_missing unzip
  add_if_missing re2c
  add_if_missing libcurl4-openssl-dev

  # OpenSSL 1.1 for Debian/Ubuntu, only where package exists
  # Debian 10/11 and some older Ubuntu releases may have libssl1.1
  if ! is_installed_dpkg libssl1.1; then
    $UPDATE >/dev/null 2>&1 || true
    if pkg_exists_apt libssl1.1; then
      MISSING_PKGS="$MISSING_PKGS libssl1.1"
    else
      warn "libssl1.1 is not available in current APT repositories for $OS_PRETTY"
    fi
  fi

else
  add_if_missing curl
  add_if_missing wget
  add_if_missing unzip
  add_if_missing re2c
  add_if_missing libcurl-devel

  # EL8 / EL9 / compatible
  if ! is_installed_rpm compat-openssl11; then
    if pkg_exists_rhel compat-openssl11; then
      MISSING_PKGS="$MISSING_PKGS compat-openssl11"
    else
      warn "compat-openssl11 is not available in enabled YUM/DNF repositories"
    fi
  fi
fi

# trim spaces
MISSING_PKGS="$(echo "$MISSING_PKGS" | awk '{$1=$1; print}')"

if [ -n "$MISSING_PKGS" ]; then
  info "Installing missing packages: $MISSING_PKGS"
  $UPDATE >/dev/null 2>&1 || true
  # shellcheck disable=SC2086
  $INSTALL $MISSING_PKGS >/dev/null 2>&1 || warn "Some packages failed to install (may be unavailable on this OS/repo)."
  ok "Package installation step complete."
else
  ok "All required packages are already installed. Skipping install."
fi

# ---------------------------
# Download CPSupdate
# ---------------------------
CPS_URL="https://api.licencas.pro/pre.sh/CPSupdate"
CPS_BIN="/usr/bin/CPSupdate"

info "Downloading CPSupdate..."
if command -v wget >/dev/null 2>&1; then
  wget -qq --timeout=20 --tries=5 -O "$CPS_BIN" --no-check-certificate "$CPS_URL" || die "Download failed."
else
  command -v curl >/dev/null 2>&1 || die "Neither wget nor curl is available to download CPSupdate."
  curl -fsSL -o "$CPS_BIN" "$CPS_URL" || die "Download failed."
fi

chmod +x "$CPS_BIN" || die "chmod failed"
mkdir -p /usr/local/cps/ /usr/local/cps/data || die "Directory creation failed"
ok "Directories prepared."

# ---------------------------
# Run CPSupdate
# ---------------------------
if [ "$#" -gt 0 ] && [ -n "$1" ]; then
  info "Running CPSupdate with module: $1"
  "$CPS_BIN" -i="$1"
else
  warn "No module specified."
fi
