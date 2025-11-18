##sera_ubuntu_with_email


#!/bin/bash
cd /data/automation/os_config/ubuntu_os_config
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



####


#!/bin/bash
# === Ubuntu Provisioning Script with HTML Email Summary ===

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ----------------------------
# Configuration
# ----------------------------
HOSTNAME=$(hostname -f 2>/dev/null || hostname)
DATE=$(date +"%d%b%Y_%H%M%S")
BASE_DIR="/home/7400428/Ansible_Automation_Final/ubuntu_os_config/ubuntu_os_config_v1"
OUTPUT_DIR="$BASE_DIR/ubuntu_output/$HOSTNAME"
LOGFILE="$OUTPUT_DIR/provisioning_$DATE.log"
SUMMARY="$OUTPUT_DIR/status.txt"

MAIL_TO="vigneswaran.murthy@sandisk.com"
MAIL_CC="PDL-IT-Linux-Support@sandisk.com"
MAIL_FROM="ansible_automation@sandisk.com"

mkdir -p "$OUTPUT_DIR"
: > "$SUMMARY"

exec > >(tee -a "$LOGFILE") 2>&1

# ----------------------------
# Helper Functions
# ----------------------------
log_task() {
    local task_name="$1"
    shift
    echo "=== Running: $task_name ==="
    if "$@" &>>"$LOGFILE"; then
        echo -e "$task_name\t✅ Success" | tee -a "$SUMMARY"
    else
        echo -e "$task_name\t❌ Failed" | tee -a "$SUMMARY"
    fi
}

# ----------------------------
# Provisioning Tasks
# ----------------------------
echo "=== Starting Provisioning: $(date) ==="

log_task "Update Root Password" bash -c 'echo "root:SNDK~R3d^H@t" | chpasswd'

log_task "Set Hostname from /tmp/servers.txt" bash -c '
  if [ -f /tmp/servers.txt ]; then
    hostnamectl set-hostname "$(head -n 1 /tmp/servers.txt)"
  fi
'

log_task "Configure resolv.conf" bash -c '
  cat <<EOF > /etc/resolv.conf
search sandisk.com corp.sandisk.com
nameserver 10.86.1.1
nameserver 10.86.2.1
EOF
'

log_task "Chrony Install & Config" bash -c '
  apt-get update -y &&
  apt-get install -y chrony mailutils &&
  cat <<EOF > /etc/chrony/chrony.conf
server 10.86.1.1 iburst
server 10.86.2.1 iburst
EOF
  systemctl enable chrony &&
  systemctl restart chrony
'

log_task "Postfix Setup" bash -c '
  apt-get install -y postfix &&
  cp /etc/postfix/main.cf /etc/postfix/main.cf.bak_$(date +%F_%T) &&
  cat <<EOF > /etc/postfix/main.cf
myhostname = $(hostname)
myorigin = /etc/mailname
mydestination = \$myhostname, localhost.\$mydomain, localhost
mynetworks = 127.0.0.0/8
relayhost = [mailrelay.sandisk.com]:25
smtp_sasl_auth_enable = no
smtp_use_tls = no
smtp_tls_security_level = none
home_mailbox = Maildir/
EOF
  systemctl restart postfix
'

log_task "Check-MK Agent Installation" bash -c '
  curl -s -o /tmp/check-mk-agent.deb http://uls-op-millsndk.corp.sandisk.com/pxehome/Check-mk/check-mk-agent_2.3.0p30-1_all.deb &&
  apt-get install -y /tmp/check-mk-agent.deb
'

log_task "Falcon Sensor Installation" bash -c '
  CID="06C18613D2124D6CA8757655E830126E-83"
  apt-get install -y /tmp/falcon-sensor_7.20.17306.deb &&
  /opt/CrowdStrike/falconctl -s -f --cid="$CID" &&
  systemctl enable falcon-sensor &&
  systemctl start falcon-sensor
'

log_task "Firewall Setup (UFW)" bash -c '
  apt-get install -y ufw &&
  for port in 22 80 443 6556; do ufw allow ${port}/tcp; done &&
  ufw --force enable
'

log_task "LVM Setup" bash -c '
  lsblk -d -n -o NAME | grep -v sr0 | while read disk; do
    if ! pvs | grep -q "/dev/$disk"; then
      pvcreate "/dev/$disk"
      vgcreate datavg "/dev/$disk"
      break
    fi
  done
'

log_task "Install Common Utilities" bash -c '
  apt-get install -y wget sysstat openssl at bzip2 git htop iproute2 lsof nfs-common pcp rsync screen tcpdump telnet tmux traceroute unzip vim zip zsh ksh
'

log_task "Add SSH Keys to Root" bash -c '
  SSH_KEYS_FILE="/tmp/ssh_keys.txt"
  if [ -f "$SSH_KEYS_FILE" ]; then
    mkdir -p /root/.ssh
    cp -a $SSH_KEYS_FILE /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys
    chown -R root:root /root/.ssh
  fi
'

log_task "Set Timezone from Hostname" bash -c '
  declare -A TIMEZONES=( ["ULS"]="America/Los_Angeles" ["IBP"]="Asia/Kolkata" ["KSG"]="Asia/Seoul" ["MSK"]="Asia/Kuala_Lumpur" ["PBT"]="Asia/Manila" ["JAN"]="Asia/Tokyo" )
  H=$(hostname | tr "[:lower:]" "[:upper:]")
  for CODE in "${!TIMEZONES[@]}"; do
    if [[ "$H" == *"$CODE"* ]]; then
      timedatectl set-timezone "${TIMEZONES[$CODE]}"
      exit 0
    fi
  done
  exit 1
'

# ----------------------------
# HTML Email Summary Section
# ----------------------------
echo
echo "=== Generating HTML summary and sending email ==="

HTML_FILE="$OUTPUT_DIR/email_summary.html"

{
  echo "<html><body style='font-family: Arial, sans-serif; text-align: center; background-color: #fafafa; padding: 20px;'>"
  echo "<div style='display:inline-block;text-align:left;background:#fff;padding:20px;border-radius:8px;box-shadow:0 2px 8px rgba(0,0,0,0.1);'>"
  echo "<p style='text-align:center;font-size:16px;font-weight:bold;'>Ubuntu Provisioning Task Summary for $HOSTNAME</p>"
  echo "<table border='1' cellpadding='8' cellspacing='0' style='border-collapse:collapse;width:600px;margin:0 auto;text-align:center;'>"
  echo "<tr style='background-color:#f2f2f2;'><th>Task Name</th><th>Status</th></tr>"

  i=0   # ✅ Initialize the counter before use
  while IFS=$'\t' read -r task status; do
    row_color="#ffffff"
    [[ $((++i % 2)) -eq 0 ]] && row_color="#f9f9f9"

    if [[ "$status" == *"✅"* ]]; then
      color="green"; label="✅ Success"
    elif [[ "$status" == *"❌"* ]]; then
      color="red"; label="❌ Failed"
    else
      color="orange"; label="⚠️ Unknown"
    fi

    echo "<tr style='background-color:$row_color;'><td>$task</td><td style='color:$color;font-weight:bold;'>$label</td></tr>"
  done < "$SUMMARY"

  echo "</table></div></body></html>"
} > "$HTML_FILE"

# Send email
mail -a "From: $MAIL_FROM" -a "Cc: $MAIL_CC" -s "Ubuntu Provisioning Summary - $HOSTNAME" -a "Content-Type: text/html" "$MAIL_TO" < "$HTML_FILE"

echo "✅ Email sent to $MAIL_TO and CC: $MAIL_CC"
echo "📁 Logs: $LOGFILE"
echo "📁 Status: $SUMMARY"
echo "📧 HTML Email: $HTML_FILE"
echo "Status:$HTML_FILE" > output.txt 
echo "=== Completed at $(date) ==="
