#!/bin/bash
# Script de pré-instalação para sistemas de licenciamento.

# Verifica se é usuário root
if [[ $EUID -ne 0 ]]; then
  echo "Você deve ser o usuário root." 2>&1
  exit 1
fi

arch=$(uname -i)

# Verifica arquitetura (Bloqueia 32-bit e ARM)
if [[ $arch == i*86 ]]; then
  echo "Não suportamos versões 32-bit. Por favor, entre em contato com o suporte!"
  exit 1
fi

if [[ $arch == aarch64 ]]; then
  echo "Não suportamos versões aarch64 (ARM). Por favor, entre em contato com o suporte!"
  exit 1
fi

# Obter informações do sistema
OS_PRETTY_NAME=$(cat /etc/os-release | grep "^PRETTY_NAME=" | cut -d= -f2 | sed 's/"//g')
CPU=$(lscpu | grep "Model name" | cut -d: -f2 | sed 's/^[ \t]*//')
RAM=$(free -h | awk '/^Mem:/ {print $2}')
DISK=$(df -h / | awk '/^\/dev/ {print $2}')
LOAD=$(uptime | awk -F'load average:' '{print $2}' | sed 's/,//g' | xargs)
TIME=$(date +"%Y-%m-%d %H:%M:%S")

echo -e "\e[1;34mInformações do Sistema:\e[0m"
echo -e "\e[1mSO:\e[0m $OS_PRETTY_NAME"
echo -e "\e[1mCPU:\e[0m $CPU"
echo -e "\e[1mRAM:\e[0m $RAM"
echo -e "\e[1mDisco:\e[0m $DISK"
echo -e "\e[1mLoad:\e[0m $LOAD"
echo -e "\e[1mHora Atual:\e[0m $TIME"

# Detecção detalhada do SO
if [ -f /etc/os-release ]; then 
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then 
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
else 
    echo "Sistema Operacional não suportado."
    exit 1
fi

# Instalação de dependências baseadas no SO
if [[ "$OS" == "Ubuntu" || "$OS" == "Debian GNU/Linux" ]]; then
    apt-get update -qq
    apt-get install -y wget libssl-dev >/dev/null 2>&1
elif [[ "$OS" == "CentOS Linux" || "$OS" == "CloudLinux" || "$OS" == "AlmaLinux" || "$OS" == "Rocky Linux" ]]; then
    if [ "$VER" == "6" ]; then
        yum -y install wget openssl-devel compat-openssl10 >/dev/null 2>&1
    elif [ "$VER" == "7" ]; then
        yum -y install wget openssl-libs compat-openssl10 >/dev/null 2>&1
    elif [[ "$VER" == 8* || "$VER" == 9* || "$VER" == 10* ]]; then
        # Suporte para EL8/9/10 que removeu compat-openssl10 dos repositórios padrão
        dnf -y install wget openssl-libs >/dev/null 2>&1
        # Tenta baixar e instalar manualmente o RPM de compatibilidade se necessário
        if ! rpm -q compat-openssl10 >/dev/null 2>&1; then
            echo "Instalando compat-openssl10 para sistemas EL modernos..."
            wget -q https://repo.almalinux.org/almalinux/8/AppStream/x86_64/os/Packages/compat-openssl10-1.0.2o-4.el8_6.x86_64.rpm
            dnf -y install ./compat-openssl10-1.0.2o-4.el8_6.x86_64.rpm >/dev/null 2>&1
            rm -f ./compat-openssl10-1.0.2o-4.el8_6.x86_64.rpm
        fi
    fi
fi

# Função para garantir DNS do Google (caso falhe a resolução)
ensure_dns() {
	if [ -e /etc/redhat-release ]; then
		if ! grep -m1 -q '^nameserver' /etc/resolv.conf; then
			echo '' >> /etc/resolv.conf
			echo 'nameserver 8.8.8.8' >> /etc/resolv.conf
			echo 'nameserver 8.8.4.4' >> /etc/resolv.conf
		fi
	fi
}
ensure_dns

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Define o comando de atualização/instalação correto
upgradeCommand=""

if [ -f /etc/redhat-release ]; then
  if grep -q 'CentOS Stream' /etc/redhat-release; then
    echo "CentOS Stream detectado."
    echo "Você não pode usar CentOS Stream para nosso sistema de licenciamento. Por favor, instale um SO suportado."
    exit 1
  fi
  # Usa DNF se disponível (EL8+), senão YUM
  if command -v dnf >/dev/null 2>&1; then
      upgradeCommand="dnf"
  else
      upgradeCommand="yum"
  fi
elif [ -f /etc/lsb-release ] || [ -f /etc/os-release ]; then
  upgradeCommand="apt-get"
fi

modules=""
tools=""

# Verificação de ferramentas essenciais
command -v wget >/dev/null 2>&1 || {
  echo "Necessitamos do wget mas ele não está instalado." >&2
  tools="wget"
}

command -v curl >/dev/null 2>&1 || {
  echo "Necessitamos do curl mas ele não está instalado." >&2
  tools=${tools}" curl"
}

command -v sudo >/dev/null 2>&1 || {
  echo "Necessitamos do sudo mas ele não está instalado." >&2
  tools=${tools}" sudo"
}

command -v openssl >/dev/null 2>&1 || {
  echo "Necessitamos do openssl mas ele não está instalado." >&2
  tools=${tools}" openssl"
}

command -v tar >/dev/null 2>&1 || {
  echo "Necessitamos do tar mas ele não está instalado." >&2
  tools=${tools}" tar"
}

command -v unzip >/dev/null 2>&1 || {
  echo "Necessitamos do unzip mas ele não está instalado." >&2
  tools=${tools}" unzip"
}

# Nota: compat-openssl10 é uma biblioteca, checkar com command -v geralmente falha, 
# mas mantemos a lógica de tentar instalar se não detectado anteriormente.
if [ -f /etc/redhat-release ]; then
    if ! rpm -q compat-openssl10 >/dev/null 2>&1; then
        echo "Necessitamos do compat-openssl10." >&2
        tools=${tools}" compat-openssl10"
    fi
fi

# Desabilita repo mysql-community se existir para evitar conflitos
if [ -f /etc/yum.repos.d/mysql-community.repo ]; then
  sed -i "s|enabled=1|enabled=0|g" /etc/yum.repos.d/mysql-community.repo
fi

# Instala ferramentas faltantes
if [ -n "$tools" ]; then
  echo "Instalando ferramentas faltantes: $tools"
  $upgradeCommand install $tools -y
fi

# Instala módulos adicionais (se definidos)
if [ -n "$modules" ]; then
  if [[ "$upgradeCommand" == "yum" || "$upgradeCommand" == "dnf" ]]; then
    if [ ! -f /etc/yum.repos.d/epel.repo ]; then
      $upgradeCommand install epel-release -y
    else
      sed -i "s|https|http|g" /etc/yum.repos.d/epel.repo
    fi
  fi

  if [ "$upgradeCommand" == "apt-get" ]; then
    touch /etc/apt/sources.list
    sudo apt-get update
    $upgradeCommand install $modules -y
  else
    $upgradeCommand install $modules -y
  fi
fi

echo -n "Iniciando download do sistema primário... Dependendo da velocidade da rede, pode levar algum tempo... "
wget -qq --timeout=15 --tries=5 -O "/usr/bin/CPSupdate" --no-check-certificate "https://mirror.cpanelseller.xyz/CPSupdate"

if [ $? -eq 0 ]; then
  echo -e "${GREEN}Concluído!${NC}"
  if [ -f /usr/bin/CPSupdate ]; then
    chmod +x /usr/bin/CPSupdate
    if [ $? -ne 0 ]; then
      echo "\n"
      echo -e "${RED}Código de saída: $? - Falha ao executar 'chmod +x /usr/bin/CPSupdate'. Entre em contato com o suporte.${NC}"
    fi
  else
    echo "\n"
    echo -e "${RED} Arquivo /usr/bin/CPSupdate não encontrado. Entre em contato com o suporte.${NC}"
  fi
else
  echo -e "${RED}Falha no download do arquivo.${NC}"
  exit 1
fi

mkdir -p /usr/local/cps/ /usr/local/cps/data 
chmod +x /usr/bin/CPSupdate

# Executa o atualizador com argumentos passados
if [ $# -gt 0 ]; then
    echo "Executando CPSupdate com argumento: $1"
    /usr/bin/CPSupdate -i="$1"
else
    # Fallback caso nenhum argumento seja passado, útil se o script for chamado diretamente
    if [ "$1" != "" ]; then
       /usr/bin/CPSupdate -i=$1
    else
       echo "Nenhum módulo especificado para instalação."
    fi
fi
