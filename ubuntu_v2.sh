#!/bin/bash

CONFIG_DIR="/etc/netplan"

# === Initialize Task Status ===
declare -A TASK_STATUS
TASKS=("Root Password Change" "Hostname Change" "Network Configuration" "Domain Join Packages" "Chrony Install" "User Creation (Madhusudhanan)" "Install .deb Packages")
for task in "${TASKS[@]}"; do
    TASK_STATUS["$task"]="⏭ Skipped"
done

# === Task Selection ===
read -p "Change root password? (y/n): " DO_PASSWORD
read -p "Change hostname? (y/n): " DO_HOSTNAME
read -p "Configure network interface? (y/n): " DO_NETWORK
read -p "Register with Canonical Livepatch or UA? (y/n): " DO_REGISTER
read -p "Install domain join packages? (y/n): " INSTALL_PACKAGES
read -p "Install and configure Chrony? (y/n): " CONFIGURE_CHRONY
read -p "Do you want to create user account for Madhusudhanan? (y/n): " CREATE_MADHU_USER
read -p "Install Check-MK agent and SecureConnector? (y/n): " INSTALL_DEBS

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
if [[ "$DO_HOSTNAME" =~ ^[Yy]$ ]]; then
    CURRENT_HOSTNAME=$(hostname)
    echo "Current Hostname: $CURRENT_HOSTNAME"

    read -p "Enter new hostname: " NEW_HOSTNAME
    if [ -z "$NEW_HOSTNAME" ]; then
        echo "Hostname cannot be empty. Skipping."
    elif [ "$NEW_HOSTNAME" == "$CURRENT_HOSTNAME" ]; then
        echo "New hostname is same as current. No changes made."
    else
        sudo hostnamectl set-hostname "$NEW_HOSTNAME" && echo "$NEW_HOSTNAME" | sudo tee /etc/hostname > /dev/null
        if [ $? -eq 0 ]; then
            echo "Hostname updated successfully."
            TASK_STATUS["Hostname Change"]="✅ Completed"
        else
            echo "Failed to change hostname."
            TASK_STATUS["Hostname Change"]="❌ Failed"
        fi
    fi
fi

# === Network Configuration ===
if [[ "$DO_NETWORK" =~ ^[Yy]$ ]]; then
    echo -e "\nAvailable interfaces:"
    ip link show | awk -F: '/^[0-9]+: / {print $2}' | grep -vE 'lo|docker|veth'

    read -p "Enter interface name to configure (e.g., ens192): " IFACE
    CONFIG_FILE="${CONFIG_DIR}/${IFACE}_config.yaml"

    [ -f "$CONFIG_FILE" ] && sudo cp "$CONFIG_FILE" "${CONFIG_FILE}.bak_$(date +%F_%T)"

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
    if [ $? -eq 0 ]; then
        echo "Network settings applied."
        TASK_STATUS["Network Configuration"]="✅ Completed"
    else
        TASK_STATUS["Network Configuration"]="❌ Failed"
    fi
fi

# === Install Required Packages ===
if [[ "$INSTALL_PACKAGES" =~ ^[Yy]$ ]]; then
    echo "Installing domain join packages..."
    sudo apt update && sudo apt install -y realmd sssd sssd-tools adcli krb5-user packagekit samba-common-bin libpam-mkhomedir
    if [ $? -eq 0 ]; then
        TASK_STATUS["Domain Join Packages"]="✅ Completed"
    else
        TASK_STATUS["Domain Join Packages"]="❌ Failed"
    fi
fi

# === Chrony Install + Config ===
if [[ "$CONFIGURE_CHRONY" =~ ^[Yy]$ ]]; then
    echo "Installing Chrony..."
    sudo apt-get update && sudo apt install -y chrony
    if [ $? -ne 0 ]; then
        TASK_STATUS["Chrony Install"]="❌ Failed"
    else
        CHRONY_CONF="/etc/chrony/chrony.conf"
        BACKUP_CHRONY="${CHRONY_CONF}.bak_$(date +%F_%T)"
        sudo cp "$CHRONY_CONF" "$BACKUP_CHRONY"

        sudo bash -c "cat > $CHRONY_CONF" <<EOF
server 10.86.1.1 iburst
server 10.86.2.1 iburst
EOF

        sudo systemctl restart chrony && sudo systemctl enable chrony
        if [ $? -eq 0 ]; then
            echo "Chrony is configured and running."
            TASK_STATUS["Chrony Install"]="✅ Completed"
        else
            TASK_STATUS["Chrony Install"]="❌ Failed"
        fi
    fi
fi

# === Madhusudhanan User Creation ===
if [[ "$CREATE_MADHU_USER" =~ ^[Yy]$ ]]; then
    sudo useradd -s /bin/bash -d /home/xservice/ -m -G sudo xservice
    while true; do
        read -s -p "Enter password for xservice user: " XSERVICE_PASS
        echo
        read -s -p "Confirm password: " XSERVICE_CONFIRM
        echo
        if [[ "$XSERVICE_PASS" != "$XSERVICE_CONFIRM" ]]; then
            echo "Passwords do not match. Try again."
        elif [[ -z "$XSERVICE_PASS" ]]; then
            echo "Password cannot be empty. Try again."
        else
            echo "xservice:$XSERVICE_PASS" | sudo chpasswd
            if [ $? -eq 0 ]; then
                echo "xservice user created."
                TASK_STATUS["User Creation (Madhusudhanan)"]="✅ Completed"
            else
                TASK_STATUS["User Creation (Madhusudhanan)"]="❌ Failed"
            fi
            break
        fi
    done
fi

# === Install .deb Packages from /tmp ===
if [[ "$INSTALL_DEBS" =~ ^[Yy]$ ]]; then
    AGENT_DEB="/tmp/check-mk-agent_2.0.0p1-1_all.deb"
    SECURE_DEB="/tmp/Ubuntu - 16-18-20-22-24 - 7.20.17306.deb"

    echo "Checking for .deb packages in /tmp..."
    DEB_SUCCESS=true

    if [[ -f "$AGENT_DEB" ]]; then
        sudo dpkg -i "$AGENT_DEB" || DEB_SUCCESS=false
    else
        echo "File not found: $AGENT_DEB"
        DEB_SUCCESS=false
    fi

    if [[ -f "$SECURE_DEB" ]]; then
        sudo dpkg -i "$SECURE_DEB" || DEB_SUCCESS=false
    else
        echo "File not found: $SECURE_DEB"
        DEB_SUCCESS=false
    fi

    if $DEB_SUCCESS; then
        TASK_STATUS["Install .deb Packages"]="✅ Completed"
    else
        TASK_STATUS["Install .deb Packages"]="❌ Failed"
    fi
fi

# === Summary Report ===
echo -e "\n=========== TASK SUMMARY ==========="
for task in "${TASKS[@]}"; do
    echo "${TASK_STATUS[$task]}  -  $task"
done
echo "===================================="
echo "All selected tasks processed. Reboot if necessary."
