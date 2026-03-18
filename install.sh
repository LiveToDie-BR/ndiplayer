#!/usr/bin/env bash

set -e

echo
echo "========================================"
echo " NDI Player Installer"
echo "========================================"

if [ "$(id -u)" -ne 0 ]; then
  echo "Execute com sudo:"
  echo "  sudo bash install.sh"
  exit 1
fi

PROJECT_DIR="$(pwd)"
INSTALL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"

echo
echo "[1/10] Instalando dependencias..."

apt update

apt install -y \
build-essential \
cmake \
libsdl2-dev \
libasound2-dev \
python3 \
python3-pip \
git \
avahi-daemon \
avahi-utils

echo
echo "[2/10] Ativando mDNS (Avahi)..."

systemctl enable avahi-daemon
systemctl start avahi-daemon

echo
echo "[3/10] Instalando Flask..."

pip3 install -r webui/requirements.txt --break-system-packages

echo
echo "[4/10] Procurando SDK NDI..."

if [ -n "${NDI_INCLUDE_DIR:-}" ] && [ -n "${NDI_LIB_DIR:-}" ]; then
    echo "Usando caminhos informados manualmente."
else
    NDI_HEADER="$(find /home -type f -name Processing.NDI.Lib.h 2>/dev/null | head -n 1 || true)"
    NDI_LIB_FILE="$(find /home -type f \( -name 'libndi.so' -o -name 'libndi.so.6' -o -name 'libndi.so.*' \) 2>/dev/null | grep x86_64-linux-gnu | head -n 1 || true)"

    if [ -n "$NDI_HEADER" ]; then
        NDI_INCLUDE_DIR="$(dirname "$NDI_HEADER")"
    fi

    if [ -n "$NDI_LIB_FILE" ]; then
        NDI_LIB_DIR="$(dirname "$NDI_LIB_FILE")"
    fi
fi

if [ -z "${NDI_INCLUDE_DIR:-}" ] || [ ! -f "$NDI_INCLUDE_DIR/Processing.NDI.Lib.h" ]; then
    echo
    echo "ERRO: Header do SDK NDI nao encontrado."
    echo
    echo "Instale o NDI SDK oficial:"
    echo "https://ndi.video/for-developers/ndi-sdk/"
    echo
    echo "Ou informe manualmente:"
    echo "sudo env NDI_INCLUDE_DIR=\"/caminho/include\" NDI_LIB_DIR=\"/caminho/lib\" bash install.sh"
    exit 1
fi

if [ -z "${NDI_LIB_DIR:-}" ] || { [ ! -f "$NDI_LIB_DIR/libndi.so" ] && [ ! -f "$NDI_LIB_DIR/libndi.so.6" ] && ! ls "$NDI_LIB_DIR"/libndi.so.* >/dev/null 2>&1; }; then
    echo
    echo "ERRO: Biblioteca NDI nao encontrada."
    echo
    echo "Instale o NDI SDK oficial."
    echo
    echo "Ou informe manualmente:"
    echo "sudo env NDI_INCLUDE_DIR=\"/caminho/include\" NDI_LIB_DIR=\"/caminho/lib\" bash install.sh"
    exit 1
fi

echo
echo "NDI detectado:"
echo "Include: $NDI_INCLUDE_DIR"
echo "Lib:     $NDI_LIB_DIR"

echo
echo "[5/10] Compilando ndiplayer..."

g++ src/ndiplayer.cpp -o ndiplayer \
  -I"$NDI_INCLUDE_DIR" \
  -L"$NDI_LIB_DIR" \
  -lndi \
  -lSDL2 \
  -lasound \
  -lpthread \
  -O3

echo
echo "[6/10] Compilando ndiplayer-setup..."

g++ src/ndiplayer_setup.cpp -o ndiplayer-setup \
  -I"$NDI_INCLUDE_DIR" \
  -L"$NDI_LIB_DIR" \
  -lndi \
  -O2

echo
echo "[7/10] Compilando ndiplayer-scan-sources..."

g++ src/ndiplayer_scan_sources.cpp -o ndiplayer-scan-sources \
  -I"$NDI_INCLUDE_DIR" \
  -L"$NDI_LIB_DIR" \
  -lndi \
  -O2

echo
echo "[8/10] Instalando binarios..."

systemctl stop ndiplayer.service >/dev/null 2>&1 || true
systemctl stop ndiplayer-web.service >/dev/null 2>&1 || true

cp ndiplayer /usr/local/bin/
cp ndiplayer-setup /usr/local/bin/
cp ndiplayer-scan-sources /usr/local/bin/

chmod +x /usr/local/bin/ndiplayer
chmod +x /usr/local/bin/ndiplayer-setup
chmod +x /usr/local/bin/ndiplayer-scan-sources

echo
echo "Registrando biblioteca NDI no linker..."

echo "$NDI_LIB_DIR" > /etc/ld.so.conf.d/ndiplayer-ndi.conf
ldconfig

echo
echo "[9/10] Instalando Web UI..."

mkdir -p /opt/ndiplayer-web
mkdir -p /opt/ndiplayer-web/templates
mkdir -p /opt/ndiplayer-web/static

cp webui/app.py /opt/ndiplayer-web/
cp webui/templates/index.html /opt/ndiplayer-web/templates/
cp webui/static/style.css /opt/ndiplayer-web/static/

echo
echo "[10/10] Instalando services..."

sed "s|__NDIPLAYER_USER__|$INSTALL_USER|g" systemd/ndiplayer.service > /etc/systemd/system/ndiplayer.service
cp systemd/ndiplayer-web.service /etc/systemd/system/

systemctl daemon-reload

systemctl enable ndiplayer.service
systemctl enable ndiplayer-web.service

systemctl restart ndiplayer-web.service

echo
echo "========================================"
echo " Instalacao concluida!"
echo "========================================"

echo
echo "Usuario detectado para o player: $INSTALL_USER"

echo
echo "Configure o decoder com:"
echo "  sudo ndiplayer-setup"

echo
echo "Depois inicie o player:"
echo "  sudo systemctl start ndiplayer.service"

echo
echo "Web UI:"
echo "  http://IP_DO_DECODER:8080"

echo
echo "Teste de descoberta NDI:"
echo "  ndiplayer-scan-sources"
