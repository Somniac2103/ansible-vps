 🛡️ Secure VPS Bootstrap Script

This Bash script automates the secure setup of a remote Ubuntu-based server via SSH. It creates a new sudo user, configures SSH access, installs essential DevOps tools (like Ansible), locks down root access, and deploys your Ansible project — all with hardened, auditable steps and logs.

---

🚀 What It Does

1. Prompts you to create a new non-root admin user
2. Generates a unique SSH keypair for secure access
3. Pushes the public key to the server and configures access
4. Optionally locks down root SSH access and disables password login
5. Removes old packages and installs fresh DevOps tools
6. Clones your Ansible repo and deploys it to the server
7. Saves:
   - A secure credential file (access info + private key)
   - A timestamped log file of the entire setup

---

🛠️ Requirements

- Local machine:
  - Linux / macOS
  - `ssh`, `ssh-keygen`, `ssh-copy-id`, `git`, `bash`

- Remote server:
  - Ubuntu (root SSH access required)

---

 🧪 Optional: Verification Mode

To audit an existing server (without making changes):

bash
./bootstrap.sh --verify
This will check:

🔒 Root SSH login is locked

🚫 Password authentication is disabled

🧰 Required tools (python3, pip3, git, curl, ansible) are installed

🔧 SSH configuration syntax is valid

🔐 Example Usage
bash
Copy
Edit
chmod +x bootstrap.sh
./bootstrap.sh root@your.server.ip
You’ll be prompted to:

Enter a new username

Set and confirm the password

The script handles everything else.

📁 Output Files
server-access-<user>@<ip>-<timestamp>.txt
➤ Contains connection info and the private key.
⚠️ Move this file to a secure, encrypted location immediately after setup.

bootstrap-log-<timestamp>.log
➤ Full log of everything the script did — for auditing and debugging.

🔒 Security Highlights
SSH access via ed25519 keypair

Optional root login and password login disabling

Validates SSH config before restarting

Automatically backs up all existing keys before replacing

Uses set -euo pipefail for script hardening

Logs every action to a persistent logfile

📦 What Gets Installed
python3, pip3

git, curl, unzip

ansible (from official PPA)

🧹 Local Cleanup
After setup:

Temporary directory ansible-tmp is removed

Only the log and credential files remain

📌 Notes
The script may overwrite .ssh/authorized_keys for both the new user and root

Do NOT commit the generated .txt credential file to Git!

Anyone with access to that file can access your server

🧠 Troubleshooting
ssh-copy-id fails:
➤ Ensure root SSH login is enabled and port 22 is open

SSH restart fails:
➤ Run sudo sshd -t on the server to check for config errors

Want to audit only:
➤ Run with --verify to test without making changes

📬 Contact
Maintained by Somniac2103
Feel free to open an issue or submit a pull request with improvements or fixes.
