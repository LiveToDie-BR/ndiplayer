# NDI Player

Decoder NDI simples para Linux.

Projeto criado para transformar um Mini PC com Debian em um decoder NDI dedicado, ideal para igrejas, eventos e broadcast.

## Recursos

- Debian 12 minimal
- Funcionamento sem interface gráfica
- Saída HDMI
- Áudio ALSA
- Descoberta automática de fontes NDI
- Interface Web para controle
- Serviços systemd
- Web UI em porta 8080

## Requisito obrigatório

Antes de instalar, é necessário baixar e instalar o NDI SDK oficial:

https://ndi.video/for-developers/ndi-sdk/

## Instalação

```bash
git clone https://github.com/LiveToDie-BR/ndiplayer.git
cd ndiplayer
sudo bash install.sh
