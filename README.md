# NDI Player

Player NDI para Linux com instalação simplificada, Web UI e execução via systemd.

## Instalação

Antes de instalar, tenha o SDK oficial da NDI para Linux disponível na HOME do usuário. O instalador procura automaticamente por um destes itens:

- `Install_NDI_SDK_v*_Linux.sh`
- `Install_NDI_SDK_v*_Linux.tar.gz`
- pasta `NDI SDK for Linux`

Depois, execute:

```bash
curl -fsSL https://raw.githubusercontent.com/LiveToDie-BR/ndiplayer/v1.2.3/install.sh | sudo bash
