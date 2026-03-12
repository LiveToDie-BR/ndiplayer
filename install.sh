#!/usr/bin/env bash
set -e

echo "========================================"
echo " NDI Player Installer"
echo "========================================"

if [ "$(id -u)" -ne 0 ]; then
  echo "Este instalador precisa ser executado com sudo."
  echo "Use: sudo bash install.sh"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
INSTALL_BIN_DIR="/usr/local/bin"
SYSTEMD_DIR="/etc/systemd/system"

if [ ! -f "$SCRIPT_DIR/src/ndiplayer.cpp" ]; then
  echo "Arquivo src/ndiplayer.cpp nao encontrado."
  exit 1
fi

if [ ! -f "$SCRIPT_DIR/src/ndiplayer_setup.cpp" ]; then
  echo "Arquivo src/ndiplayer_setup.cpp nao encontrado."
  exit 1
fi

if [ ! -f "$SCRIPT_DIR/systemd/ndiplayer.service" ]; then
  echo "Arquivo systemd/ndiplayer.service nao encontrado."
  exit 1
fi

echo
echo "[1/7] Instalando dependencias..."
apt update
apt install -y build-essential git cmake libsdl2-dev libasound2-dev

echo
echo "[2/7] Verificando SDK NDI..."

NDI_INCLUDE_DIR_DEFAULT="/home/audio_asus/NDI SDK for Linux/include"
NDI_LIB_DIR_DEFAULT="/home/audio_asus/NDI SDK for Linux/lib/x86_64-linux-gnu"

NDI_INCLUDE_DIR="${NDI_INCLUDE_DIR:-$NDI_INCLUDE_DIR_DEFAULT}"
NDI_LIB_DIR="${NDI_LIB_DIR:-$NDI_LIB_DIR_DEFAULT}"

if [ ! -f "$NDI_INCLUDE_DIR/Processing.NDI.Lib.h" ]; then
  echo "Header NDI nao encontrado em:"
  echo "  $NDI_INCLUDE_DIR"
  echo
  echo "Defina o caminho correto assim:"
  echo "  sudo NDI_INCLUDE_DIR=\"/caminho/include\" NDI_LIB_DIR=\"/caminho/lib\" bash install.sh"
  exit 1
fi

if [ ! -f "$NDI_LIB_DIR/libndi.so" ] && [ ! -f "$NDI_LIB_DIR/libndi.so.6" ]; then
  echo "Biblioteca NDI nao encontrada em:"
  echo "  $NDI_LIB_DIR"
  echo
  echo "Defina o caminho correto assim:"
  echo "  sudo NDI_INCLUDE_DIR=\"/caminho/include\" NDI_LIB_DIR=\"/caminho/lib\" bash install.sh"
  exit 1
fi

echo
echo "[3/7] Preparando build..."
mkdir -p "$BUILD_DIR"

echo
echo "[4/7] Compilando ndiplayer_setup..."
g++ "$SCRIPT_DIR/src/ndiplayer_setup.cpp" -o "$BUILD_DIR/ndiplayer_setup" \
  -I"$NDI_INCLUDE_DIR" \
  -L"$NDI_LIB_DIR" \
  -lndi

echo
echo "[5/7] Compilando ndiplayer..."
g++ "$SCRIPT_DIR/src/ndiplayer.cpp" -o "$BUILD_DIR/ndiplayer" \
  -I"$NDI_INCLUDE_DIR" \
  -L"$NDI_LIB_DIR" \
  -lndi -lSDL2 -lasound -lpthread

echo
echo "[6/7] Instalando binarios..."
systemctl stop ndiplayer.service >/dev/null 2>&1 || true

cp "$BUILD_DIR/ndiplayer" "$INSTALL_BIN_DIR/ndiplayer"
cp "$BUILD_DIR/ndiplayer_setup" "$INSTALL_BIN_DIR/ndiplayer-setup"

chmod +x "$INSTALL_BIN_DIR/ndiplayer"
chmod +x "$INSTALL_BIN_DIR/ndiplayer-setup"

echo
echo "[7/7] Instalando servico systemd..."
cp "$SCRIPT_DIR/systemd/ndiplayer.service" "$SYSTEMD_DIR/ndiplayer.service"

systemctl daemon-reload
systemctl enable ndiplayer.service

echo
echo "========================================"
echo " Instalacao concluida"
echo "========================================"
echo
echo "Agora execute:"
echo "  sudo /usr/local/bin/ndiplayer-setup"
echo
echo "Depois inicie o servico com:"
echo "  sudo systemctl start ndiplayer.service"
echo
echo "Para ver o status:"
echo "  systemctl status ndiplayer.service"
echo
