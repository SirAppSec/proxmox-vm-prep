#!/usr/bin/env bash
set -e

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

# ---------------------------
# Preparation Stage Functions
# ---------------------------

add_user_to_sudo() {
    if groups | grep -q '\bsudo\b'; then
        echo "✔ User $USER is already in sudo group"
        return
    fi

    read -rp "Add $USER to sudo group? [Y/n] " answer
    if [[ "${answer,,}" != "n" ]]; then
        if ! command -v sudo &>/dev/null; then
            echo "Installing sudo..."
            su -c "apt-get install -y sudo" root
        fi
        
        echo "Please enter root password to add $USER to sudo group:"
        su -c "usermod -aG sudo $USER; \
               echo '$USER ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/$USER" root
        
        echo -e "\nUser $USER added to sudo group. A logout/login may be required."
    fi
}

fix_apt_sources() {
    # Disable cdrom repository and set up proper sources
    echo "Configuring APT repositories..."

    # Install required keyring first
    if ! dpkg -l debian-archive-keyring >/dev/null 2>&1; then
        echo "Installing debian-archive-keyring..."
        sudo apt-get update -qq
        sudo apt-get install -y debian-archive-keyring
    fi

    # Comment out CD-ROM sources
    sudo sed -i '/^deb cdrom:/s/^/#/' /etc/apt/sources.list

    # Create modern repository configuration
    sudo tee /etc/apt/sources.list.d/debian-official.sources <<EOF
# Debian Bookworm base repository
Types: deb
URIs: https://deb.debian.org/debian
Suites: bookworm bookworm-updates bookworm-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# Debian Security updates
Types: deb
URIs: https://security.debian.org/debian-security
Suites: bookworm-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

    # Clean up legacy list files
    sudo rm -f /etc/apt/sources.list.d/*.list
}

install_packages() {
    fix_apt_sources  # This must come first
    
    echo "Updating package lists..."
    if ! sudo apt update -qq; then
        echo "Failed to update package lists. Please check your network connection."
        exit 1
    fi

    local to_install=()
    for pkg in "${PREP_PACKAGES[@]}"; do
        if ! dpkg -l | grep -q "^ii  ${pkg%% *} "; then
            to_install+=("$pkg")
        fi
    done

    if [ ${#to_install[@]} -gt 0 ]; then
        echo "Installing missing packages..."
        sudo apt install -y "${to_install[@]}"
    else
        echo "All required packages are already installed."
    fi
}
install_nvm() {
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
        echo "✔ nvm is already installed"
        return
    fi
    
    read -rp "Install nvm (Node Version Manager)? [Y/n] " answer
    if [[ "${answer,,}" != "n" ]]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        nvm install --lts
        npm install -g npm@latest
    fi
}

install_pipx() {
    if command -v pipx &>/dev/null; then
        echo "✔ pipx is already installed"
        return
    fi
    
    read -rp "Install pipx for Python application management? [Y/n] " answer
    if [[ "${answer,,}" != "n" ]]; then
        python3 -m pip install --user pipx
        python3 -m pipx ensurepath
        pipx install --include-deps ansible
        pipx install poetry pre-commit black
    fi
}

docker_postinstall() {
    if groups | grep -q docker; then
        echo "✔ Docker post-install already completed"
        return
    fi
    
    read -rp "Configure Docker for non-root user? [Y/n] " answer
    if [[ "${answer,,}" != "n" ]]; then
        sudo usermod -aG docker "$USER"
        echo "⚠️ You need to log out and back in for Docker group changes to take effect"
    fi
}

shell_customizations() {
    local aliases=(
        "alias ll='exa -alhF --git --group-directories-first'"
        "alias lt='exa -TF --git --ignore-glob=.git'"
        "alias cat='bat --paging=never'"
        "alias dps='docker ps --format \"table {{.ID}}\\t{{.Image}}\\t{{.Status}}\\t{{.Names}}\"'"
        "alias k='kubectl'"
    )

    for alias in "${aliases[@]}"; do
        if ! grep -qF "$alias" ~/.bashrc; then
            echo "$alias" >> ~/.bashrc
        fi
    done

    echo "✔ Shell customizations applied"
}

security_hardening() {
    read -rp "Enable basic security hardening? [Y/n] " answer
    if [[ "${answer,,}" != "n" ]]; then
        # Configure automatic security updates
        sudo apt install -y unattended-upgrades
        sudo dpkg-reconfigure -plow unattended-upgrades
        
        # Harden SSH configuration
        sudo sed -i -E 's/^#?(PasswordAuthentication|PermitRootLogin).*/\1 no/' /etc/ssh/sshd_config
        echo "⚠️ SSH password authentication and root login disabled"
    fi
}

# ------------------------
# Post-Clone Functions
# ------------------------

change_hostname() {
    read -rp "Enter new hostname: " new_hostname
    if [ -n "$new_hostname" ]; then
        sudo hostnamectl set-hostname "$new_hostname"
        sudo sed -i "/^127.0.1.1/c\127.0.1.1 $new_hostname" /etc/hosts
        echo "Hostname changed to $new_hostname"
    fi
}

regenerate_system_ids() {
    echo "Regenerating system identifiers..."
    
    # Reset machine-id
    sudo rm -f /etc/machine-id
    sudo systemd-machine-id-setup

    # Regenerate SSH host keys
    sudo rm -f /etc/ssh/ssh_host_*
    sudo dpkg-reconfigure -f noninteractive openssh-server
    sudo systemctl restart ssh

    echo "✔ System identifiers regenerated"
}

install_tailscale() {
    if command -v tailscale &>/dev/null; then
        echo "✔ Tailscale is already installed"
        return
    fi
    
    read -rp "Install Tailscale? [Y/n] " answer
    if [[ "${answer,,}" != "n" ]]; then
        curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
        curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
        sudo apt update
        sudo apt install -y tailscale
        
        read -rp "Enter your Tailscale auth key: " auth_key
        if [ -n "$auth_key" ]; then
            sudo tailscale up --auth-key "$auth_key"
            sudo systemctl enable tailscale
        else
            echo "⚠️ No auth key provided, run 'sudo tailscale up' manually when ready"
        fi
    fi
}

setup_firewall() {
    if sudo ufw status | grep -q "Status: active"; then
        echo "✔ UFW is already active"
    else
        read -rp "Enable UFW firewall? [Y/n] " answer
        if [[ "${answer,,}" != "n" ]]; then
            sudo ufw default deny incoming
            sudo ufw default allow outgoing
            sudo ufw allow OpenSSH
            sudo ufw allow in on tailscale0
            sudo ufw allow 41641/udp  # Tailscale
            sudo ufw --force enable
        fi
    fi
}

# ------------------------
# Main Script Logic
# ------------------------

prep_install() {
    echo "=== Running preparation phase ==="
    add_user_to_sudo
    install_packages
    
    for install in "${PREP_INSTALLATIONS[@]}"; do
        $install
    done
    
    echo -e "\nPreparation complete! Recommended actions:"
    echo "1. Log out and back in to apply group changes"
    echo "2. Review security settings in /etc/ssh/sshd_config"
    echo "3. This VM can now be turned into a template"
}

post_clone() {
    echo "=== Running post-clone phase ==="
    regenerate_system_ids
    change_hostname
    install_tailscale
    setup_firewall
    echo -e "\nPost-clone configuration complete! Recommended actions:"
    echo "1. Verify network connectivity with 'tailscale status'"
    echo "2. Check firewall rules with 'sudo ufw status'"
    echo "3. Rotate any application-specific secrets"
}

usage() {
    echo "Usage: $0 [--prep|--post-clone]"
    exit 1
}

# Check for arguments
if [ $# -eq 0 ]; then
    usage
fi

case "$1" in
    "--prep")
        prep_install
        ;;
    "--post-clone")
        post_clone
        ;;
    *)
        usage
        ;;
esac
