# Ubuntu 24.04 minimal server setup (homelab baseline)

This document describes Phase 1 – Server Preparation for a fresh Ubuntu 24.04 minimal server before deploying the `nextcloud-pihole-selfhosted` stack.[web:152]  
The focus is: base OS update, SSH hardening, Docker install, basic firewall, then cloning the repository.

---

## Phase 1 – Server Preparation

### 1. Update the base system

On the new Ubuntu 24.04 minimal server, run:

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y ca-certificates curl gnupg lsb-release
```

This ensures the system has current packages and basic tools like `curl` and `ca-certificates` needed for Docker and HTTPS access.[web:140][web:153]

If a reboot is required after kernel upgrades:

```bash
sudo reboot
```

Log back in and continue.

---

### 2. (Optional) unminimize if needed

Ubuntu minimal removes some non-essential packages (man pages, extra utilities).[web:137][web:138]  
If you find essential tools missing (editors, man pages):

```bash
sudo unminimize
```

For a headless homelab with good documentation, you can stay minimal as long as you have your preferred editor and tools (e.g. `nano`, `vim`, `git`).[web:138]

Install basic tools:

```bash
sudo apt install -y git nano ufw
```

You’ll use:

- `git` to pull the repo.  
- `nano` (or your editor of choice) for `.env` and configs.  
- `ufw` for simple firewall rules.[web:145][web:149]

---

### 3. Set up SSH keys and harden SSH

If you haven’t already:

#### 3.1 Generate an SSH key on your client

On your laptop/workstation:

```bash
ssh-keygen -t ed25519 -C "homelab-nextcloud"
```

Accept defaults or choose a custom path/passphrase.

#### 3.2 Copy the key to the server

From your client:

```bash
ssh-copy-id user@your-server-ip
```

Replace `user` and `your-server-ip` with your actual username and server address.[web:147]

#### 3.3 Harden SSH on the server

On the server:

```bash
sudo nano /etc/ssh/sshd_config.d/00-custom.conf
```

Add:

```text
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
```

Then restart SSH:

```bash
sudo systemctl restart ssh
```

This matches typical Ubuntu 24.04 SSH hardening guidance.[web:147][web:139]  
Confirm you can still log in via SSH key before logging out.

---

### 4. Install Docker (official packages)

Use the official Docker CE packages rather than `docker.io` for consistency with your previous setup.[web:140][web:143]

#### 4.1 Docker GPG key

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
```

#### 4.2 Docker APT repository

```bash
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

#### 4.3 Install Docker Engine + Compose plugin

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

#### 4.4 Add your user to the `docker` group and test

```bash
sudo usermod -aG docker $USER
newgrp docker
docker run hello-world
```

This verifies Docker is working before you introduce your stack.[web:140][web:143]

---

### 5. Enable and configure UFW

Keep it simple at first so you don’t lock yourself out.[web:141][web:149]

#### 5.1 Default policies

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
```

#### 5.2 Allow SSH

```bash
sudo ufw allow 22/tcp
```

#### 5.3 Enable UFW

```bash
sudo ufw enable
sudo ufw status verbose
```

Later, when Pi-hole and Nextcloud are running, you can add rules for HTTP/HTTPS and specific ports you use (for example Pi-hole UI ports).[web:148][web:151]

Examples to add later:

```bash
# Allow web traffic (if needed)
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Example Pi-hole UI ports (adjust to your compose.yaml)
sudo ufw allow 8081/tcp
sudo ufw allow 8444/tcp
```

You can refine rules once Pi-hole and Nextcloud are up and you know exactly which ports are in use.

---

### 6. Prepare a working directory and clone the repo

Now the base host is ready; time to bring in your project.

```bash
cd ~
git clone https://github.com/Deluk47/nextcloud-pihole-selfhosted.git
cd nextcloud-pihole-selfhosted
git status
```

At this point you can start following `README.md` to:

- Create `.env` files from `.env.example` in:
  - `pihole/`
  - `nextcloud/`
  - `nextcloud/reverse-proxy/`
- Bring up the stacks with:

  ```bash
  # Pi-hole
  cd pihole
  docker compose up -d

  # Nextcloud AIO
  cd ../nextcloud
  docker compose up -d

  # Reverse proxy
  cd reverse-proxy
  docker compose up -d
  ```

Pi-hole should provide DNS, Nextcloud should serve your cloud, and the reverse proxy should terminate HTTPS for your chosen domain.

---

### 7. Documentation notes

As you run these commands on a new host:

- Capture the exact sequence in a `terminal-session-YYYYMMDD.md` or similar file for your own records.  
- Keep `SETUP-UBUNTU-24.04.md` focused on OS-level preparation.  
- Use:
  - `pihole/PIHOLE_DEPLOYMENT.md`  
  - `nextcloud/NEXTCLOUD_DEPLOYMENT.md`  
  - `nextcloud/reverse-proxy/REVERSE-PROXY.md`  
  for stack-specific deployment and troubleshooting details.

This separation makes future rebuilds and public documentation clearer and easier to maintain.[web:145][web:152]
