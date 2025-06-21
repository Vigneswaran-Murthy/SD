#!/bin/bash

CONFIG_DIR="/etc/sysconfig/network-scripts"

# === Task Selection ===
echo -e "\n========== SELECT TASKS TO PERFORM =========="
read -p "Change hostname? (y/n): " DO_HOSTNAME
read -p "Change root password? (y/n): " DO_PASSWORD
read -p "Configure network interface? (y/n): " DO_NETWORK
read -p "Register with Red Hat Satellite? (y/n): " DO_REGISTER
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
    BACKUP_DIR="${CONFIG_DIR}_backup_$(date +%F_%T)"
    echo -e "\nBacking up $CONFIG_DIR to $BACKUP_DIR..."
    sudo cp -r "$CONFIG_DIR" "$BACKUP_DIR"
    echo "Backup completed."

    echo -e "\nAvailable network interface config files:"
    ls "$CONFIG_DIR"/ifcfg-* | grep -vE 'ifcfg-lo|ifcfg-.*:.*'

    read -p "Enter interface name to configure (e.g., ens192): " IFACE
    CONFIG_FILE="$CONFIG_DIR/ifcfg-$IFACE"

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Config file $CONFIG_FILE does not exist. Skipping network config."
    else
        sudo cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
        echo "Backup of $CONFIG_FILE saved as ${CONFIG_FILE}.bak"

        # Remove UUID if present
        sudo sed -i '/^UUID=/d' "$CONFIG_FILE"

        # BOOTPROTO
        grep -q '^BOOTPROTO=dhcp' "$CONFIG_FILE" && \
            sudo sed -i 's/^BOOTPROTO=dhcp/BOOTPROTO=static/' "$CONFIG_FILE"
        grep -q '^BOOTPROTO=' "$CONFIG_FILE" || echo "BOOTPROTO=static" | sudo tee -a "$CONFIG_FILE" > /dev/null

        # Get IP settings
        read -p "Enter IPADDR: " IPADDR
        read -p "Enter NETMASK: " NETMASK
        read -p "Enter GATEWAY: " GATEWAY
        read -p "Enter DNS1: " DNS1
        read -p "Enter DNS2: " DNS2
        read -p "Enter DOMAIN: " DOMAIN

        # Remove existing values
        sudo sed -i '/^IPADDR=/d;/^NETMASK=/d;/^GATEWAY=/d;/^DNS1=/d;/^DNS2=/d;/^DOMAIN=/d' "$CONFIG_FILE"

        # Append new values
        {
            echo "IPADDR=$IPADDR"
            echo "NETMASK=$NETMASK"
            echo "GATEWAY=$GATEWAY"
            echo "DNS1=$DNS1"
            echo "DNS2=$DNS2"
            echo "DOMAIN=$DOMAIN"
        } | sudo tee -a "$CONFIG_FILE" > /dev/null

        echo "Network configuration updated in $CONFIG_FILE"

        # Restart NetworkManager and check status
        echo -e "\nRestarting NetworkManager..."
        sudo systemctl restart NetworkManager
        echo "NetworkManager status:"
        sudo systemctl status NetworkManager --no-pager
    fi
fi

# === Satellite Registration ===
if [[ "$DO_REGISTER" =~ ^[Yy]$ ]]; then
    echo -e "\n========== SATELLITE REGISTRATION =========="

    read -p "Enter RHEL version (7/8/9): " RHEL_VER
    read -p "Is this environment prod or non-prod? (prod/non-prod): " ENV_TYPE
    read -p "Enter activation key manually: " ACTIVATION_KEY

    if [ -n "$ACTIVATION_KEY" ]; then
        echo "Registering system using activation key: $ACTIVATION_KEY"
        sudo subscription-manager register --org="your_org_name" --activationkey="$ACTIVATION_KEY"
        if [ $? -eq 0 ]; then
            echo "Successfully registered with Satellite."
        else
            echo "Registration failed. Check Satellite settings or network."
        fi
    fi
fi

# === Package Tasks ===
if [[ "$REMOVE_SSSD" =~ ^[Yy]$ ]]; then
    echo -e "\nChecking for sssd packages..."
    if rpm -q sssd &>/dev/null; then
        echo "Removing sssd packages..."
        sudo yum remove -y sssd*
    else
        echo "SSSD package not installed. Skipping removal."
    fi
fi

if [[ "$INSTALL_PACKAGES" =~ ^[Yy]$ ]]; then
    echo -e "\nInstalling required packages..."
    sudo yum install -y realmd sssd oddjob-mkhomedir adcli samba-common samba-common-tools krb5-workstation authselect-compat

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
