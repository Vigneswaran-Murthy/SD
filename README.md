Netbackup instalaltion .

+------------------------------------------------------+
|                     MASTER SERVER                    |
|  (where you execute your automation script)           |
|                                                      |
|  /home/7400428/Ansible_Automation_Final/             |
|   ├── Netbackup_inst/                                |
|   │   ├── vars/nb_vars.conf      <-- environment vars|
|   │   ├── software/NBU_10.3.0.1/ <-- NBU installer   |
|   │   └── scripts/NBU_Client_Install.sh <-- your main|
|   │                                                  |
|   └── wrapper (optional, runs remotely)              |
+------------------------------------------------------+
                  │
                  │ (SSH/SCP)
                  ▼
+------------------------------------------------------+
|                     CLIENT SERVER                    |
|    (where NetBackup Client will be installed)        |
|                                                      |
|  Receives via SSH:                                   |
|   ├── NBU_Client_Install.sh                          |
|   ├── /tmp/.Lock_File_NBU_Client_Install (temp lock) |
|   ├── /tmp/NBInstallAnswer.conf                      |
|   └── /usr/openv/netbackup/bp.conf (generated)       |
|                                                      |
|  Uses installer package from:                        |
|   /home/7400428/Ansible_Automation_Final/Netbackup_inst/ |
|        software/NBU_10.3.0.1/install                 |
|                                                      |
|  Writes logs to:                                     |
|   /home/7400428/Netbackup_installation/Logs/output.txt|
+------------------------------------------------------+



 ┌───────────────────────────────────────────┐
 │        STEP 1: Master Execution           │
 └───────────────────────────────────────────┘
           │
           │  You run the script:
           │
           │  bash NBU_Client_Install.sh <token> <cert>
           │
           ▼
 ┌───────────────────────────────────────────┐
 │   STEP 2: Load variable file (nb_vars.conf) │
 │   Reads:                                   │
 │    - MASTER_SERVER                         │
 │    - CLIENT_NAME                           │
 │    - MEDIA_SERVERS[]                       │
 │    - INSTALLER_PATH                        │
 │    - LOG_PATH                              │
 │    - SERVICE_USER, CONNECT_OPTIONS etc.    │
 └───────────────────────────────────────────┘
           │
           ▼
 ┌───────────────────────────────────────────┐
 │   STEP 3: Pre-check phase                 │
 │   (runs validations before install)       │
 │                                           │
 │   ✅ Checks for lock file                 │
 │   ✅ Confirms variables loaded            │
 │   ✅ Verifies DNS for master/client       │
 │   ✅ Checks if NetBackup already exists   │
 │   ✅ Confirms installer path valid        │
 │   ✅ Confirms token & certificate          │
 │   ✅ Tests TCP ports 1556,13724,…         │
 └───────────────────────────────────────────┘
           │
           ▼
 ┌───────────────────────────────────────────┐
 │   STEP 4: Generate configuration files     │
 │   - NBInstallAnswer.conf (used by installer)
 │   - bp.conf (NetBackup client config)     │
 │                                           │
 │   bp.conf includes:                       │
 │     SERVER = use-op-snbkip01              │
 │     CLIENT_NAME = use-dd-oragis-corp      │
 │     MEDIA_SERVER = use-op-snbkip02,03,04  │
 │     NB_FIPS_MODE = DISABLE                │
 │     SERVICE_USER = root                   │
 └───────────────────────────────────────────┘
           │
           ▼
 ┌───────────────────────────────────────────┐
 │   STEP 5: Installation phase              │
 │   Executes: ./install -answer_file NBInstallAnswer.conf
 │   Logs all actions to output.txt          │
 └───────────────────────────────────────────┘
           │
           ▼
 ┌───────────────────────────────────────────┐
 │   STEP 6: Post-install phase              │
 │   ✅ Cleans up lock files                 │
 │   ✅ Verifies bp.conf created             │
 │   ✅ Logs success                         │
 │                                           │
 │   Output:                                 │
 │    /home/7400428/Netbackup_installation/Logs/output.txt
 └───────────────────────────────────────────┘
