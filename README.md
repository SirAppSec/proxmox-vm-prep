# proxmox-vm-prep
Preperatory scripts to install on pre-cloned and cloned vms
```bash
wget https://raw.githubusercontent.com/SirAppSec/proxmox-vm-prep/refs/heads/main/proxmox-vm-prep.sh
wget -O proxmox-vm-prep.sh https://tinyurl.com/sirappsec-vm-prep
```
## Install on pre-cloned vms
```
chmod +x proxmopx-vm-prep.sh
./proxmox-vm-prep.sh --prep
```
## Post-clone
```
./proxmox-vm-prep.sh --post-clone
```
before saving the template : `sudo apt clean` and `rm -r /tmp`

### Currently installls:
```bash

PREP_PACKAGES=(
    # Base system
    firmware-linux-nonfree aptitude software-properties-common
    apt-transport-https ca-certificates gnupg2
    
    # Core tools
    rsync curl wget git openssh-client bash-completion
    htop neovim jq tree net-tools dnsutils ncdu
    unzip zip mlocate make build-essential
    
    # Dev environments
    docker.io docker-compose python3 python3-pip python3-venv
    nodejs npm rustc cargo
    
    # Security & Management
    ufw fail2ban ansible
    
    # Optional tools
    tmux zsh fzf ripgrep bat exa
)

PREP_INSTALLATIONS=(
    nvm pipx docker_postinstall
    shell_customizations security_hardening
)

```
