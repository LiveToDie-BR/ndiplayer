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
- `install.sh` → instalador
- `uninstall.sh` → desinstalador

## Dependências

O projeto depende do SDK oficial da NDI instalado localmente.

Exemplo de caminho usado durante o desenvolvimento:

- Include: `/home/audio_asus/NDI SDK for Linux/include`
- Lib: `/home/audio_asus/NDI SDK for Linux/lib/x86_64-linux-gnu`

## Instalação

No Debian:

```bash
git clone https://github.com/LiveToDie-BR/ndiplayer.git
cd ndiplayer
sudo bash install.sh
