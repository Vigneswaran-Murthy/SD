#!/bin/bash

CONFIG_DIR="/etc/netplan"

# === Task Selection ===
read -p "Change root password? (y/n): " DO_PASSWORD
read -p "Change hostname? (y/n): " DO_HOSTNAME
read -p "Configure network interface? (y/n): " DO_NETWORK
read -p "Register with Canonical Livepatch or UA? (y/n): " DO_REGISTER
read -p "Install domain join packages? (y/n): " INSTALL_PACKAGES
read -p "Install and configure Chrony? (y/n): " CONFIGURE_CHRONY
read -p "Do you want to create user account for Madhusudhanan? (y/n): " CREATE_MADHU_USER

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

# === Network Configuration ===
if [[ "$DO_NETWORK" =~ ^[Yy]$ ]]; then
    echo -e "\nAvailable interfaces:"
    ip link show | awk -F: '/^[0-9]+: / {print $2}' | grep -vE 'lo|docker|veth'

    read -p "Enter interface name to configure (e.g., ens192): " IFACE
    CONFIG_FILE="${CONFIG_DIR}/${IFACE}_config.yaml"

    if [ -f "$CONFIG_FILE" ]; then
        BACKUP_FILE="${CONFIG_FILE}.bak_$(date +%F_%T)"
        echo "Backing up $CONFIG_FILE to $BACKUP_FILE..."
        sudo cp "$CONFIG_FILE" "$BACKUP_FILE"
        echo "Backup completed."
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
    echo "Netplan configuration written to $CONFIG_FILE. Applying changes..."
    sudo netplan apply
    echo "Network settings applied."
fi

# === Install Required Packages ===
if [[ "$INSTALL_PACKAGES" =~ ^[Yy]$ ]]; then
    echo "Installing domain join packages..."
    sudo apt update
    sudo apt install -y realmd sssd sssd-tools adcli krb5-user packagekit samba-common-bin libpam-mkhomedir
    echo "Packages installed successfully."
fi

# === Chrony Install + Config ===
if [[ "$CONFIGURE_CHRONY" =~ ^[Yy]$ ]]; then
    echo "Installing Chrony..."
    sudo apt-get update
    sudo apt install -y chrony
    echo "Chrony package installed."

    CHRONY_CONF="/etc/chrony/chrony.conf"
    BACKUP_CHRONY="${CHRONY_CONF}.bak_$(date +%F_%T)"
    echo "Backing up $CHRONY_CONF to $BACKUP_CHRONY..."
    sudo cp "$CHRONY_CONF" "$BACKUP_CHRONY"
    echo "Backup completed."

    echo "Writing new Chrony configuration..."
    sudo bash -c "cat > $CHRONY_CONF" <<EOF
server 10.86.1.1 iburst
server 10.86.2.1 iburst
EOF

    echo "Restarting and enabling Chrony service..."
    sudo systemctl restart chrony
    sudo systemctl enable chrony
    echo "Chrony is now configured and running."
fi

# === Madhusudhanan User Creation ===
if [[ "$CREATE_MADHU_USER" =~ ^[Yy]$ ]]; then
    echo "Creating xservice user for Madhusudhanan..."
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
            if [ $? -eq 0 ]; then
                echo "xservice user created and password set successfully."
            else
                echo "Failed to set password for xservice user."
            fi
            break
        fi
    done
fi

echo -e "\nAll selected tasks completed. Reboot if necessary."
