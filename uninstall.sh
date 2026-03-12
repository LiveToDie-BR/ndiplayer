#!/usr/bin/env bash
set -e

echo "========================================"
echo " NDI Player Uninstall"
echo "========================================"

if [ "$(id -u)" -ne 0 ]; then
  echo "Este script precisa ser executado com sudo."
  echo "Use: sudo bash uninstall.sh"
  exit 1
fi

systemctl stop ndiplayer.service >/dev/null 2>&1 || true
systemctl disable ndiplayer.service >/dev/null 2>&1 || true

rm -f /usr/local/bin/ndiplayer
rm -f /usr/local/bin/ndiplayer-setup
rm -f /etc/systemd/system/ndiplayer.service

systemctl daemon-reload

echo
echo "Arquivos removidos."
echo
echo "Se desejar, remova tambem a configuracao manualmente:"
echo "  sudo rm -f /etc/ndiplayer.conf"
echo
echo "Desinstalacao concluida."
