# 🛡️ Secure VPS Bootstrap Script

This Bash script automates the secure setup of a remote Ubuntu-based server via SSH. It creates a new sudo user, configures SSH access, installs essential DevOps tools (like Ansible), locks down root access, and deploys your Ansible project — all with hardened, auditable steps and logs.

---

## 🚀 What It Does

1. Prompts you to create a new **non-root admin user**
2. **Generates a unique SSH keypair** for secure access
3. **Pushes public key to server** and configures access
4. Optionally **locks down root SSH access and disables password login**
5. Removes old tools (like Ansible, Python, Git) and **installs fresh**
6. **Clones your Ansible repo** and deploys it to the server
7. Saves:
   - A secure **credential file** with access info and private key
   - A **timestamped log file** of the entire setup

---

## 🛠️ Requirements

- Local machine:
  - Linux / macOS
  - `ssh`, `ssh-keygen`, `ssh-copy-id`, `git`, `bash`
- Remote server:
  - Ubuntu with root SSH access

---

## 🧪 Optional Verification Mode

Run this to **audit** a server (no changes made):

```bash
./bootstrap.sh --verify
This checks:

Root SSH login locked

Password authentication disabled

Key dev tools installed

SSH configuration syntax is valid

🔐 Example Usage
bash
Copy
Edit
chmod +x bootstrap.sh
./bootstrap.sh root@your.server.ip
You’ll be prompted to:

Enter a new username

Set and confirm the password

The script takes care of everything else

📁 Output Files
server-access-<user>@<ip>-<timestamp>.txt:
Contains connection info and the private key. Move this to a secure location!

bootstrap-log-<timestamp>.log:
Full log of everything the script did — for debugging or audit purposes.

🔒 Security Highlights
SSH access via ed25519 keypair

No password login after setup (optional)

Automatically disables root login once safe

Validates SSH config before restarting

Backs up any existing keys before overwriting

Uses set -euo pipefail for hardened scripting

Logs everything for transparency

📦 What Gets Installed
python3, pip3

git, curl, unzip

ansible (from official PPA)

🧹 Local Cleanup
After finishing, it deletes any temp directories (ansible-tmp) and leaves only the log and credentials.

📌 Notes
The script will overwrite the SSH key for the new user and root.

Be cautious — anyone with the output .txt file can access your server.

Do not commit that file to version control or leave it unsecured.

🧠 Troubleshooting
If ssh-copy-id fails, ensure root SSH access is enabled and firewall allows port 22.

If log shows SSH restart failure, run sudo sshd -t on the server to check config.

Run with --verify to inspect without making changes.

📬 Contact
Maintained by Somniac2103
Feel free to open an issue or PR if you'd like to suggest improvements!

yaml
Copy
Edit

---

Let me know if you'd like:

- Emojis removed (for more professional tone)
- A badge set for GitHub Actions
- A version with shell snippets as collapsible blocks
- A multilingual version (EN/DE/etc.)

Want me to save this to your repo as `README.md`?