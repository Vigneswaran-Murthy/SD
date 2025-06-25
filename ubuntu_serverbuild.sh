#!/bin/bash

CONFIG_DIR="/etc/netplan"

# === Task Selection ===
echo -e "\n========== SELECT TASKS TO PERFORM =========="
read -p "Change hostname? (y/n): " DO_HOSTNAME
read -p "Change root password? (y/n): " DO_PASSWORD
read -p "Configure network interface? (y/n): " DO_NETWORK
read -p "Register with Canonical Livepatch or UA? (y/n): " DO_REGISTER
read -p "Remove sssd package if installed? (y/n): " REMOVE_SSSD
read -p "Install domain join packages? (y/n): " INSTALL_PACKAGES

# === Hostname Change ===
if [[ "$DO_HOSTNAME" =~ ^[Yy]$ ]]; then
    CURRENT_HOSTNAME=$(hostname)
    echo "Current Hostname: $CURRENT_HOSTNAME"

    read -p "Enter new hostname: " NEW_HOSTNAME
    if [ -z "$NEW_HOSTNAME" ]; then
        echo "Hostname cannot be empty. Skipping."
    elif [ "$NEW_HOSTNAME" == "$CURRENT_HOSTNAME" ]; then
        echo "New hostname is same as current. No changes made."
    else
        echo "Changing hostname to $NEW_HOSTNAME..."
        sudo hostnamectl set-hostname "$NEW_HOSTNAME"
        echo "$NEW_HOSTNAME" | sudo tee /etc/hostname > /dev/null
        echo "Hostname updated successfully."
    fi
fi

# === Root Password Change ===
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
            else
                echo "Failed to update root password."
            fi
            break
        fi
    done
fi

# === Network Configuration ===
if [[ "$DO_NETWORK" =~ ^[Yy]$ ]]; then
    BACKUP_FILE="${CONFIG_DIR}/01-netcfg.yaml.bak_$(date +%F_%T)"
    echo -e "\nBacking up current Netplan config to $BACKUP_FILE..."
    sudo cp ${CONFIG_DIR}/*.yaml "$BACKUP_FILE"
    echo "Backup completed."

    read -p "Enter interface name to configure (e.g., ens33): " IFACE
    read -p "Enter static IP (e.g., 192.168.1.100/24): " IPADDR
    read -p "Enter gateway IP: " GATEWAY
    read -p "Enter DNS servers (comma-separated): " DNS

    CONFIG_FILE="${CONFIG_DIR}/01-netcfg.yaml"
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
    echo "Netplan configuration written. Applying changes..."
    sudo netplan apply
    echo "Network settings applied."
fi

# === UA or Livepatch Registration ===
if [[ "$DO_REGISTER" =~ ^[Yy]$ ]]; then
    echo -e "\nCanonical UA / Livepatch Setup"
    read -p "Enter UA token (or press Enter to skip): " UA_TOKEN
    if [ -n "$UA_TOKEN" ]; then
        sudo ua attach "$UA_TOKEN"
        sudo ua enable livepatch
    else
        echo "No token entered. Skipping."
    fi
fi

# === Package Tasks ===
if [[ "$REMOVE_SSSD" =~ ^[Yy]$ ]]; then
    echo -e "\nChecking for sssd packages..."
    if dpkg -l | grep -q sssd; then
        echo "Removing sssd packages..."
        sudo apt remove --purge -y sssd*
    else
        echo "SSSD package not installed. Skipping removal."
    fi
fi

if [[ "$INSTALL_PACKAGES" =~ ^[Yy]$ ]]; then
    echo -e "\nInstalling required packages..."
    sudo apt update
    sudo apt install -y realmd sssd sssd-tools libnss-sss libpam-sss adcli samba-common-bin krb5-user packagekit

    echo -e "\n========== DOMAIN JOIN =========="
    read -p "Enter domain join command (or press Enter to skip): " JOIN_CMD
    if [ -n "$JOIN_CMD" ]; then
        read -s -p "Enter domain password: " JOIN_PASS
        echo
        echo "$JOIN_PASS" | eval "$JOIN_CMD"

        echo -e "\nVerifying domain join with 'realm list'..."
        realm list
    else
        echo "Domain join skipped."
    fi
fi

echo -e "\nAll selected tasks completed. Reboot if necessary."
