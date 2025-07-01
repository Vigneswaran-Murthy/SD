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
read -p "Configure SSSD? (y/n): " CONFIGURE_SSSD

...

# === SSSD Configuration ===
TASKS+=("SSSD Configuration")
TASK_STATUS["SSSD Configuration"]="⏭ Skipped"
if [[ "$CONFIGURE_SSSD" =~ ^[Yy]$ ]]; then
    SSSD_CONF="/etc/sssd/sssd.conf"
    sudo bash -c "cat > $SSSD_CONF" <<EOF
[sssd]
domains = corp.sandisk.com
config_file_version = 2
services = nss, pam
timeout = 150

[nss]
homedir_substring = /home
timeout = 150

[domain/corp.sandisk.com]
ad_domain = corp.sandisk.com
#ad_site = corp.sandisk.com
timeout = 150
krb5_realm = corp.sandisk.com
realmd_tags = manages-system joined-with-samba
cache_credentials = True
id_provider = ad
krb5_store_password_if_offline = True
krb5_auth_timeout = 30
default_shell = /bin/bash
ldap_id_mapping = True
use_fully_qualified_names = False
fallback_homedir = /home/%u
access_provider = ad
simple_allow_users =
simple_allow_groups = IT-Infra-Linux-Support-Flash,IT-Infra-Linux-Support
ad_gpo_ignore_unreadable = True
#ldap_user_principal = nosuchattr
subdomain_inherit = ignore_group_members, ldap_purge_cache_timeout
ignore_group_members = True
ldap_purge_cache_timeout = 0
ad_enable_gc = False
override_homedir = /home/%u
ldap_use_tokengroups = false
dns_resolver_timeout = 60
dyndns_update = false

[pam]
timeout = 150

[pac]
timeout = 150
EOF
    sudo chmod 600 $SSSD_CONF
    sudo systemctl restart sssd
    if [ $? -eq 0 ]; then
        TASK_STATUS["SSSD Configuration"]="✅ Completed"
    else
        TASK_STATUS["SSSD Configuration"]="❌ Failed"
    fi
fi

# === Final Summary ===
echo -e "\n\n========= TASK SUMMARY ========="
for task in "${TASKS[@]}"; do
    status="${TASK_STATUS[$task]}"
    case "$status" in
        "✅ Completed") echo -e "
