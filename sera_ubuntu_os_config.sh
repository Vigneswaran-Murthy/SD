
##without email ##
##standard_os_config.sh #
#!/bin/bash
cd /data/automation/os_config/
SERVERS_FILE="servers.txt"
SCRIPT="ubuntu_os_config.sh"
LOGFILE="provisioning.log"
cat servers.txt >> master_inventory_ubuntu
echo "Provisioning started at $(date)" > "$LOGFILE"
echo "----------------------------------------" >> "$LOGFILE"
# Requires root privileges
if [[ $EUID -ne 0 ]]; then
  echo "***** Please run this script as root to change the system time zone *****"
  exit 1
fi


if [ ! -f "$SERVERS_FILE" ]; then
  echo "***** Error: $SERVERS_FILE not found." | tee -a "$LOGFILE *****"
  exit 1
fi

#cat $SERVERS_FILE|while read -r HOST; do
for HOST in `cat  $SERVERS_FILE`
do
  if [ -z "$HOST" ]; then
    continue
  fi

  echo "=== [$HOST] Starting provisioning... ===" | tee -a "$LOGFILE"
  echo "$HOST" > /tmp/pws

  # Test SSH connection
  ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "echo SSH connection successful" 2>/dev/null
  if [ $? -ne 0 ]; then
    echo "=== [$HOST] SSH connection failed. Skipping ===" | tee -a "$LOGFILE"
    continue
  fi

  # Copy the provisioning script and other required files
  scp "$SCRIPT" "$HOST:/tmp/$SCRIPT" >> "$LOGFILE" 2>&1
  scp /root/important_package/team.keys $HOST:/tmp/ssh_keys.txt >> "$LOGFILE" 2>&1
  scp /root/important_package/falcon_package/falcon-sensor_7.20.17306.deb $HOST:/tmp >> "$LOGFILE" 2>&1
  scp /tmp/pws $HOST:/tmp/servers.txt >> "$LOGFILE" 2>&1
  if [ $? -ne 0 ]; then
    echo "=== [$HOST] Failed to copy needed files. Skipping ===" | tee -a "$LOGFILE"
    continue
  fi

  # Execute the script remotely
  ssh -o StrictHostKeyChecking=no  "$HOST" "bash /tmp/$SCRIPT" >> "$LOGFILE" 2>&1
  if [ $? -eq 0 ]; then
    echo "=== [$HOST] Provisioning successful at $(date)===" | tee -a "$LOGFILE"
  else
    echo "=== [$HOST] Provisioning failed ===" | tee -a "$LOGFILE"
  fi

done




#####

#!/bin/bash
# === Linux Provisioning Script ===
# Supports: Ubuntu OS
# Features: Logging, Error Handling, Email Alerts, SSH Key Setup
# This Script will crate single VG named datavg from availables disks, work manually in case if you need multiple VG
# # Input files
# ssh keys file /root/important_package/team.keys
#SERVERS_FILE="servers.txt"

echo "********** Ensure New server is accessible over network without password *************"

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

LOGFILE="/var/log/provisioning.log"
#EMAIL="PDL-HCL-Linux@sandisk.com"
EMAIL="seramavalavan.vilvanathan@sandisk.com"
FQDN=""
exec > >(tee -a "$LOGFILE") 2>&1

#trap 'echo "Error on line $LINENO. Sending alert email." | mail -s "Provisioning Failed on $(hostname)" "$EMAIL" < <(tail -n 50 "$LOGFILE")' ERR

echo "=== Starting Provisioning: $(date) ==="

# === Change Root Password ===
echo "root:SNDK~R3d^H@t" | chpasswd
echo "=== Root password updated.==="

# === Validate FQDN from file ===
FQDN_FILE=/tmp/servers.txt
if [ -f "$FQDN_FILE" ]; then
  FQDN=$(head -n 1 "$FQDN_FILE")
  hostnamectl set-hostname "$FQDN"
  echo "=== Hostname set to $FQDN ==="
else
  echo "===FQDN file not found: $FQDN_FILE ==="
fi

# === Configure resolv.conf ===
rm -rf /etc/resolv.conf
touch /etc/resolv.conf
cat <<EOF > /etc/resolv.conf
search sandisk.com corp.sandisk.com
nameserver 10.86.1.1
nameserver 10.86.2.1
EOF
#chattr +i /etc/resolv.conf
echo "=== DNS & Search domain configured ==="

# === Configure Chrony ===
if command -v chronyd &>/dev/null; then
  systemctl stop chronyd || true
fi
apt install -y chrony
cat <<EOF > /etc/chrony/chrony.conf
server 10.86.1.1 iburst
server 10.86.2.1 iburst
EOF
systemctl enable chrony;systemctl restart chrony
echo "=== Chrony configured. ==="

# === Configure Postfix ===
apt install -y postfix

# Get system hostname
HOSTNAME=$(hostname)

# Backup existing Postfix configuration
cp /etc/postfix/main.cf /etc/postfix/main.cf.bak_$(date +%F_%T)

# Create new main.cf configuration
cat <<EOF > /etc/postfix/main.cf
# Basic server identity
myhostname = $HOSTNAME
myorigin = /etc/mailname
mydestination = \$myhostname, localhost.\$mydomain, localhost
mynetworks = 127.0.0.0/8

# Relay settings
relayhost = [mailrelay.sandisk.com]:25
smtp_sasl_auth_enable = no
smtp_use_tls = no
smtp_tls_security_level = none

# Mailbox and queue settings
home_mailbox = Maildir/
mailbox_command =

# Performance and security
smtpd_banner = \$myhostname ESMTP
biff = no
append_dot_mydomain = no
readme_directory = no
compatibility_level = 2

# Logging and access control
smtpd_recipient_restrictions = permit_mynetworks, reject_unauth_destination
EOF

# Set permissions
chown root:root /etc/postfix/main.cf
chmod 644 /etc/postfix/main.cf

# Restart Postfix to apply changes
systemctl restart postfix

echo "=== Postfix has been configured as a relay server using mailrelay.sandisk.com ==="

# === Install Check-MK Agent ===

curl -o /tmp/check-mk-agent.deb http://uls-op-millsndk.corp.sandisk.com/pxehome/Check-mk/check-mk-agent_2.3.0p30-1_all.deb
apt install -y /tmp/check-mk-agent.deb
echo "=== Check-MK agent installed. ==="

# === Install CrowdStrike  ===
CID="06C18613D2124D6CA8757655E830126E-83"
apt install -y /tmp/falcon-sensor_7.20.17306.deb
/opt/CrowdStrike/falconctl -s -f --cid="$CID"
systemctl enable falcon-sensor;systemctl start falcon-sensor
echo "=== Falcon Sensor installed and configured with SD CID ==="

# === Enable Firewall and Allow Ports ===
apt-get install -y ufw
for port in 22 80 443 6556; do
    sudo ufw allow ${port}/tcp
done
ufw --force  enable
echo "=== Configured OS firewall and enabled ports 22 80 443 6556 ==="


# === LVM Setup ===
lsblk -d -n -o NAME | grep -v sr0|while read disk; do
  if ! pvs | grep -q "/dev/$disk"; then
    pvcreate  "/dev/$disk"
    vgcreate datavg "/dev/$disk"
    echo "=== value of disk /dev/$disk , created VG named datavg  ==="
  else
    echo "=== Either NO  non-OS disk or Unpartitioned disk found for LVM setup ==="
  fi
done


# === Install Common Utilities ===
apt install -y wget sysstat openssl at bzip2 git htop iproute2 lsof nfs-common pcp rsync screen tcpdump telnet tmux traceroute unzip vim zip zsh ksh
echo "=== Common utilities installed. ==="

# === Add SSH keys to root user ===
cp -a /root/.ssh/authorized_keys /root/.ssh/authorized_keys_bak_$(date +%F_%T)
SSH_KEYS_FILE="/tmp/ssh_keys.txt"
if [ -f "$SSH_KEYS_FILE" ]; then
  mkdir -p /root/.ssh
  #cat "$SSH_KEYS_FILE" > /root/.ssh/authorized_keys
  cp -a $SSH_KEYS_FILE /root/.ssh/authorized_keys
  chmod 700 /root/.ssh
  chmod 600 /root/.ssh/authorized_keys
  chown -R root:root /root/.ssh
  echo "=== SSH keys added to root user ==="
else
  echo "=== SSH keys file not found: $SSH_KEYS_FILE ==="
fi

#=== TimeZone Change ===
# Mapping of location codes to IANA time zones
declare -A TIMEZONES=(
  ["ULS"]="America/Los_Angeles" ["USE"]="America/Los_Angeles" ["USS"]="America/Los_Angeles"
  ["USG"]="America/Los_Angeles" ["UIM"]="America/Los_Angeles" ["TBM"]="Asia/Bangkok"
  ["TBB"]="Asia/Bangkok" ["TPT"]="Asia/Bangkok" ["IKY"]="Asia/Jerusalem"
  ["CSJ"]="Asia/Shanghai" ["CSS"]="Asia/Shanghai" ["CSF"]="Asia/Shanghai"
  ["IOI"]="Asia/Jerusalem" ["IBP"]="Asia/Kolkata" ["IBS"]="Asia/Kolkata"
  ["IBV"]="Asia/Kolkata" ["IBT"]="Asia/Kolkata" ["KSG"]="Asia/Seoul"
  ["MSK"]="Asia/Kuala_Lumpur" ["MJP"]="Asia/Kuala_Lumpur" ["MPP"]="Asia/Kuala_Lumpur"
  ["MPL"]="Asia/Kuala_Lumpur" ["MPS"]="Asia/Kuala_Lumpur" ["PBT"]="Asia/Manila"
  ["JAN"]="Asia/Tokyo" ["JFK"]="Asia/Tokyo" ["JOK"]="Asia/Tokyo" ["JOM"]="Asia/Tokyo"
  ["JTK"]="Asia/Tokyo" ["JON"]="Asia/Tokyo" ["JYU"]="Asia/Tokyo" ["JOO"]="Asia/Tokyo"
  ["JTY"]="Asia/Tokyo" ["JYY"]="Asia/Tokyo" ["IBH"]="Asia/Kolkata"
)

# Get the hostname
HOSTNAME=$(hostname | tr '[:lower:]' '[:upper:]')


# Try to extract a known location code from the hostname
LOCATION_CODE=""
for CODE in "${!TIMEZONES[@]}"; do
  if [[ "$HOSTNAME" == *"$CODE"* ]]; then
    LOCATION_CODE="$CODE"
    break
  fi
done

# Validate and apply timezone
if [[ -z "$LOCATION_CODE" ]]; then
  echo "**** No matching location code found in hostname: $HOSTNAME ****"
  exit 1
fi

TIMEZONE="${TIMEZONES[$LOCATION_CODE]}"
echo "Detected location code: $LOCATION_CODE"

# Requires root privileges
if [[ $EUID -ne 0 ]]; then
  echo "**** Please run this script as root to change the system time zone ****"
  exit 1
fi

timedatectl set-timezone "$TIMEZONE"

if [[ $? -eq 0 ]]; then
  echo "=== Time zone successfully changed to $TIMEZONE ==="
else
  echo "=== Failed to change time zone ==="
fi



