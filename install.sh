#!/usr/bin/env bash
set -euo pipefail

VERSION="${NDIPLAYER_VERSION:-v1.2.2}"
REPO="LiveToDie-BR/ndiplayer"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${VERSION}"

TMP_DIR="$(mktemp -d)"
APP_DIR="/opt/ndiplayer"
CONFIG_FILE="/etc/ndiplayer.conf"
SERVICE_PLAYER="/etc/systemd/system/ndiplayer.service"
SERVICE_WEB="/etc/systemd/system/ndiplayer-web.service"
LD_CONF="/etc/ld.so.conf.d/ndiplayer-ndi.conf"

CURRENT_USER="${SUDO_USER:-$USER}"
USER_HOME="$(eval echo "~${CURRENT_USER}")"
USER_UID="$(id -u "${CURRENT_USER}")"
ARCH="$(uname -m)"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

log()  { echo "[INFO] $*"; }
ok()   { echo "[OK]   $*"; }
warn() { echo "[WARN] $*"; }
err()  { echo "[ERRO] $*" >&2; }

require_sudo() {
  if [[ "$EUID" -ne 0 ]]; then
    err "Execute assim:"
    echo "curl -fsSL ${BASE_URL}/install.sh | sudo bash"
    exit 1
  fi
}

detect_os() {
  if [[ ! -f /etc/debian_version ]]; then
    err "Este instalador foi preparado para Debian/Ubuntu."
    exit 1
  fi
  ok "Sistema compatível detectado."
}

install_system_dependencies() {
  log "Instalando dependências do sistema..."
  apt update
  apt install -y \
    curl \
    git \
    rsync \
    ffmpeg \
    python3 \
    python3-pip \
    python3-flask \
    build-essential \
    pkg-config \
    libavcodec-dev \
    libavformat-dev \
    libavdevice-dev \
    libavutil-dev \
    libswscale-dev
  ok "Dependências do sistema instaladas."
}

download_runtime_files() {
  log "Baixando arquivos do NDI Player ${VERSION}..."
  mkdir -p "${TMP_DIR}/webui/static" "${TMP_DIR}/webui/templates"

  curl -fsSL "${BASE_URL}/ndiplayer" -o "${TMP_DIR}/ndiplayer"
  curl -fsSL "${BASE_URL}/ndiplayer-scan-sources" -o "${TMP_DIR}/ndiplayer-scan-sources"
  curl -fsSL "${BASE_URL}/ndiplayer-setup" -o "${TMP_DIR}/ndiplayer-setup" || true
  curl -fsSL "${BASE_URL}/ndiplayer_setup" -o "${TMP_DIR}/ndiplayer_setup" || true
  curl -fsSL "${BASE_URL}/uninstall.sh" -o "${TMP_DIR}/uninstall.sh"
  curl -fsSL "${BASE_URL}/webui/app.py" -o "${TMP_DIR}/webui/app.py"
  curl -fsSL "${BASE_URL}/webui/requirements.txt" -o "${TMP_DIR}/webui/requirements.txt"
  curl -fsSL "${BASE_URL}/webui/static/style.css" -o "${TMP_DIR}/webui/static/style.css"
  curl -fsSL "${BASE_URL}/webui/templates/index.html" -o "${TMP_DIR}/webui/templates/index.html"

  chmod +x "${TMP_DIR}/ndiplayer" 2>/dev/null || true
  chmod +x "${TMP_DIR}/ndiplayer-scan-sources" 2>/dev/null || true
  chmod +x "${TMP_DIR}/ndiplayer-setup" 2>/dev/null || true
  chmod +x "${TMP_DIR}/ndiplayer_setup" 2>/dev/null || true
  chmod +x "${TMP_DIR}/uninstall.sh" 2>/dev/null || true

  ok "Arquivos baixados."
}

find_ndi_sdk_dir() {
  if [[ -d "${USER_HOME}/NDI SDK for Linux" ]]; then
    echo "${USER_HOME}/NDI SDK for Linux"
    return 0
  fi

  local sdk_sh=""
  sdk_sh="$(find "${USER_HOME}" -maxdepth 1 -type f -name 'Install_NDI_SDK_v*_Linux.sh' | head -n 1 || true)"
  if [[ -n "${sdk_sh}" ]]; then
    log "Executando extrator do SDK NDI..."
    chmod +x "${sdk_sh}"
    su - "${CURRENT_USER}" -c "\"${sdk_sh}\"" || true
    if [[ -d "${USER_HOME}/NDI SDK for Linux" ]]; then
      echo "${USER_HOME}/NDI SDK for Linux"
      return 0
    fi
  fi

  local sdk_tgz=""
  sdk_tgz="$(find "${USER_HOME}" -maxdepth 1 -type f -name 'Install_NDI_SDK_v*_Linux.tar.gz' | head -n 1 || true)"
  if [[ -n "${sdk_tgz}" ]]; then
    log "Extraindo pacote do SDK NDI..."
    su - "${CURRENT_USER}" -c "tar -xf \"${sdk_tgz}\" -C \"${USER_HOME}\""
    local extracted_sh=""
    extracted_sh="$(find "${USER_HOME}" -maxdepth 1 -type f -name 'Install_NDI_SDK_v*_Linux.sh' | head -n 1 || true)"
    if [[ -n "${extracted_sh}" ]]; then
      chmod +x "${extracted_sh}"
      su - "${CURRENT_USER}" -c "\"${extracted_sh}\"" || true
    fi
    if [[ -d "${USER_HOME}/NDI SDK for Linux" ]]; then
      echo "${USER_HOME}/NDI SDK for Linux"
      return 0
    fi
  fi

  return 1
}

get_ndi_arch_dir() {
  case "${ARCH}" in
    x86_64) echo "x86_64-linux-gnu" ;;
    i686|i386) echo "i686-linux-gnu" ;;
    aarch64|arm64) echo "aarch64-rpi4-linux-gnueabi" ;;
    armv7l) echo "arm-rpi4-linux-gnueabihf" ;;
    *)
      err "Arquitetura não suportada automaticamente: ${ARCH}"
      exit 1
      ;;
  esac
}

install_ndi_sdk() {
  if ldconfig -p | grep -q libndi; then
    ok "SDK NDI já está instalado."
    return 0
  fi

  local sdk_dir=""
  sdk_dir="$(find_ndi_sdk_dir)" || {
    err "NDI SDK não encontrado."
    echo
    echo "Baixe o SDK oficial da NDI para Linux e coloque na HOME do usuário um destes itens:"
    echo "  - Install_NDI_SDK_v*_Linux.sh"
    echo "  - Install_NDI_SDK_v*_Linux.tar.gz"
    echo "  - pasta 'NDI SDK for Linux'"
    echo
    echo "Depois execute novamente o instalador."
    exit 1
  }

  local ndi_arch_dir=""
  ndi_arch_dir="$(get_ndi_arch_dir)"

  [[ -d "${sdk_dir}/lib/${ndi_arch_dir}" ]] || {
    err "Pasta de libs do SDK não encontrada para ${ndi_arch_dir}"
    exit 1
  }

  log "Instalando SDK NDI para ${ndi_arch_dir}..."
  cp -av "${sdk_dir}/lib/${ndi_arch_dir}"/libndi.so* /usr/local/lib/
  cp -av "${sdk_dir}/include"/Processing.NDI.* /usr/local/include/

  if [[ -d "${sdk_dir}/bin/${ndi_arch_dir}" ]]; then
    cp -av "${sdk_dir}/bin/${ndi_arch_dir}/"* /usr/local/bin/ || true
    chmod 755 /usr/local/bin/ndi-* 2>/dev/null || true
  fi

  echo "/usr/local/lib" > "${LD_CONF}"
  ldconfig

  ldconfig -p | grep -q libndi || {
    err "Falha ao registrar libndi no sistema."
    exit 1
  }

  ok "SDK NDI instalado com sucesso."
}

install_python_requirements() {
  if [[ -f "${TMP_DIR}/webui/requirements.txt" ]]; then
    log "Instalando dependências Python..."
    python3 -m pip install --break-system-packages -r "${TMP_DIR}/webui/requirements.txt" || \
    python3 -m pip install -r "${TMP_DIR}/webui/requirements.txt"
    ok "Dependências Python instaladas."
  fi
}

install_app_files() {
  log "Parando serviços antes de atualizar arquivos..."
  systemctl stop ndiplayer.service 2>/dev/null || true
  systemctl stop ndiplayer-web.service 2>/dev/null || true

  log "Limpando diretório da aplicação..."
  rm -rf "${APP_DIR}"
  mkdir -p "${APP_DIR}"
  mkdir -p "${APP_DIR}/webui"

  log "Instalando runtime..."
  cp -av "${TMP_DIR}/ndiplayer" "${APP_DIR}/"
  cp -av "${TMP_DIR}/ndiplayer-scan-sources" "${APP_DIR}/"
  cp -av "${TMP_DIR}/ndiplayer-setup" "${APP_DIR}/" 2>/dev/null || true
  cp -av "${TMP_DIR}/ndiplayer_setup" "${APP_DIR}/" 2>/dev/null || true
  cp -av "${TMP_DIR}/uninstall.sh" "${APP_DIR}/"
  cp -av "${TMP_DIR}/webui/." "${APP_DIR}/webui/"

  chown -R "${CURRENT_USER}:${CURRENT_USER}" "${APP_DIR}"
  chmod +x "${APP_DIR}/ndiplayer" 2>/dev/null || true
  chmod +x "${APP_DIR}/ndiplayer-scan-sources" 2>/dev/null || true
  chmod +x "${APP_DIR}/ndiplayer-setup" 2>/dev/null || true
  chmod +x "${APP_DIR}/ndiplayer_setup" 2>/dev/null || true
  chmod +x "${APP_DIR}/uninstall.sh" 2>/dev/null || true

  ok "Arquivos instalados em ${APP_DIR}"
}

install_default_config() {
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    cat > "${CONFIG_FILE}" <<EOF
NDI_SOURCE=""
EOF
    ok "Arquivo de configuração criado em ${CONFIG_FILE}"
  else
    warn "Config existente preservada: ${CONFIG_FILE}"
  fi
}

install_services() {
  log "Instalando serviços systemd..."

  cat > "${SERVICE_PLAYER}" <<EOF
[Unit]
Description=NDI Player
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${CURRENT_USER}
WorkingDirectory=${APP_DIR}
Environment=HOME=${USER_HOME}
Environment=XDG_RUNTIME_DIR=/run/user/${USER_UID}
ExecStart=${APP_DIR}/ndiplayer
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  cat > "${SERVICE_WEB}" <<EOF
[Unit]
Description=NDI Player Web UI
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}
ExecStart=/usr/bin/python3 ${APP_DIR}/webui/app.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable ndiplayer.service
  systemctl enable ndiplayer-web.service
  systemctl restart ndiplayer.service
  systemctl restart ndiplayer-web.service

  ok "Serviços instalados e reiniciados."
}

final_validation() {
  log "Executando validação final..."

  ldconfig -p | grep -q libndi && ok "libndi registrada."
  systemctl is-enabled ndiplayer.service >/dev/null && ok "ndiplayer.service habilitado."
  systemctl is-enabled ndiplayer-web.service >/dev/null && ok "ndiplayer-web.service habilitado."

  systemctl is-active ndiplayer.service >/dev/null \
    && ok "ndiplayer.service em execução." \
    || warn "ndiplayer.service não está ativo."

  systemctl is-active ndiplayer-web.service >/dev/null \
    && ok "ndiplayer-web.service em execução." \
    || warn "ndiplayer-web.service não está ativo."
}

main() {
  require_sudo
  detect_os
  install_system_dependencies
  download_runtime_files
  install_ndi_sdk
  install_python_requirements
  install_app_files
  install_default_config
  install_services
  final_validation

  echo
  ok "Instalação concluída."
  echo "Web UI: http://IP_DO_HOST:5000"
}

main "$@"
