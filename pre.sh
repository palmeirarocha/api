#!/bin/sh
# Instalador de Licenciamento CPS (POSIX /bin/sh) - somente dnf/yum/apt
# Instala apenas os pacotes ausentes:
#   Baseado em RHEL: compat-openssl11 libcurl-devel re2c curl wget unzip
#   Baseado em Debian: libssl1.1 libcurl4-openssl-dev re2c curl wget unzip

# ---------------------------
# Cores / Interface
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
# Verificação de root
# ---------------------------
if [ "$(id -u 2>/dev/null)" != "0" ]; then
  die "Você precisa ser root."
fi

# ---------------------------
# Verificação de arquitetura
# ---------------------------
ARCH="$(uname -m 2>/dev/null || echo unknown)"
case "$ARCH" in
  i386|i486|i586|i686) die "Sistemas de 32 bits não são suportados." ;;
  aarch64|arm64)       die "Sistemas aarch64/arm64 não são suportados." ;;
esac

# ---------------------------
# Detecção do sistema operacional
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
# Informações do sistema (melhor esforço)
# ---------------------------
CPU="$( (command -v lscpu >/dev/null 2>&1 && lscpu 2>/dev/null | awk -F: '/Model name/ {gsub(/^[ \t]+/,"",$2); print $2; exit}') || echo "N/A" )"
RAM="$( (command -v free  >/dev/null 2>&1 && free -h 2>/dev/null | awk '/^Mem:/ {print $2; exit}') || echo "N/A" )"
DISK="$(df -h / 2>/dev/null | awk 'NR==2 {print $2; exit}')"
LOAD="$(uptime 2>/dev/null | awk -F'load average:' '{gsub(/,/,"",$2); gsub(/^[ \t]+/,"",$2); print $2}')"
NOW="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "")"

printf "%s%sInformações do Sistema%s\n" "$BOLD" "$BLUE" "$NC"
printf "%sSO:%s     %s\n" "$BOLD" "$NC" "$OS_PRETTY"
printf "%sArq:%s    %s\n" "$BOLD" "$NC" "$ARCH"
printf "%sCPU:%s    %s\n" "$BOLD" "$NC" "$CPU"
printf "%sRAM:%s    %s\n" "$BOLD" "$NC" "$RAM"
printf "%sDisco:%s  %s\n" "$BOLD" "$NC" "${DISK:-N/A}"
printf "%sCarga:%s  %s\n" "$BOLD" "$NC" "${LOAD:-N/A}"
printf "%sHora:%s   %s\n\n" "$BOLD" "$NC" "$NOW"

# ---------------------------
# Detecção do gerenciador de pacotes
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
  die "SO não suportado: é necessário dnf, yum ou apt-get."
fi

ok "Gerenciador de pacotes: $PKG"

# ---------------------------
# Garantir DNS (apenas se não houver nameserver)
# ---------------------------
if ! grep -m1 -q '^nameserver' /etc/resolv.conf 2>/dev/null; then
  warn "Nenhum nameserver encontrado em /etc/resolv.conf — adicionando DNS do Google."
  {
    printf "\n"
    printf "nameserver 8.8.8.8\n"
    printf "nameserver 8.8.4.4\n"
  } >> /etc/resolv.conf
fi

# ---------------------------
# Desabilitar repositório da comunidade MySQL, se existir (família RHEL)
# ---------------------------
if [ -f /etc/yum.repos.d/mysql-community.repo ]; then
  warn "Desabilitando mysql-community.repo"
  sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/mysql-community.repo >/dev/null 2>&1 || true
fi

# ---------------------------
# Funções auxiliares de pacotes
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
# Pacotes necessários
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
      warn "libssl1.1 não está disponível nos repositórios APT atuais para $OS_PRETTY"
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
      warn "compat-openssl11 não está disponível nos repositórios YUM/DNF habilitados"
    fi
  fi
fi

# remover espaços extras
MISSING_PKGS="$(echo "$MISSING_PKGS" | awk '{$1=$1; print}')"

if [ -n "$MISSING_PKGS" ]; then
  info "Instalando pacotes ausentes: $MISSING_PKGS"
  $UPDATE >/dev/null 2>&1 || true
  # shellcheck disable=SC2086
  $INSTALL $MISSING_PKGS >/dev/null 2>&1 || warn "Alguns pacotes falharam ao instalar (podem estar indisponíveis neste SO/repositório)."
  ok "Etapa de instalação de pacotes concluída."
else
  ok "Todos os pacotes necessários já estão instalados. Pulando instalação."
fi

# ---------------------------
# Download do CPSupdate
# ---------------------------
CPS_URLS="https://api.licencas.pro/CPSupdate https://mirror.cpanelseller.xyz/CPSupdate"
CPS_BIN="/usr/bin/CPSupdate"
CPS_TMP="/tmp/CPSupdate.$$"

download_file() {
  # $1 = url, $2 = destino
  if command -v wget >/dev/null 2>&1; then
    wget -qq --timeout=20 --tries=3 -O "$2" --no-check-certificate "$1"
  else
    command -v curl >/dev/null 2>&1 || die "Nem wget nem curl estão disponíveis para baixar o CPSupdate."
    curl -fsSL -o "$2" "$1"
  fi
}

is_elf_binary() {
  [ -s "$1" ] || return 1
  head -c 4 "$1" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n' | grep -qi '^7f454c46$'
}

DOWNLOADED=0
for url in $CPS_URLS; do
  info "Baixando o CPSupdate de $url..."
  if download_file "$url" "$CPS_TMP" && is_elf_binary "$CPS_TMP"; then
    ok "Binário válido obtido de $url"
    DOWNLOADED=1
    break
  else
    warn "Falha ao obter um binário válido de $url — tentando próxima fonte, se houver."
    rm -f "$CPS_TMP"
  fi
done

[ "$DOWNLOADED" -eq 1 ] || die "Não foi possível baixar o CPSupdate de nenhuma fonte disponível."

mv "$CPS_TMP" "$CPS_BIN" || die "Falha ao mover o binário para $CPS_BIN"
chmod +x "$CPS_BIN" || die "Falha no chmod"
mkdir -p /usr/local/cps/ /usr/local/cps/data || die "Falha ao criar diretórios"
ok "Diretórios preparados."

# ---------------------------
# Executar CPSupdate
# ---------------------------
if [ "$#" -gt 0 ] && [ -n "$1" ]; then
  info "Executando CPSupdate com o módulo: $1"
  "$CPS_BIN" -i="$1"
else
  warn "Nenhum módulo especificado."
fi
