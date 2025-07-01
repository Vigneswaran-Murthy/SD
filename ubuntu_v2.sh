#!/bin/bash

CONFIG_DIR="/etc/netplan"
TASKS=()
declare -A TASK_STATUS

# === Task Selection ===
read -p "Change root password? (y/n): " DO_PASSWORD
read -p "Change hostname? (y/n): " DO_HOSTNAME
read -p "Configure network interface? (y/n): " DO_NETWORK
read -p "Register with Canonical Livepatch or UA? (y/n): " DO_REGISTER
read -p "Install domain join packages? (y/n): " INSTALL_PACKAGES
read -p "Join system to AD domain corp.sandisk.com? (y/n): " JOIN_DOMAIN
read -p "Install and configure Chrony? (y/n): " CONFIGURE_CHRONY
read -p "Do you want to create user account for Madhusudhanan? (y/n): " CREATE_MADHU_USER
read -p "Install Check-MK agent and SecureConnector? (y/n): " INSTALL_DEBS
read -p "Modify SSHD config for GSSAPIAuthentication and reload SSH? (y/n): " CONFIGURE_SSH

# === Root Password Change ===
TASKS+=("Root Password Change")
TASK_STATUS["Root Password Change"]="⏭ Skipped"
if [[ "$DO_PASSWORD" =~ ^[Yy]$ ]]; then
    echo -e "\nChange root password:"
    while true; do
        read -t 60 -s -p "Enter new password for root (or press 's' to skip): " PASSWORD
        echo
        if [[ "$PASSWORD" == "s" ]]; then
            echo "Password change skipped by user."
            break
        fi
        read -t 60 -s -p "Confirm new password: " CONFIRM_PASSWORD
        echo
        if [ "$PASSWORD" != "$CONFIRM_PASSWORD" ]; then
            echo "Passwords do not match. Try again."
        elif [ -z "$PASSWORD" ]; then
            echo "Password cannot be empty. Try again."
        else
            echo "root:$PASSWORD" | sudo chpasswd
            if [ $? -eq 0 ]; then
                echo "Root password updated successfully."
                TASK_STATUS["Root Password Change"]="✅ Completed"
            else
                echo "Failed to update root password."
                TASK_STATUS["Root Password Change"]="❌ Failed"
            fi
            break
        fi
    done
fi

# === Hostname Change ===
TASKS+=("Hostname Change")
TASK_STATUS["Hostname Change"]="⏭ Skipped"
if [[ "$DO_HOSTNAME" =~ ^[Yy]$ ]]; then
    CURRENT_HOSTNAME=$(hostname)
    read -p "Enter new hostname: " NEW_HOSTNAME
    if [ -z "$NEW_HOSTNAME" ]; then
        echo "Hostname cannot be empty. Skipping."
    elif [ "$NEW_HOSTNAME" == "$CURRENT_HOSTNAME" ]; then
        echo "New hostname is same as current. No changes made."
    else
        sudo hostnamectl set-hostname "$NEW_HOSTNAME"
        echo "$NEW_HOSTNAME" | sudo tee /etc/hostname > /dev/null
        echo "Hostname updated successfully."
        TASK_STATUS["Hostname Change"]="✅ Completed"
    fi
fi

# === Network Configuration ===
TASKS+=("Network Configuration")
TASK_STATUS["Network Configuration"]="⏭ Skipped"
if [[ "$DO_NETWORK" =~ ^[Yy]$ ]]; then
    ip link show | awk -F: '/^[0-9]+: / {print $2}' | grep -vE 'lo|docker|veth'
    read -p "Enter interface name to configure (e.g., ens192): " IFACE
    CONFIG_FILE="${CONFIG_DIR}/${IFACE}_config.yaml"
    if [ -f "$CONFIG_FILE" ]; then
        BACKUP_FILE="${CONFIG_FILE}.bak_$(date +%F_%T)"
        sudo cp "$CONFIG_FILE" "$BACKUP_FILE"
    fi
    read -p "Enter static IP (e.g., 192.168.1.100/24): " IPADDR
    read -p "Enter gateway IP: " GATEWAY
    read -p "Enter DNS servers (comma-separated): " DNS
    sudo bash -c "cat > $CONFIG_FILE" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      addresses: [$IPADDR]
      gateway4: $GATEWAY
      nameservers:
        addresses: [$DNS]
EOF
    sudo netplan apply
    TASK_STATUS["Network Configuration"]="✅ Completed"
fi

# === Domain Join Package Installation ===
TASKS+=("Domain Join Package Installation")
TASK_STATUS["Domain Join Package Installation"]="⏭ Skipped"
if [[ "$INSTALL_PACKAGES" =~ ^[Yy]$ ]]; then
    sudo apt update
    sudo apt install -y realmd sssd sssd-tools adcli krb5-user packagekit samba-common-bin libpam-mkhomedir
    TASK_STATUS["Domain Join Package Installation"]=$([[ $? -eq 0 ]] && echo "✅ Completed" || echo "❌ Failed")
fi

# === AD Domain Join ===
TASKS+=("AD Domain Join")
TASK_STATUS["AD Domain Join"]="⏭ Skipped"
if [[ "$JOIN_DOMAIN" =~ ^[Yy]$ ]]; then
    sudo realm join corp.sandisk.com -U 7400428_sa --computer-ou="OU=Infra,OU=Prod,OU=NIX,OU=UNIX,OU=ExternalSystems,OU=Servers,DC=corp,DC=sandisk,DC=com"
    TASK_STATUS["AD Domain Join"]=$([[ $? -eq 0 ]] && echo "✅ Completed" || echo "❌ Failed")
fi

# === Chrony Configuration ===
TASKS+=("Chrony Install + Config")
TASK_STATUS["Chrony Install + Config"]="⏭ Skipped"
if [[ "$CONFIGURE_CHRONY" =~ ^[Yy]$ ]]; then
    sudo apt-get update
    sudo apt install -y chrony
    CHRONY_CONF="/etc/chrony/chrony.conf"
    BACKUP_CHRONY="${CHRONY_CONF}.bak_$(date +%F_%T)"
    sudo cp "$CHRONY_CONF" "$BACKUP_CHRONY"
    sudo bash -c "cat > $CHRONY_CONF" <<EOF
server 10.86.1.1 iburst
server 10.86.2.1 iburst
EOF
    sudo systemctl restart chrony
    sudo systemctl enable chrony
    TASK_STATUS["Chrony Install + Config"]="✅ Completed"
fi

# === Create xservice User ===
TASKS+=("xservice User Creation")
TASK_STATUS["xservice User Creation"]="⏭ Skipped"
if [[ "$CREATE_MADHU_USER" =~ ^[Yy]$ ]]; then
    sudo useradd -s /bin/bash -d /home/xservice/ -m -G sudo xservice
    while true; do
        read -s -p "Enter password for xservice user: " XSERVICE_PASS
        echo
        read -s -p "Confirm password: " XSERVICE_CONFIRM
        echo
        if [[ "$XSERVICE_PASS" != "$XSERVICE_CONFIRM" ]]; then
            echo "Passwords do not match. Please try again."
        elif [[ -z "$XSERVICE_PASS" ]]; then
            echo "Password cannot be empty. Please try again."
        else
            echo "xservice:$XSERVICE_PASS" | sudo chpasswd
            TASK_STATUS["xservice User Creation"]=$([[ $? -eq 0 ]] && echo "✅ Completed" || echo "❌ Failed")
            break
        fi
    done
fi

# === Install .deb Packages from /tmp ===
TASKS+=("Check-MK agent and SecureConnector")
TASK_STATUS["Check-MK agent and SecureConnector"]="⏭ Skipped"
if [[ "$INSTALL_DEBS" =~ ^[Yy]$ ]]; then
    AGENT_DEB="/tmp/check-mk-agent_2.0.0p1-1_all.deb"
    SECURE_DEB="/tmp/Ubuntu - 16-18-20-22-24 - 7.20.17306.deb"
    [[ -f "$AGENT_DEB" ]] && sudo dpkg -i "$AGENT_DEB"
    [[ -f "$SECURE_DEB" ]] && sudo dpkg -i "$SECURE_DEB"
    TASK_STATUS["Check-MK agent and SecureConnector"]="✅ Completed"
fi

# === SSH GSSAPI Configuration ===
TASKS+=("SSH GSSAPI Configuration")
TASK_STATUS["SSH GSSAPI Configuration"]="⏭ Skipped"
if [[ "$CONFIGURE_SSH" =~ ^[Yy]$ ]]; then
    SSH_CONFIG="/etc/ssh/ssh_config"
    DATE_SUFFIX=$(date +"%d%b%Y" | tr '[:lower:]' '[:upper:]')
    BACKUP_FILE="/etc/ssh/sshd_config_bkp_$DATE_SUFFIX"
    sudo cp "$SSH_CONFIG" "$BACKUP_FILE"
    sudo sed -i 's/^#\?GSSAPIAuthentication.*/GSSAPIAuthentication no/' "$SSH_CONFIG"
    if grep -q "^GSSAPICleanupCredentials" "$SSH_CONFIG"; then
        sudo sed -i 's/^#\?GSSAPICleanupCredentials.*/GSSAPICleanupCredentials yes/' "$SSH_CONFIG"
    else
        echo "GSSAPICleanupCredentials yes" | sudo tee -a "$SSH_CONFIG" > /dev/null
    fi
    sudo systemctl reload ssh.service
    TASK_STATUS["SSH GSSAPI Configuration"]=$([[ $? -eq 0 ]] && echo "✅ Completed" || echo "❌ Failed")
fi

# === Final Summary ===
echo -e "\n\n========= TASK SUMMARY ========="
for task in "${TASKS[@]}"; do
    echo "${TASK_STATUS[$task]}  $task"
done
echo -e "================================"
echo -e "\nAll selected tasks processed. Reboot if necessary."
