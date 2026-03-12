# NDI Player for Linux

Player NDI dedicado para Debian, pensado para uso em igrejas e ambientes de exibição fixa.

## Recursos

- Descoberta de sources NDI
- Setup interativo em terminal
- Seleção de source NDI
- Seleção de saída de áudio ALSA
- Vídeo via SDL em tela local
- Áudio via ALSA/HDMI
- Configuração persistente em `/etc/ndiplayer.conf`
- Inicialização automática com systemd
- Reconexão prática quando a source volta

## Estrutura

- `src/ndiplayer.cpp` → player principal
- `src/ndiplayer_setup.cpp` → setup interativo
- `systemd/ndiplayer.service` → serviço systemd

## Dependências

No Debian:

```bash
sudo apt update
sudo apt install -y build-essential git cmake libsdl2-dev libsdl2-ttf-dev libasound2-dev
