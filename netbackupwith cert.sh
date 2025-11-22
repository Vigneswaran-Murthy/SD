


##without certificate ##

#!/bin/bash
###############################################################################
# NetBackup Client Auto-Install Script (Certificate Optional Version)
# Purpose : Automate NBU Client Installation using token-only or token+cert
# Author  : Vigneswaran Murthy (Modified for cert-optional mode)
# Version : 4.0
###############################################################################

# ========================== LOAD VARIABLE FILE ===============================
VAR_FILE="/home/7400428/Ansible_Automation_Final/Netbackup_inst/vars/nb_vars.conf"

if [[ -f "${VAR_FILE}" ]]; then
  source "${VAR_FILE}"
else
  echo "❌ Variable file not found: ${VAR_FILE}"
  exit 1
fi

# ========================== ENVIRONMENT SETTINGS ============================
LANG="C"; LANG_ALL="C"; LC_MESSAGE="C"
OS_TYPE=$(uname -s 2>/dev/null)

# ========================== VARIABLE MAPPING ================================
mst_nm="${MASTER_SERVER}"
cli_nm="${CLIENT_NAME}"
log_pth="${LOG_PATH}"
tmp_mnt="${INSTALLER_PATH}"

tkn_info=$1      # Token passed as argument
cert_info=$2     # Certificate passed as argument (OPTIONAL)

# ========================== PATH SETTINGS ===================================
export PATH="${PATH}:/usr/openv/netbackup/bin"

out_log="${log_pth}/output.txt"
err_log="${log_pth}/error.txt"
tmp_log="/tmp/.Lock_File_NBU_Client_Install"
bp_conf="/usr/openv/netbackup/bp.conf"

# Derived paths
c_pth="$(dirname ${bp_conf} 2>/dev/null)/bin"
c_bpnbat="${c_pth}/bpnbat"
c_nbcert="${c_pth}/nbcertcmd"

# System info
hst_nm=$(uname -n 2>/dev/null | awk -F '.' '{print $1}')
log_tim=$(date +%d%m%y_%H%M%S)

# Temp files
tkn_fil="${log_pth}/Mycld_Token_Gen.txt"
cert_fil="${log_pth}/Mycld_CA_Cert.txt"
nbinst_conf="/tmp/NBInstallAnswer.conf"
std_prt="1556 13724 13782 13720 10082 10102"

###############################################################################
# Utility Functions
###############################################################################
function do_ln() { echo -e "---------------------------------------------------------------\n" >> "${out_log}"; }

function ex_it() {
  ei_v=$1
  do_ln
  echo -e "Removing lock file..." >> "${out_log}"
  rm -f "${tmp_log}" >> "${out_log}" 2>&1
  echo -e "Exit Code: ${ei_v}" >> "${out_log}"
  do_ln
  exit "${ei_v}"
}

###############################################################################
# Function: pre_chk
# Purpose : Validate environment, check token, cert, and installer
###############################################################################
function pre_chk() {

  echo -e "NetBackup Client Installation (Certificate Optional Mode)\nDate: $(date)\n" > "${out_log}"
  do_ln

  # Step 1: Lock file
  echo -en "1) Checking script lock: " >> "${out_log}"
  if [ -f "${tmp_log}" ]; then
    echo -e "LOCKED (Another instance running)" >> "${out_log}"
    exit 99
  else
    echo -e "Free" >> "${out_log}"
    : > "${tmp_log}"
  fi

  # Step 2: Variable validation
  echo -e "\n2) Validating loaded variables:" >> "${out_log}"
  [[ -z "${mst_nm}" ]] && echo " - Missing MASTER_SERVER" >> "${out_log}" && ex_it 81
  [[ -z "${cli_nm}" ]] && echo " - Missing CLIENT_NAME" >> "${out_log}" && ex_it 81
  [[ -z "${tmp_mnt}" ]] && echo " - Missing INSTALLER_PATH" >> "${out_log}" && ex_it 81
  echo " - All required variables loaded successfully" >> "${out_log}"

  # Step 3: DNS check
  mst_FQDN=$(host "${mst_nm}" 2>/dev/null | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
  cli_FQDN=$(host "${cli_nm}" 2>/dev/null | awk '{print $1}' | tr '[:upper:]' '[:lower:]')

  echo -e "\n3) DNS Validation:" >> "${out_log}"
  [[ -z "${mst_FQDN}" ]] && echo "Master FQDN resolution failed" >> "${out_log}" && ex_it 1
  [[ -z "${cli_FQDN}" ]] && echo "Client FQDN resolution failed" >> "${out_log}" && ex_it 1
  echo "Master = ${mst_FQDN}" >> "${out_log}"
  echo "Client = ${cli_FQDN}" >> "${out_log}"

  # Step 4: Existing installation check
  echo -en "\n4) Checking for existing NetBackup packages: " >> "${out_log}"
  if rpm -qa | grep -q "^VRTS"; then
    echo "Detected existing installation (X)" >> "${out_log}"
    ex_it 99
  else
    echo "Not found" >> "${out_log}"
  fi

  # Step 5: Installer path validation
  echo -en "\n5) Checking installer directory: " >> "${out_log}"
  [[ ! -d "${tmp_mnt}" ]] && echo "Installer path not found (${tmp_mnt})" >> "${out_log}" && ex_it 1
  [[ ! -f "${tmp_mnt}/install" ]] && echo "Missing 'install' binary in ${tmp_mnt}" >> "${out_log}" && ex_it 98
  echo "Installer found" >> "${out_log}"

  # Step 6: Token and certificate (optional)
  echo "${tkn_info}" > "${tkn_fil}"
  echo "${cert_info}" > "${cert_fil}"

  tkn=$(head -1 "${tkn_fil}")
  cacert=$(head -1 "${cert_fil}")

  if [[ -z "${tkn}" ]]; then
    echo "Invalid token" >> "${out_log}"
    ex_it 98
  fi

  # Certificate-optional logic
  if [[ -z "${cacert}" ]]; then
    echo -e "\n6) Certificate NOT provided → Auto CA Certificate Download mode enabled" >> "${out_log}"
    cert_mode="auto"
  else
    echo -e "\n6) Certificate provided → Manual certificate mode" >> "${out_log}"
    cert_mode="manual"
  fi

  # Step 7: Port check
  echo -e "\n7) Checking communication ports to Master:" >> "${out_log}"
  for pc_prt in ${std_prt}; do
    echo -en "  - Port ${pc_prt}: " >> "${out_log}"
    nc -z -v "${mst_FQDN}" "${pc_prt}" >/dev/null 2>&1 && echo "OPEN" >> "${out_log}" || echo "BLOCKED (X)" >> "${out_log}"
  done

  # Step 8: Create NBInstallAnswer.conf
  echo -e "\n8) Creating NBInstallAnswer.conf:" >> "${out_log}"

  cat <<EOF > "${nbinst_conf}"
NB_FIPS_MODE = ${NB_FIPS_MODE}
CLIENT_NAME = ${cli_FQDN}
SERVER = ${mst_FQDN}
MACHINE_ROLE = CLIENT
EOF

  if [[ "${cert_mode}" == "manual" ]]; then
    echo "CA_CERTIFICATE_FINGERPRINT = ${cacert}" >> "${nbinst_conf}"
  else
    echo "# Auto-download CA certificate" >> "${nbinst_conf}"
  fi

  echo "AUTHORIZATION_TOKEN = ${tkn}" >> "${nbinst_conf}"
  echo "PROCEED_WITH_INSTALL = YES" >> "${nbinst_conf}"
  echo "ACCEPT_EULA = YES" >> "${nbinst_conf}"

  echo "Created ${nbinst_conf}" >> "${out_log}"
}

###############################################################################
# Function: create_bp_conf
###############################################################################
function create_bp_conf() {
  echo -e "\n9) Creating bp.conf configuration file:" >> "${out_log}"
  mkdir -p "$(dirname ${bp_conf})"

  cat <<EOF > "${bp_conf}"
SERVER = ${MASTER_SERVER}
CLIENT_NAME = ${CLIENT_NAME}
CONNECT_OPTIONS = ${CONNECT_OPTIONS}
NB_FIPS_MODE = ${NB_FIPS_MODE}
SERVICE_USER = ${SERVICE_USER}
EOF

  for media in "${MEDIA_SERVERS[@]}"; do
    echo "MEDIA_SERVER = ${media}" >> "${bp_conf}"
  done

  echo "bp.conf created successfully at ${bp_conf}" >> "${out_log}"
}

###############################################################################
# Function: ins_pkg
###############################################################################
function ins_pkg() {
  do_ln
  echo -e "\nStarting NetBackup installation from ${tmp_mnt}\n" >> "${out_log}"

  cd "${tmp_mnt}" || { echo "Failed to access ${tmp_mnt}" >> "${out_log}"; ex_it 1; }

  (echo -e "y"; echo -e "${mst_FQDN}"; echo -e "n"; echo -e "${cli_FQDN}"; echo -e "2";) \
  | ./install -answer_file "${nbinst_conf}" >> "${out_log}" 2>&1

  echo -e "\nInstallation completed.\n" >> "${out_log}"
}

###############################################################################
# Function: letz_start
###############################################################################
function letz_start() {
  pre_chk
  ins_pkg
  create_bp_conf
  echo -e "\nInstallation finished successfully.\n" >> "${out_log}"
  ex_it 0
}

###############################################################################
# Script Entry
###############################################################################
if [[ "${OS_TYPE}" == "Linux" ]]; then
  letz_start
else
  echo "Unsupported OS: ${OS_TYPE}" >> "${out_log}"
  exit 51
fi
###############################################################################
