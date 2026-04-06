# Phase 0 — Proxmox Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recover ~7 GB RAM on Proxmox by migrating smart-resume and restorate VMs to native LXC containers, removing SonarQube, and tuning host settings (ZFS ARC, memory ballooning, GPU verification).

**Architecture:** Each VM-to-LXC migration creates a new `compute/<app>_lxc/` directory following existing Ansible patterns. LXC containers run services natively via systemd (no Docker). A new `compute/proxmox_host/` directory targets the Proxmox host for ZFS/ballooning/GPU tasks. Network stack gets minimal updates (remove SonarQube from Caddy, update Grafana log panel queries).

**Tech Stack:** Ansible (community.general.proxmox for LXC, community.general.proxmox_kvm for VM config), Debian 12 LXC, systemd, Caddy, PostgreSQL 17, Valkey, Node.js 22, Python 3.11, uv, Promtail.

**Spec:** `docs/specs/2026-04-06-phase0-proxmox-optimization-design.md`

---

## File Map

### New: `compute/proxmox_host/`
| File | Responsibility |
|------|----------------|
| `ansible.cfg` | Inventory, vault config |
| `inventory/hosts.yml` | Proxmox host + Ollama VM SSH targets |
| `group_vars/all/vars.yml` | Proxmox API creds, ZFS values, Ollama VM ID |
| `group_vars/all/vault.yml` | Encrypted secrets (Proxmox API token) |
| `Makefile` | Targets: `zfs-arc`, `ollama-balloon`, `verify-gpu`, `remove-sonarqube` |
| `playbooks/zfs_arc.yml` | Write modprobe config, update initramfs |
| `playbooks/ollama_balloon.yml` | Set balloon via Proxmox API |
| `playbooks/verify_gpu.yml` | Read-only validation checks |
| `playbooks/remove_sonarqube.yml` | Stop + delete VM 103 |

### New: `compute/smart_resume_lxc/`
| File | Responsibility |
|------|----------------|
| `ansible.cfg` | Inventory, vault config |
| `requirements.yml` | Ansible collections |
| `inventory/hosts.yml` | LXC SSH target |
| `group_vars/all/vars.yml` | LXC spec, network, app config |
| `group_vars/all/vault.yml` | Encrypted secrets |
| `Makefile` | Targets: `provision`, `configure`, `deploy` |
| `playbooks/site.yml` | Import chain: create → configure → deploy |
| `playbooks/create_lxc.yml` | Create LXC via Proxmox API |
| `playbooks/configure_lxc.yml` | Install packages, configure services |
| `playbooks/deploy_app.yml` | Build locally, rsync, restart |
| `templates/smart-resume-api.service.j2` | Systemd unit for uvicorn |
| `templates/Caddyfile.j2` | Static files + API reverse proxy |
| `templates/env.j2` | API environment variables |

### New: `compute/restorate_lxc/`
| File | Responsibility |
|------|----------------|
| `ansible.cfg` | Inventory, vault config |
| `requirements.yml` | Ansible collections |
| `inventory/hosts.yml` | LXC SSH target |
| `group_vars/all/vars.yml` | LXC spec, network, app config |
| `group_vars/all/vault.yml` | Encrypted secrets (PG, Valkey, API keys) |
| `group_vars/all/vault.yml.example` | Template for vault secrets |
| `Makefile` | Targets: provision, configure, deploy, db-* operations |
| `playbooks/site.yml` | Import chain: create → configure → deploy |
| `playbooks/create_lxc.yml` | Create LXC via Proxmox API |
| `playbooks/configure_lxc.yml` | Install PG, Valkey, Caddy, Node.js |
| `playbooks/deploy_app.yml` | Build locally, copy binary + SSR bundle, restart |
| `templates/restorate-api.service.j2` | Systemd unit for Go binary |
| `templates/restorate-web.service.j2` | Systemd unit for Node.js SSR |
| `templates/Caddyfile.j2` | Reverse proxy for API + web |
| `templates/api.env.j2` | API environment variables |
| `templates/valkey.conf.j2` | Valkey server config |
| `templates/promtail-config.yml.j2` | Journal log shipping to Loki |
| `templates/pg_backup.service.j2` | pg_dump systemd service |
| `templates/pg_backup.timer.j2` | Daily backup timer |

### Modified: `network/`
| File | Change |
|------|--------|
| `network/caddy/Caddyfile:192-199` | Remove sonarqube block |
| `network/grafana/provisioning/dashboards/restorate.json:597,619,639` | Update Loki queries from `compose_project` to `job` label |

### Removed (after decommission):
| Directory | When |
|-----------|------|
| `compute/sonarqube_vm/` | After Task 3 |
| `compute/smart_resume_vm/` | After Task 1 cutover verified |
| `compute/restorate_vm/` | After Task 2 cutover verified |

---

## Task 1: Proxmox Host — Scaffolding + ZFS ARC + Ollama Balloon

**Files:**
- Create: `compute/proxmox_host/ansible.cfg`
- Create: `compute/proxmox_host/inventory/hosts.yml`
- Create: `compute/proxmox_host/group_vars/all/vars.yml`
- Create: `compute/proxmox_host/group_vars/all/vault.yml`
- Create: `compute/proxmox_host/Makefile`
- Create: `compute/proxmox_host/playbooks/zfs_arc.yml`
- Create: `compute/proxmox_host/playbooks/ollama_balloon.yml`
- Create: `compute/proxmox_host/playbooks/verify_gpu.yml`
- Create: `compute/proxmox_host/playbooks/remove_sonarqube.yml`

- [ ] **Step 1: Create `compute/proxmox_host/ansible.cfg`**

```ini
[defaults]
inventory          = inventory/hosts.yml
vault_password_file = ~/.vault_pass
host_key_checking  = False
stdout_callback    = default
result_format      = yaml
```

- [ ] **Step 2: Create `compute/proxmox_host/inventory/hosts.yml`**

```yaml
all:
  hosts:
    proxmox:
      ansible_host: "192.168.1.184"
      ansible_user: root
      ansible_ssh_private_key_file: ~/.ssh/id_ed25519
      ansible_python_interpreter: /usr/bin/python3
    ollama-gpu:
      ansible_host: "192.168.1.48"
      ansible_user: ollama-gpu
      ansible_ssh_private_key_file: ~/.ssh/id_ed25519
      ansible_python_interpreter: /usr/bin/python3
```

- [ ] **Step 3: Create `compute/proxmox_host/group_vars/all/vars.yml`**

```yaml
# Proxmox API connection
proxmox_host: "192.168.1.184"
proxmox_node: "proxmox"
proxmox_api_user: "root@pam"
proxmox_api_token_id:     "{{ vault_proxmox_api_token_id }}"
proxmox_api_token_secret: "{{ vault_proxmox_api_token_secret }}"

# ZFS ARC limits
zfs_arc_max: 3221225472    # 3 GB
zfs_arc_min: 2147483648    # 2 GB

# Ollama VM
ollama_vm_id: 101
ollama_balloon_min_mb: 4096
ollama_memory_max_mb: 12288

# SonarQube VM
sonarqube_vm_id: 103

# GPU passthrough
gpu_pcie_address: "0000:26:00"
ollama_host_port: "0.0.0.0:11434"
```

- [ ] **Step 4: Create vault file**

```bash
cd compute/proxmox_host
cp ../ollama_vm/group_vars/all/vault.yml group_vars/all/vault.yml
```

This reuses the same Proxmox API token secrets from an existing vault. If the file doesn't have the right secrets, create a new vault:

```bash
cat > /tmp/vault_template.yml << 'TEMPLATE'
vault_proxmox_api_token_id: "root@pam!ansible"
vault_proxmox_api_token_secret: "<token-from-proxmox>"
TEMPLATE
cp /tmp/vault_template.yml group_vars/all/vault.yml
ansible-vault encrypt group_vars/all/vault.yml
rm /tmp/vault_template.yml
```

- [ ] **Step 5: Create `compute/proxmox_host/playbooks/zfs_arc.yml`**

```yaml
- name: Cap ZFS ARC memory
  hosts: proxmox
  become: true
  vars_files:
    - ../group_vars/all/vars.yml
  tasks:
    - name: Write ZFS modprobe config
      ansible.builtin.copy:
        dest: /etc/modprobe.d/zfs.conf
        content: |
          options zfs zfs_arc_max={{ zfs_arc_max }}
          options zfs zfs_arc_min={{ zfs_arc_min }}
        owner: root
        group: root
        mode: "0644"
      register: zfs_conf

    - name: Rebuild initramfs
      ansible.builtin.command: update-initramfs -u -k all
      when: zfs_conf.changed

    - name: Remind about reboot
      ansible.builtin.debug:
        msg: >
          ZFS ARC config written. REBOOT REQUIRED to apply.
          Current ARC max: {{ lookup('file', '/proc/spl/kstat/zfs/arcstats') | default('check manually') }}
          Run: ssh root@{{ proxmox_host }} reboot
      when: zfs_conf.changed
```

- [ ] **Step 6: Create `compute/proxmox_host/playbooks/ollama_balloon.yml`**

```yaml
- name: Enable memory ballooning on Ollama VM
  hosts: localhost
  gather_facts: false
  vars_files:
    - ../group_vars/all/vars.yml
    - ../group_vars/all/vault.yml
  tasks:
    - name: Set balloon memory on Ollama VM
      community.general.proxmox_kvm:
        api_host:         "{{ proxmox_host }}"
        api_user:         "{{ proxmox_api_user }}"
        api_token_id:     "{{ proxmox_api_token_id }}"
        api_token_secret: "{{ proxmox_api_token_secret }}"
        node:    "{{ proxmox_node }}"
        vmid:    "{{ ollama_vm_id }}"
        memory:  "{{ ollama_memory_max_mb }}"
        balloon: "{{ ollama_balloon_min_mb }}"
        update:  true

    - name: Remind about VM restart
      ansible.builtin.debug:
        msg: >
          Ballooning set: min={{ ollama_balloon_min_mb }}MB, max={{ ollama_memory_max_mb }}MB.
          VM RESTART REQUIRED to apply. Stop and start VM {{ ollama_vm_id }} from Proxmox UI
          or run: qm shutdown {{ ollama_vm_id }} && sleep 10 && qm start {{ ollama_vm_id }}
```

- [ ] **Step 7: Create `compute/proxmox_host/playbooks/verify_gpu.yml`**

```yaml
- name: Verify GPU passthrough configuration
  hosts: proxmox
  become: true
  vars_files:
    - ../group_vars/all/vars.yml
  tasks:
    - name: Check IOMMU in kernel cmdline
      ansible.builtin.command: cat /proc/cmdline
      register: cmdline
      changed_when: false

    - name: Validate IOMMU flags
      ansible.builtin.assert:
        that:
          - "'amd_iommu=on' in cmdline.stdout or 'intel_iommu=on' in cmdline.stdout"
          - "'iommu=pt' in cmdline.stdout"
        fail_msg: "IOMMU not enabled in kernel cmdline: {{ cmdline.stdout }}"
        success_msg: "IOMMU enabled: {{ cmdline.stdout | regex_search('(amd|intel)_iommu=on iommu=pt') }}"

    - name: Check nouveau is blacklisted
      ansible.builtin.command: grep -r nouveau /etc/modprobe.d/
      register: nouveau_check
      changed_when: false
      failed_when: false

    - name: Report nouveau status
      ansible.builtin.debug:
        msg: >
          {% if 'blacklist nouveau' in nouveau_check.stdout %}
          nouveau is blacklisted
          {% else %}
          WARNING: nouveau may not be blacklisted. Check /etc/modprobe.d/ manually.
          Output: {{ nouveau_check.stdout }}
          {% endif %}

    - name: Check IOMMU group for GPU
      ansible.builtin.shell: |
        for d in /sys/kernel/iommu_groups/*/devices/*; do
          if echo "$d" | grep -q "{{ gpu_pcie_address }}"; then
            group=$(echo "$d" | cut -d/ -f5)
            echo "GPU {{ gpu_pcie_address }} is in IOMMU group $group"
            ls /sys/kernel/iommu_groups/$group/devices/
          fi
        done
      register: iommu_group
      changed_when: false

    - name: Report IOMMU group
      ansible.builtin.debug:
        msg: "{{ iommu_group.stdout }}"

- name: Verify Ollama VM GPU and config
  hosts: ollama-gpu
  become: false
  vars_files:
    - ../group_vars/all/vars.yml
  tasks:
    - name: Run nvidia-smi
      ansible.builtin.command: nvidia-smi
      register: nvidia_smi
      changed_when: false

    - name: Report GPU status
      ansible.builtin.debug:
        msg: "{{ nvidia_smi.stdout }}"

    - name: Check OLLAMA_HOST
      ansible.builtin.command: systemctl show ollama --property=Environment
      register: ollama_env
      changed_when: false

    - name: Validate OLLAMA_HOST
      ansible.builtin.assert:
        that:
          - "'OLLAMA_HOST={{ ollama_host_port }}' in ollama_env.stdout"
        fail_msg: "OLLAMA_HOST not set to {{ ollama_host_port }}: {{ ollama_env.stdout }}"
        success_msg: "OLLAMA_HOST={{ ollama_host_port }} confirmed"

    - name: Test Ollama API
      ansible.builtin.uri:
        url: "http://127.0.0.1:11434/api/tags"
        method: GET
        return_content: true
      register: ollama_api

    - name: Report loaded models
      ansible.builtin.debug:
        msg: "Ollama API responding. Models: {{ ollama_api.json.models | map(attribute='name') | list }}"
```

- [ ] **Step 8: Create `compute/proxmox_host/playbooks/remove_sonarqube.yml`**

```yaml
- name: Remove SonarQube VM
  hosts: localhost
  gather_facts: false
  vars_files:
    - ../group_vars/all/vars.yml
    - ../group_vars/all/vault.yml
  tasks:
    - name: Confirm removal
      ansible.builtin.pause:
        prompt: >
          This will PERMANENTLY DELETE VM {{ sonarqube_vm_id }} (SonarQube)
          and all its data. Type 'yes' to continue
      register: confirm

    - name: Abort if not confirmed
      ansible.builtin.fail:
        msg: "Aborted by user"
      when: confirm.user_input != 'yes'

    - name: Stop SonarQube VM
      community.general.proxmox_kvm:
        api_host:         "{{ proxmox_host }}"
        api_user:         "{{ proxmox_api_user }}"
        api_token_id:     "{{ proxmox_api_token_id }}"
        api_token_secret: "{{ proxmox_api_token_secret }}"
        node:  "{{ proxmox_node }}"
        vmid:  "{{ sonarqube_vm_id }}"
        state: stopped
        force: true
        timeout: 120

    - name: Delete SonarQube VM
      community.general.proxmox_kvm:
        api_host:         "{{ proxmox_host }}"
        api_user:         "{{ proxmox_api_user }}"
        api_token_id:     "{{ proxmox_api_token_id }}"
        api_token_secret: "{{ proxmox_api_token_secret }}"
        node:  "{{ proxmox_node }}"
        vmid:  "{{ sonarqube_vm_id }}"
        state: absent

    - name: Done
      ansible.builtin.debug:
        msg: >
          VM {{ sonarqube_vm_id }} deleted. Next steps:
          1. Remove compute/sonarqube_vm/ from git
          2. Remove sonarqube block from network/caddy/Caddyfile
          3. Redeploy Caddy
```

- [ ] **Step 9: Create `compute/proxmox_host/Makefile`**

```makefile
.PHONY: zfs-arc ollama-balloon verify-gpu remove-sonarqube

zfs-arc:
	ansible-playbook playbooks/zfs_arc.yml

ollama-balloon:
	ansible-playbook playbooks/ollama_balloon.yml

verify-gpu:
	ansible-playbook playbooks/verify_gpu.yml

remove-sonarqube:
	ansible-playbook playbooks/remove_sonarqube.yml
```

- [ ] **Step 10: Commit**

```bash
git add compute/proxmox_host/
git commit -m "feat(compute): add proxmox_host playbooks — ZFS ARC, ballooning, GPU verify, SonarQube removal"
```

---

## Task 2: Smart Resume LXC — Scaffolding

**Files:**
- Create: `compute/smart_resume_lxc/ansible.cfg`
- Create: `compute/smart_resume_lxc/requirements.yml`
- Create: `compute/smart_resume_lxc/inventory/hosts.yml`
- Create: `compute/smart_resume_lxc/group_vars/all/vars.yml`
- Create: `compute/smart_resume_lxc/group_vars/all/vault.yml`
- Create: `compute/smart_resume_lxc/Makefile`
- Create: `compute/smart_resume_lxc/playbooks/site.yml`

- [ ] **Step 1: Create `compute/smart_resume_lxc/ansible.cfg`**

```ini
[defaults]
inventory          = inventory/hosts.yml
roles_path         = roles
vault_password_file = ~/.vault_pass
host_key_checking  = False
stdout_callback    = default
result_format      = yaml
```

- [ ] **Step 2: Create `compute/smart_resume_lxc/requirements.yml`**

```yaml
collections:
  - name: community.general    # proxmox (LXC), ufw
```

- [ ] **Step 3: Create `compute/smart_resume_lxc/inventory/hosts.yml`**

```yaml
all:
  hosts:
    localhost:
      ansible_connection: local
    smart-resume:
      ansible_host: "192.168.1.210"    # temporary — change to .200 after cutover
      ansible_user: root
      ansible_ssh_private_key_file: ~/.ssh/id_ed25519
      ansible_python_interpreter: /usr/bin/python3
```

Note: LXC containers default to root SSH access. After configure_lxc creates a deploy user, update `ansible_user` if desired.

- [ ] **Step 4: Create `compute/smart_resume_lxc/group_vars/all/vars.yml`**

```yaml
# Proxmox connection
proxmox_host: "192.168.1.184"
proxmox_node: "proxmox"
proxmox_api_user: "root@pam"
proxmox_api_token_id:     "{{ vault_proxmox_api_token_id }}"
proxmox_api_token_secret: "{{ vault_proxmox_api_token_secret }}"

# LXC spec
lxc_id: 110
lxc_name: "smart-resume"
lxc_template: "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
lxc_cores: 1
lxc_memory_mb: 1024
lxc_swap_mb: 256
lxc_disk_size: "10"
lxc_storage: "local-lvm"

# Network (static)
lxc_ip: "192.168.1.210"          # temporary — change to .200 after cutover
lxc_ip_final: "192.168.1.200"    # documented target
lxc_gateway: "192.168.1.1"
lxc_nameserver: "192.168.1.1"
lxc_cidr: 24

# SSH
lxc_ssh_key_path: "~/.ssh/id_ed25519.pub"

# App
app_repo_path: "/home/gooral/Projects/smart-resume"
app_remote_path: "/opt/smart-resume"
api_port: 8000
```

- [ ] **Step 5: Create vault file**

Copy and adapt from the existing smart_resume_vm vault (it already has the Proxmox API token + app secrets):

```bash
cd compute/smart_resume_lxc
mkdir -p group_vars/all
cp ../smart_resume_vm/group_vars/all/vault.yml group_vars/all/vault.yml
```

The vault already contains: `vault_proxmox_api_token_id`, `vault_proxmox_api_token_secret`, `vault_vm_root_password` (reuse as `vault_lxc_root_password` — or add a new entry), `vault_ollama_url`, `vault_session_secret`, `vault_turnstile_secret_key`, `vault_turnstile_site_key`.

If needed, decrypt, add `vault_lxc_root_password`, and re-encrypt:

```bash
ansible-vault edit group_vars/all/vault.yml
# Add: vault_lxc_root_password: "<strong-password>"
```

- [ ] **Step 6: Create `compute/smart_resume_lxc/Makefile`**

```makefile
.PHONY: provision configure deploy install-deps

install-deps:
	ansible-galaxy collection install -r requirements.yml

provision: install-deps
	ansible-playbook playbooks/site.yml

configure:
	ansible-playbook playbooks/configure_lxc.yml

deploy:
	ansible-playbook playbooks/deploy_app.yml
```

- [ ] **Step 7: Create `compute/smart_resume_lxc/playbooks/site.yml`**

```yaml
- import_playbook: create_lxc.yml
- import_playbook: configure_lxc.yml
- import_playbook: deploy_app.yml
```

- [ ] **Step 8: Commit**

```bash
git add compute/smart_resume_lxc/ansible.cfg compute/smart_resume_lxc/requirements.yml \
  compute/smart_resume_lxc/inventory/ compute/smart_resume_lxc/group_vars/all/vars.yml \
  compute/smart_resume_lxc/Makefile compute/smart_resume_lxc/playbooks/site.yml
git commit -m "feat(compute): scaffold smart_resume_lxc directory"
```

Note: `vault.yml` is encrypted and may be in `.gitignore`. Check `compute/.gitignore` and add the new vault path if needed.

---

## Task 3: Smart Resume LXC — Create Playbook

**Files:**
- Create: `compute/smart_resume_lxc/playbooks/create_lxc.yml`

- [ ] **Step 1: Create `compute/smart_resume_lxc/playbooks/create_lxc.yml`**

```yaml
- name: Create Smart Resume LXC container
  hosts: localhost
  gather_facts: false
  vars_files:
    - ../group_vars/all/vars.yml
    - ../group_vars/all/vault.yml
  tasks:
    - name: Download Debian 12 LXC template (if missing)
      ansible.builtin.command:
        cmd: >-
          ssh root@{{ proxmox_host }}
          pveam download local debian-12-standard_12.7-1_amd64.tar.zst
      register: template_download
      changed_when: "'download' in template_download.stdout"
      failed_when:
        - template_download.rc != 0
        - "'already exists' not in template_download.stderr"

    - name: Create LXC container
      community.general.proxmox:
        api_host:         "{{ proxmox_host }}"
        api_user:         "{{ proxmox_api_user }}"
        api_token_id:     "{{ proxmox_api_token_id }}"
        api_token_secret: "{{ proxmox_api_token_secret }}"
        node:         "{{ proxmox_node }}"
        vmid:         "{{ lxc_id }}"
        hostname:     "{{ lxc_name }}"
        ostemplate:   "{{ lxc_template }}"
        storage:      "{{ lxc_storage }}"
        disk:         "{{ lxc_disk_size }}"
        cores:        "{{ lxc_cores }}"
        memory:       "{{ lxc_memory_mb }}"
        swap:         "{{ lxc_swap_mb }}"
        unprivileged: true
        netif:
          net0: "name=eth0,bridge=vmbr0,ip={{ lxc_ip }}/{{ lxc_cidr }},gw={{ lxc_gateway }}"
        nameserver:   "{{ lxc_nameserver }}"
        pubkey:       "{{ lookup('file', lxc_ssh_key_path) }}"
        password:     "{{ vault_lxc_root_password }}"
        onboot:       true
        state:        present

    - name: Start LXC container
      community.general.proxmox:
        api_host:         "{{ proxmox_host }}"
        api_user:         "{{ proxmox_api_user }}"
        api_token_id:     "{{ proxmox_api_token_id }}"
        api_token_secret: "{{ proxmox_api_token_secret }}"
        node:  "{{ proxmox_node }}"
        vmid:  "{{ lxc_id }}"
        state: started

    - name: Wait for SSH
      ansible.builtin.wait_for:
        host:    "{{ lxc_ip }}"
        port:    22
        timeout: 60
```

- [ ] **Step 2: Commit**

```bash
git add compute/smart_resume_lxc/playbooks/create_lxc.yml
git commit -m "feat(compute): add smart_resume_lxc create playbook"
```

---

## Task 4: Smart Resume LXC — Configure Playbook

**Files:**
- Create: `compute/smart_resume_lxc/playbooks/configure_lxc.yml`

- [ ] **Step 1: Create `compute/smart_resume_lxc/playbooks/configure_lxc.yml`**

```yaml
- name: Configure Smart Resume LXC
  hosts: smart-resume
  become: true
  vars_files:
    - ../group_vars/all/vars.yml
    - ../group_vars/all/vault.yml
  tasks:
    - name: Upgrade all packages
      ansible.builtin.apt:
        upgrade: dist
        update_cache: true

    - name: Install base packages
      ansible.builtin.apt:
        name:
          - ca-certificates
          - curl
          - gnupg
          - ufw
          - fail2ban
          - python3
          - python3-venv
          - python3-dev
          - libgomp1
        state: present

    # ── uv (Python package manager) ──────────────────────────────────────────
    - name: Install uv
      ansible.builtin.shell: curl -LsSf https://astral.sh/uv/install.sh | sh
      args:
        creates: /root/.local/bin/uv

    - name: Symlink uv to /usr/local/bin
      ansible.builtin.file:
        src: /root/.local/bin/uv
        dest: /usr/local/bin/uv
        state: link

    # ── Caddy ────────────────────────────────────────────────────────────────
    - name: Add Caddy GPG key
      ansible.builtin.get_url:
        url: https://dl.cloudsmith.io/public/caddy/stable/gpg.key
        dest: /etc/apt/keyrings/caddy-stable.asc
        mode: "0644"

    - name: Add Caddy APT repository
      ansible.builtin.apt_repository:
        repo: >
          deb [signed-by=/etc/apt/keyrings/caddy-stable.asc]
          https://dl.cloudsmith.io/public/caddy/stable/deb/debian
          any-version main

    - name: Install Caddy
      ansible.builtin.apt:
        name: caddy
        update_cache: true

    # ── Firewall ─────────────────────────────────────────────────────────────
    - name: Configure UFW — allow SSH
      community.general.ufw:
        rule: allow
        port: "22"
        proto: tcp

    - name: Configure UFW — allow HTTP
      community.general.ufw:
        rule: allow
        port: "80"
        proto: tcp

    - name: Enable UFW
      community.general.ufw:
        state: enabled
        policy: deny

    - name: Enable fail2ban
      ansible.builtin.service:
        name: fail2ban
        enabled: true
        state: started
```

- [ ] **Step 2: Commit**

```bash
git add compute/smart_resume_lxc/playbooks/configure_lxc.yml
git commit -m "feat(compute): add smart_resume_lxc configure playbook"
```

---

## Task 5: Smart Resume LXC — Templates + Deploy Playbook

**Files:**
- Create: `compute/smart_resume_lxc/templates/smart-resume-api.service.j2`
- Create: `compute/smart_resume_lxc/templates/Caddyfile.j2`
- Create: `compute/smart_resume_lxc/templates/env.j2`
- Create: `compute/smart_resume_lxc/playbooks/deploy_app.yml`

- [ ] **Step 1: Create `compute/smart_resume_lxc/templates/smart-resume-api.service.j2`**

```ini
[Unit]
Description=Smart Resume API
After=network.target

[Service]
Type=exec
User=www-data
WorkingDirectory={{ app_remote_path }}/api
EnvironmentFile={{ app_remote_path }}/api/.env
ExecStart={{ app_remote_path }}/api/.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port {{ api_port }}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 2: Create `compute/smart_resume_lxc/templates/Caddyfile.j2`**

```
:80 {
    handle /api/* {
        reverse_proxy 127.0.0.1:{{ api_port }}
    }

    root * {{ app_remote_path }}/web
    file_server
}
```

- [ ] **Step 3: Create `compute/smart_resume_lxc/templates/env.j2`**

Adapted from the existing `compute/smart_resume_vm/templates/env.j2`:

```
OLLAMA_URL={{ vault_ollama_url }}
SESSION_SECRET={{ vault_session_secret }}
CORS_ORIGINS=http://{{ lxc_ip }},https://smart-resume.mati-lab.online
CHAT_MODEL=qwen2.5:7b-instruct
EMBED_MODEL=nomic-embed-text
TURNSTILE_SECRET_KEY={{ vault_turnstile_secret_key }}
```

- [ ] **Step 4: Create `compute/smart_resume_lxc/playbooks/deploy_app.yml`**

```yaml
- name: Deploy Smart Resume
  hosts: smart-resume
  gather_facts: false
  vars_files:
    - ../group_vars/all/vars.yml
    - ../group_vars/all/vault.yml

  pre_tasks:
    - name: Lint API code (ruff)
      ansible.builtin.command:
        cmd: uv run ruff check src/ tests/
        chdir: "{{ app_repo_path }}/apps/api"
      delegate_to: localhost
      run_once: true
      changed_when: false

    - name: Run API tests (pytest)
      ansible.builtin.command:
        cmd: uv run pytest tests/ -q --tb=short
        chdir: "{{ app_repo_path }}/apps/api"
      delegate_to: localhost
      run_once: true
      changed_when: false

    - name: Build Astro static site
      ansible.builtin.command:
        cmd: yarn build
        chdir: "{{ app_repo_path }}/apps/web"
      delegate_to: localhost
      run_once: true
      changed_when: true
      environment:
        PUBLIC_TURNSTILE_SITE_KEY: "{{ vault_turnstile_site_key }}"

  tasks:
    - name: Create app directories
      ansible.builtin.file:
        path: "{{ item }}"
        state: directory
        owner: www-data
        group: www-data
        mode: "0755"
      loop:
        - "{{ app_remote_path }}/api"
        - "{{ app_remote_path }}/web"
      become: true

    - name: Rsync API source
      ansible.posix.synchronize:
        src: "{{ app_repo_path }}/apps/api/{{ item }}"
        dest: "{{ app_remote_path }}/api/"
        delete: true
        rsync_opts:
          - "--exclude=__pycache__"
          - "--exclude=.venv"
          - "--exclude=.ruff_cache"
      loop:
        - pyproject.toml
        - uv.lock
        - src/

    - name: Rsync Astro static files
      ansible.posix.synchronize:
        src: "{{ app_repo_path }}/apps/web/dist/"
        dest: "{{ app_remote_path }}/web/"
        delete: true

    - name: Install Python dependencies
      ansible.builtin.command:
        cmd: uv sync --frozen --no-dev
        chdir: "{{ app_remote_path }}/api"
      become: true
      become_user: www-data
      changed_when: true

    - name: Write API .env
      ansible.builtin.template:
        src: ../templates/env.j2
        dest: "{{ app_remote_path }}/api/.env"
        owner: www-data
        mode: "0600"
      become: true

    - name: Write Caddyfile
      ansible.builtin.template:
        src: ../templates/Caddyfile.j2
        dest: /etc/caddy/Caddyfile
        owner: root
        mode: "0644"
      become: true
      notify: Reload Caddy

    - name: Write systemd unit
      ansible.builtin.template:
        src: ../templates/smart-resume-api.service.j2
        dest: /etc/systemd/system/smart-resume-api.service
        owner: root
        mode: "0644"
      become: true
      notify: Restart API

    - name: Enable and start API service
      ansible.builtin.systemd:
        name: smart-resume-api
        enabled: true
        state: started
        daemon_reload: true
      become: true

    - name: Enable and start Caddy
      ansible.builtin.systemd:
        name: caddy
        enabled: true
        state: started
      become: true

  handlers:
    - name: Reload Caddy
      ansible.builtin.systemd:
        name: caddy
        state: reloaded
      become: true

    - name: Restart API
      ansible.builtin.systemd:
        name: smart-resume-api
        state: restarted
        daemon_reload: true
      become: true
```

- [ ] **Step 5: Commit**

```bash
git add compute/smart_resume_lxc/templates/ compute/smart_resume_lxc/playbooks/deploy_app.yml
git commit -m "feat(compute): add smart_resume_lxc templates and deploy playbook"
```

---

## Task 6: Restorate LXC — Scaffolding

**Files:**
- Create: `compute/restorate_lxc/ansible.cfg`
- Create: `compute/restorate_lxc/requirements.yml`
- Create: `compute/restorate_lxc/inventory/hosts.yml`
- Create: `compute/restorate_lxc/group_vars/all/vars.yml`
- Create: `compute/restorate_lxc/group_vars/all/vault.yml`
- Create: `compute/restorate_lxc/group_vars/all/vault.yml.example`
- Create: `compute/restorate_lxc/Makefile`
- Create: `compute/restorate_lxc/playbooks/site.yml`

- [ ] **Step 1: Create `compute/restorate_lxc/ansible.cfg`**

```ini
[defaults]
inventory          = inventory/hosts.yml
roles_path         = roles
vault_password_file = ~/.vault_pass
host_key_checking  = False
stdout_callback    = default
result_format      = yaml
```

- [ ] **Step 2: Create `compute/restorate_lxc/requirements.yml`**

```yaml
collections:
  - name: community.general    # proxmox (LXC), ufw
  - name: ansible.posix        # synchronize
```

- [ ] **Step 3: Create `compute/restorate_lxc/inventory/hosts.yml`**

```yaml
all:
  hosts:
    localhost:
      ansible_connection: local
    restorate:
      ansible_host: "192.168.1.211"    # temporary — change to .203 after cutover
      ansible_user: root
      ansible_ssh_private_key_file: ~/.ssh/id_ed25519
      ansible_python_interpreter: /usr/bin/python3
```

- [ ] **Step 4: Create `compute/restorate_lxc/group_vars/all/vars.yml`**

```yaml
# Proxmox connection
proxmox_host: "192.168.1.184"
proxmox_node: "proxmox"
proxmox_api_user: "root@pam"
proxmox_api_token_id:     "{{ vault_proxmox_api_token_id }}"
proxmox_api_token_secret: "{{ vault_proxmox_api_token_secret }}"

# LXC spec
lxc_id: 111
lxc_name: "restorate"
lxc_template: "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
lxc_cores: 2
lxc_memory_mb: 2048
lxc_swap_mb: 256
lxc_disk_size: "20"
lxc_storage: "local-lvm"

# Network (static)
lxc_ip: "192.168.1.211"          # temporary — change to .203 after cutover
lxc_ip_final: "192.168.1.203"    # documented target
lxc_gateway: "192.168.1.1"
lxc_nameserver: "192.168.1.1"
lxc_cidr: 24

# SSH
lxc_ssh_key_path: "~/.ssh/id_ed25519.pub"

# App
app_repo_path: "/home/gooral/Projects/resto-rate"
app_remote_path: "/opt/restorate"

# API / frontend URLs
api_host: "restorate.mati-lab.online"
vite_api_url: "https://restorate.mati-lab.online"
api_port: 3001
web_port: 3000

# PostgreSQL
postgres_db: "restorate"
postgres_user: "restorate"

# Valkey
valkey_port: 6379

# Invite system
invite_required: true

# Monitoring
loki_push_url: "http://192.168.1.252:3100/loki/api/v1/push"
```

- [ ] **Step 5: Create vault.yml.example**

```yaml
# Copy to vault.yml, fill in values, then encrypt:
#   ansible-vault encrypt group_vars/all/vault.yml
vault_proxmox_api_token_id: "root@pam!ansible"
vault_proxmox_api_token_secret: "<token-secret-from-proxmox>"
vault_lxc_root_password: "<strong-password>"
vault_postgres_password: "<strong-password>"
vault_valkey_password: "<strong-password>"
vault_google_places_api_key: "<google-places-api-key>"
vault_google_client_id: "<google-oauth-client-id>"
vault_session_secret: "<random-32+-char-string>"
vault_invite_secret_pepper: "<random-32+-char-string>"
vault_admin_key: "<strong-secret-key>"
```

- [ ] **Step 6: Create vault file**

Copy from existing restorate_vm vault:

```bash
cd compute/restorate_lxc
mkdir -p group_vars/all
cp ../restorate_vm/group_vars/all/vault.yml group_vars/all/vault.yml
```

Then add `vault_lxc_root_password`:

```bash
ansible-vault edit group_vars/all/vault.yml
# Add: vault_lxc_root_password: "<strong-password>"
```

- [ ] **Step 7: Create `compute/restorate_lxc/Makefile`**

```makefile
.PHONY: provision configure deploy install-deps \
        db-backup db-restore db-clean db-shell

# ── SSH config ───────────────────────────────────────────────────────────────
SSH_KEY  ?= ~/.ssh/id_ed25519
SSH_HOST ?= root@192.168.1.211
SSH      := ssh -i $(SSH_KEY) -o StrictHostKeyChecking=accept-new $(SSH_HOST)
SSH_TTY  := ssh -t -i $(SSH_KEY) -o StrictHostKeyChecking=accept-new $(SSH_HOST)

DB_NAME  ?= restorate
DB_USER  ?= restorate
APP_DIR  ?= /opt/restorate

BACKUP_DIR := ./backups

# ── Provisioning ─────────────────────────────────────────────────────────────

install-deps:
	ansible-galaxy collection install -r requirements.yml

provision: install-deps
	ansible-playbook playbooks/site.yml

configure:
	ansible-playbook playbooks/configure_lxc.yml

deploy:
	ansible-playbook playbooks/deploy_app.yml

# ── Database operations ──────────────────────────────────────────────────────
# Commands run directly on the LXC (no Docker container).

db-backup:
	@mkdir -p $(BACKUP_DIR)
	@set -e; \
	 TIMESTAMP=$$(date +%Y%m%d_%H%M%S); \
	 OUTFILE=$(BACKUP_DIR)/$(DB_NAME)_$$TIMESTAMP.dump; \
	 TMPFILE=$$OUTFILE.tmp; \
	 echo "Backing up to $$OUTFILE ..."; \
	 $(SSH) "sudo -u postgres pg_dump -Fc $(DB_NAME)" > $$TMPFILE && \
	 mv $$TMPFILE $$OUTFILE && \
	 echo "Done — $$(du -sh $$OUTFILE | cut -f1)" || { rm -f $$TMPFILE; exit 1; }

db-restore:
	@test -n "$(FILE)" || { echo "Usage: make db-restore FILE=<path/to/dump>"; exit 1; }
	@test -f "$(FILE)" || { echo "File not found: $(FILE)"; exit 1; }
	@echo "Restoring $(FILE) into $(DB_NAME) ..."
	cat "$(FILE)" | $(SSH) "sudo -u postgres pg_restore -d $(DB_NAME) --clean --if-exists --no-owner --exit-on-error"
	@echo "Done. Restarting API to re-run migrations ..."
	$(SSH) "systemctl restart restorate-api"

db-clean:
	@echo "WARNING: This will wipe all data in $(DB_NAME). Press Ctrl-C within 5 seconds to abort."
	@sleep 5
	$(SSH) "sudo -u postgres psql -d $(DB_NAME) -v ON_ERROR_STOP=1 -X \
	        -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO $(DB_USER);'"
	@echo "Schema wiped. Restarting API ..."
	$(SSH) "systemctl restart restorate-api"

db-shell:
	$(SSH_TTY) "sudo -u postgres psql $(DB_NAME)"
```

- [ ] **Step 8: Create `compute/restorate_lxc/playbooks/site.yml`**

```yaml
- import_playbook: create_lxc.yml
- import_playbook: configure_lxc.yml
- import_playbook: deploy_app.yml
```

- [ ] **Step 9: Update `compute/.gitignore`**

Add the new vault files:

```
smart_resume_vm/group_vars/all/vault.yml
sonarqube_vm/group_vars/all/vault.yml
smart_resume_lxc/group_vars/all/vault.yml
restorate_lxc/group_vars/all/vault.yml
proxmox_host/group_vars/all/vault.yml
```

- [ ] **Step 10: Commit**

```bash
git add compute/restorate_lxc/ansible.cfg compute/restorate_lxc/requirements.yml \
  compute/restorate_lxc/inventory/ compute/restorate_lxc/group_vars/all/vars.yml \
  compute/restorate_lxc/group_vars/all/vault.yml.example \
  compute/restorate_lxc/Makefile compute/restorate_lxc/playbooks/site.yml \
  compute/.gitignore
git commit -m "feat(compute): scaffold restorate_lxc directory"
```

---

## Task 7: Restorate LXC — Create Playbook

**Files:**
- Create: `compute/restorate_lxc/playbooks/create_lxc.yml`

- [ ] **Step 1: Create `compute/restorate_lxc/playbooks/create_lxc.yml`**

```yaml
- name: Create Restorate LXC container
  hosts: localhost
  gather_facts: false
  vars_files:
    - ../group_vars/all/vars.yml
    - ../group_vars/all/vault.yml
  tasks:
    - name: Download Debian 12 LXC template (if missing)
      ansible.builtin.command:
        cmd: >-
          ssh root@{{ proxmox_host }}
          pveam download local debian-12-standard_12.7-1_amd64.tar.zst
      register: template_download
      changed_when: "'download' in template_download.stdout"
      failed_when:
        - template_download.rc != 0
        - "'already exists' not in template_download.stderr"

    - name: Create LXC container
      community.general.proxmox:
        api_host:         "{{ proxmox_host }}"
        api_user:         "{{ proxmox_api_user }}"
        api_token_id:     "{{ proxmox_api_token_id }}"
        api_token_secret: "{{ proxmox_api_token_secret }}"
        node:         "{{ proxmox_node }}"
        vmid:         "{{ lxc_id }}"
        hostname:     "{{ lxc_name }}"
        ostemplate:   "{{ lxc_template }}"
        storage:      "{{ lxc_storage }}"
        disk:         "{{ lxc_disk_size }}"
        cores:        "{{ lxc_cores }}"
        memory:       "{{ lxc_memory_mb }}"
        swap:         "{{ lxc_swap_mb }}"
        unprivileged: true
        netif:
          net0: "name=eth0,bridge=vmbr0,ip={{ lxc_ip }}/{{ lxc_cidr }},gw={{ lxc_gateway }}"
        nameserver:   "{{ lxc_nameserver }}"
        pubkey:       "{{ lookup('file', lxc_ssh_key_path) }}"
        password:     "{{ vault_lxc_root_password }}"
        onboot:       true
        state:        present

    - name: Start LXC container
      community.general.proxmox:
        api_host:         "{{ proxmox_host }}"
        api_user:         "{{ proxmox_api_user }}"
        api_token_id:     "{{ proxmox_api_token_id }}"
        api_token_secret: "{{ proxmox_api_token_secret }}"
        node:  "{{ proxmox_node }}"
        vmid:  "{{ lxc_id }}"
        state: started

    - name: Wait for SSH
      ansible.builtin.wait_for:
        host:    "{{ lxc_ip }}"
        port:    22
        timeout: 60
```

- [ ] **Step 2: Commit**

```bash
git add compute/restorate_lxc/playbooks/create_lxc.yml
git commit -m "feat(compute): add restorate_lxc create playbook"
```

---

## Task 8: Restorate LXC — Configure Playbook

**Files:**
- Create: `compute/restorate_lxc/playbooks/configure_lxc.yml`

- [ ] **Step 1: Create `compute/restorate_lxc/playbooks/configure_lxc.yml`**

```yaml
- name: Configure Restorate LXC
  hosts: restorate
  become: true
  vars_files:
    - ../group_vars/all/vars.yml
    - ../group_vars/all/vault.yml
  tasks:
    - name: Upgrade all packages
      ansible.builtin.apt:
        upgrade: dist
        update_cache: true

    - name: Install base packages
      ansible.builtin.apt:
        name:
          - ca-certificates
          - curl
          - gnupg
          - ufw
          - fail2ban
        state: present

    - name: Ensure APT keyrings directory exists
      ansible.builtin.file:
        path: /etc/apt/keyrings
        state: directory
        mode: "0755"

    # ── PostgreSQL 17 (PGDG repo) ───────────────────────────────────────────
    - name: Add PostgreSQL GPG key
      ansible.builtin.get_url:
        url: https://www.postgresql.org/media/keys/ACCC4CF8.asc
        dest: /etc/apt/keyrings/postgresql.asc
        mode: "0644"

    - name: Add PostgreSQL APT repository
      ansible.builtin.apt_repository:
        repo: >
          deb [signed-by=/etc/apt/keyrings/postgresql.asc]
          https://apt.postgresql.org/pub/repos/apt
          bookworm-pgdg main

    - name: Install PostgreSQL 17
      ansible.builtin.apt:
        name: postgresql-17
        update_cache: true

    - name: Create PostgreSQL user
      ansible.builtin.command:
        cmd: >-
          sudo -u postgres psql -tAc
          "DO $$ BEGIN
            IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='{{ postgres_user }}') THEN
              CREATE ROLE {{ postgres_user }} WITH LOGIN PASSWORD '{{ vault_postgres_password }}';
            END IF;
          END $$;"
      changed_when: false

    - name: Create PostgreSQL database
      ansible.builtin.command:
        cmd: >-
          sudo -u postgres psql -tAc
          "SELECT 1 FROM pg_database WHERE datname='{{ postgres_db }}'"
      register: db_exists
      changed_when: false

    - name: Create database if not exists
      ansible.builtin.command:
        cmd: >-
          sudo -u postgres createdb -O {{ postgres_user }} {{ postgres_db }}
      when: db_exists.stdout != "1"

    # ── Valkey ───────────────────────────────────────────────────────────────
    - name: Add Valkey GPG key
      ansible.builtin.get_url:
        url: https://packages.valkey.io/gpg
        dest: /etc/apt/keyrings/valkey.asc
        mode: "0644"

    - name: Add Valkey APT repository
      ansible.builtin.apt_repository:
        repo: >
          deb [signed-by=/etc/apt/keyrings/valkey.asc]
          https://packages.valkey.io/deb
          bookworm main

    - name: Install Valkey
      ansible.builtin.apt:
        name: valkey
        update_cache: true

    # ── Node.js 22 LTS (NodeSource) ─────────────────────────────────────────
    - name: Add NodeSource GPG key
      ansible.builtin.get_url:
        url: https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key
        dest: /etc/apt/keyrings/nodesource.asc
        mode: "0644"

    - name: Add NodeSource APT repository
      ansible.builtin.apt_repository:
        repo: >
          deb [signed-by=/etc/apt/keyrings/nodesource.asc]
          https://deb.nodesource.com/node_22.x
          nodistro main

    - name: Install Node.js
      ansible.builtin.apt:
        name: nodejs
        update_cache: true

    # ── Caddy ────────────────────────────────────────────────────────────────
    - name: Add Caddy GPG key
      ansible.builtin.get_url:
        url: https://dl.cloudsmith.io/public/caddy/stable/gpg.key
        dest: /etc/apt/keyrings/caddy-stable.asc
        mode: "0644"

    - name: Add Caddy APT repository
      ansible.builtin.apt_repository:
        repo: >
          deb [signed-by=/etc/apt/keyrings/caddy-stable.asc]
          https://dl.cloudsmith.io/public/caddy/stable/deb/debian
          any-version main

    - name: Install Caddy
      ansible.builtin.apt:
        name: caddy
        update_cache: true

    # ── Application user ─────────────────────────────────────────────────────
    - name: Create restorate system user
      ansible.builtin.user:
        name: restorate
        system: true
        shell: /bin/false
        home: /opt/restorate
        create_home: false

    # ── Firewall ─────────────────────────────────────────────────────────────
    - name: Configure UFW — allow SSH
      community.general.ufw:
        rule: allow
        port: "22"
        proto: tcp

    - name: Configure UFW — allow HTTP
      community.general.ufw:
        rule: allow
        port: "80"
        proto: tcp

    - name: Configure UFW — allow Prometheus scrape from LAN
      community.general.ufw:
        rule: allow
        port: "{{ api_port | string }}"
        proto: tcp
        src: "192.168.1.0/24"

    - name: Enable UFW
      community.general.ufw:
        state: enabled
        policy: deny

    - name: Enable fail2ban
      ansible.builtin.service:
        name: fail2ban
        enabled: true
        state: started
```

- [ ] **Step 2: Commit**

```bash
git add compute/restorate_lxc/playbooks/configure_lxc.yml
git commit -m "feat(compute): add restorate_lxc configure playbook"
```

---

## Task 9: Restorate LXC — Templates

**Files:**
- Create: `compute/restorate_lxc/templates/restorate-api.service.j2`
- Create: `compute/restorate_lxc/templates/restorate-web.service.j2`
- Create: `compute/restorate_lxc/templates/Caddyfile.j2`
- Create: `compute/restorate_lxc/templates/api.env.j2`
- Create: `compute/restorate_lxc/templates/valkey.conf.j2`
- Create: `compute/restorate_lxc/templates/promtail-config.yml.j2`
- Create: `compute/restorate_lxc/templates/pg_backup.service.j2`
- Create: `compute/restorate_lxc/templates/pg_backup.timer.j2`

- [ ] **Step 1: Create `compute/restorate_lxc/templates/restorate-api.service.j2`**

```ini
[Unit]
Description=Restorate API
After=network.target postgresql.service valkey.service
Requires=postgresql.service valkey.service

[Service]
Type=exec
User=restorate
EnvironmentFile={{ app_remote_path }}/api.env
ExecStart={{ app_remote_path }}/api
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 2: Create `compute/restorate_lxc/templates/restorate-web.service.j2`**

```ini
[Unit]
Description=Restorate Web (SvelteKit SSR)
After=network.target restorate-api.service

[Service]
Type=exec
User=restorate
WorkingDirectory={{ app_remote_path }}/web
Environment=HOST=0.0.0.0
Environment=PORT={{ web_port }}
Environment=ORIGIN=https://{{ api_host }}
ExecStart=/usr/bin/node index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 3: Create `compute/restorate_lxc/templates/Caddyfile.j2`**

Adapted from existing `compute/restorate_vm/templates/Caddyfile.j2`:

```
{
    log default {
        output stdout
        format json
        level INFO
    }
}

:80 {
    header -Server
    encode zstd gzip

    # Block Prometheus metrics from public access
    handle /metrics {
        respond 404
    }

    # Connect-RPC service routes
    @connect_rpc path_regexp ^/[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\.[A-Z]
    handle @connect_rpc {
        reverse_proxy 127.0.0.1:{{ api_port }}
    }

    # REST API routes
    handle /place-photo {
        reverse_proxy 127.0.0.1:{{ api_port }}
    }
    handle /health {
        reverse_proxy 127.0.0.1:{{ api_port }}
    }
    handle /export/reviews {
        reverse_proxy 127.0.0.1:{{ api_port }}
    }
    handle /admin/invite-secret {
        reverse_proxy 127.0.0.1:{{ api_port }}
    }

    # SvelteKit frontend
    handle {
        reverse_proxy 127.0.0.1:{{ web_port }}
    }
}
```

- [ ] **Step 4: Create `compute/restorate_lxc/templates/api.env.j2`**

Adapted from existing `compute/restorate_vm/templates/api.env.j2` — changes: `POSTGRES_HOST` is now `localhost`, `VALKEY_URI` is now `localhost:6379`:

```
ENV=prod
POSTGRES_HOST=localhost
POSTGRES_USER={{ postgres_user }}
POSTGRES_PASSWORD={{ vault_postgres_password }}
POSTGRES_DB={{ postgres_db }}
POSTGRES_PORT=5432
VALKEY_URI=localhost:{{ valkey_port }}
VALKEY_PASSWORD={{ vault_valkey_password }}
API_PORT={{ api_port }}
API_HOST={{ api_host }}
API_PROTOCOL=https
WEB_UI_PORT=443
GOOGLE_PLACES_API_KEY={{ vault_google_places_api_key }}
GOOGLE_CLIENT_ID={{ vault_google_client_id }}
SESSION_SECRET={{ vault_session_secret }}
SEED=true
LOG_LEVEL=INFO
{% if invite_required %}
INVITE_REQUIRED=true
INVITE_SECRET_PEPPER={{ vault_invite_secret_pepper }}
ADMIN_KEY={{ vault_admin_key }}
{% endif %}
```

- [ ] **Step 5: Create `compute/restorate_lxc/templates/valkey.conf.j2`**

Same as existing `compute/restorate_vm/templates/valkey.conf.j2`:

```
bind 127.0.0.1
port {{ valkey_port }}
protected-mode yes

save 60 1
dir /var/lib/valkey

requirepass {{ vault_valkey_password }}
```

Note: `bind` changed from `0.0.0.0` to `127.0.0.1` — no need for network access when everything is on the same host. `dir` changed to the system package default.

- [ ] **Step 6: Create `compute/restorate_lxc/templates/promtail-config.yml.j2`**

Replaces Docker socket scraping with systemd journal:

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: {{ loki_push_url }}

scrape_configs:
  - job_name: journal
    journal:
      json: false
      max_age: 12h
      labels:
        job: restorate
        host: restorate
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: unit
      # Only ship logs from our services
      - source_labels: ['__journal__systemd_unit']
        regex: '(restorate-api|restorate-web|caddy|postgresql|valkey)\.service'
        action: keep
```

- [ ] **Step 7: Create `compute/restorate_lxc/templates/pg_backup.service.j2`**

```ini
[Unit]
Description=PostgreSQL daily backup for {{ postgres_db }}

[Service]
Type=oneshot
User=postgres
ExecStart=/bin/bash -c 'pg_dump -Fc {{ postgres_db }} > {{ app_remote_path }}/backups/{{ postgres_db }}-$(date +%%F).dump'
ExecStartPost=/usr/bin/find {{ app_remote_path }}/backups -name '*.dump' -mtime +7 -delete
```

- [ ] **Step 8: Create `compute/restorate_lxc/templates/pg_backup.timer.j2`**

```ini
[Unit]
Description=Daily PostgreSQL backup timer

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

- [ ] **Step 9: Commit**

```bash
git add compute/restorate_lxc/templates/
git commit -m "feat(compute): add restorate_lxc templates — systemd units, Caddy, env, promtail, pg backup"
```

---

## Task 10: Restorate LXC — Deploy Playbook

**Files:**
- Create: `compute/restorate_lxc/playbooks/deploy_app.yml`

- [ ] **Step 1: Create `compute/restorate_lxc/playbooks/deploy_app.yml`**

```yaml
- name: Deploy Restorate
  hosts: restorate
  gather_facts: false
  vars:
    clean_deploy: false
  vars_files:
    - ../group_vars/all/vars.yml
    - ../group_vars/all/vault.yml

  pre_tasks:
    - name: Clean deploy — stop services and wipe database
      when: clean_deploy | bool
      block:
        - name: Stop application services
          ansible.builtin.systemd:
            name: "{{ item }}"
            state: stopped
          loop:
            - restorate-api
            - restorate-web
          failed_when: false
          become: true
        - name: Wipe database
          ansible.builtin.command:
            cmd: >-
              sudo -u postgres psql -d {{ postgres_db }} -v ON_ERROR_STOP=1 -X
              -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO {{ postgres_user }};"
          become: true

    - name: Generate protobuf code
      ansible.builtin.command:
        cmd: buf generate --template apps/api/buf.gen.yaml
        chdir: "{{ app_repo_path }}"
      delegate_to: localhost
      run_once: true
      changed_when: true

    - name: Build Go API binary
      ansible.builtin.command:
        cmd: go build -ldflags="-s -w" -o /tmp/restorate-api ./src
        chdir: "{{ app_repo_path }}/apps/api"
      delegate_to: localhost
      run_once: true
      changed_when: true
      environment:
        CGO_ENABLED: "0"
        GOOS: linux
        GOARCH: amd64

    - name: Generate web protobuf code
      ansible.builtin.command:
        cmd: bunx nx run protos:generate:web
        chdir: "{{ app_repo_path }}"
      delegate_to: localhost
      run_once: true
      changed_when: true

    - name: Build SvelteKit app
      ansible.builtin.command:
        cmd: bunx vite build
        chdir: "{{ app_repo_path }}/apps/web"
      delegate_to: localhost
      run_once: true
      changed_when: true
      environment:
        VITE_API_URL: "{{ vite_api_url }}"

    - name: Install production node_modules
      ansible.builtin.command:
        cmd: bun install --production --frozen-lockfile
        chdir: "{{ app_repo_path }}"
      delegate_to: localhost
      run_once: true
      changed_when: true

  tasks:
    - name: Create app directories
      ansible.builtin.file:
        path: "{{ item }}"
        state: directory
        owner: restorate
        group: restorate
        mode: "0755"
      loop:
        - "{{ app_remote_path }}"
        - "{{ app_remote_path }}/web"
        - "{{ app_remote_path }}/backups"
      become: true

    - name: Copy Go API binary
      ansible.builtin.copy:
        src: /tmp/restorate-api
        dest: "{{ app_remote_path }}/api"
        owner: restorate
        group: restorate
        mode: "0755"
      become: true
      notify: Restart API

    - name: Rsync SvelteKit build
      ansible.posix.synchronize:
        src: "{{ app_repo_path }}/apps/web/build/"
        dest: "{{ app_remote_path }}/web/"
        delete: true
        rsync_opts:
          - "--exclude=node_modules"
      notify: Restart Web

    - name: Rsync production node_modules
      ansible.posix.synchronize:
        src: "{{ app_repo_path }}/node_modules/"
        dest: "{{ app_remote_path }}/web/node_modules/"
        delete: true

    - name: Write Valkey config
      ansible.builtin.template:
        src: ../templates/valkey.conf.j2
        dest: /etc/valkey/valkey.conf
        owner: root
        mode: "0644"
      become: true
      notify: Restart Valkey

    - name: Write Caddyfile
      ansible.builtin.template:
        src: ../templates/Caddyfile.j2
        dest: /etc/caddy/Caddyfile
        owner: root
        mode: "0644"
      become: true
      notify: Reload Caddy

    - name: Write Promtail config
      ansible.builtin.template:
        src: ../templates/promtail-config.yml.j2
        dest: /etc/promtail/config.yml
        owner: root
        mode: "0644"
      become: true
      notify: Restart Promtail

    - name: Write API .env
      ansible.builtin.template:
        src: ../templates/api.env.j2
        dest: "{{ app_remote_path }}/api.env"
        owner: restorate
        mode: "0600"
      become: true
      notify: Restart API

    - name: Write systemd units
      ansible.builtin.template:
        src: "../templates/{{ item }}"
        dest: "/etc/systemd/system/{{ item | regex_replace('\\.j2$', '') }}"
        owner: root
        mode: "0644"
      loop:
        - restorate-api.service.j2
        - restorate-web.service.j2
        - pg_backup.service.j2
        - pg_backup.timer.j2
      become: true
      notify: Daemon reload

    - name: Enable and start services
      ansible.builtin.systemd:
        name: "{{ item }}"
        enabled: true
        state: started
        daemon_reload: true
      loop:
        - valkey
        - postgresql
        - restorate-api
        - restorate-web
        - caddy
        - pg_backup.timer
      become: true

    # ── Promtail ─────────────────────────────────────────────────────────────
    - name: Download Promtail binary
      ansible.builtin.get_url:
        url: "https://github.com/grafana/loki/releases/download/v3.5.0/promtail-linux-amd64.zip"
        dest: /tmp/promtail.zip
      become: true

    - name: Unzip Promtail
      ansible.builtin.unarchive:
        src: /tmp/promtail.zip
        dest: /usr/local/bin/
        remote_src: true
        mode: "0755"
      become: true

    - name: Rename Promtail binary
      ansible.builtin.command:
        cmd: mv /usr/local/bin/promtail-linux-amd64 /usr/local/bin/promtail
        creates: /usr/local/bin/promtail
      become: true

    - name: Create Promtail directories
      ansible.builtin.file:
        path: "{{ item }}"
        state: directory
        mode: "0755"
      loop:
        - /etc/promtail
        - /var/lib/promtail
      become: true

    - name: Write Promtail systemd unit
      ansible.builtin.copy:
        dest: /etc/systemd/system/promtail.service
        content: |
          [Unit]
          Description=Promtail Log Agent
          After=network.target

          [Service]
          Type=exec
          ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/config.yml
          Restart=on-failure
          RestartSec=5

          [Install]
          WantedBy=multi-user.target
        mode: "0644"
      become: true
      notify: Restart Promtail

    - name: Enable and start Promtail
      ansible.builtin.systemd:
        name: promtail
        enabled: true
        state: started
        daemon_reload: true
      become: true

  handlers:
    - name: Daemon reload
      ansible.builtin.systemd:
        daemon_reload: true
      become: true

    - name: Restart API
      ansible.builtin.systemd:
        name: restorate-api
        state: restarted
      become: true

    - name: Restart Web
      ansible.builtin.systemd:
        name: restorate-web
        state: restarted
      become: true

    - name: Restart Valkey
      ansible.builtin.systemd:
        name: valkey
        state: restarted
      become: true

    - name: Reload Caddy
      ansible.builtin.systemd:
        name: caddy
        state: reloaded
      become: true

    - name: Restart Promtail
      ansible.builtin.systemd:
        name: promtail
        state: restarted
      become: true
```

- [ ] **Step 2: Commit**

```bash
git add compute/restorate_lxc/playbooks/deploy_app.yml
git commit -m "feat(compute): add restorate_lxc deploy playbook"
```

---

## Task 11: Network Stack Updates

**Files:**
- Modify: `network/caddy/Caddyfile:192-199`
- Modify: `network/grafana/provisioning/dashboards/restorate.json:597,619,639`

- [ ] **Step 1: Remove SonarQube block from Caddyfile**

Remove lines 192-199 from `network/caddy/Caddyfile`:

```
    @sonarqube host sonarqube.mati-lab.online
    handle @sonarqube {
        reverse_proxy 192.168.1.201:9000 {
            header_up Host {host}
            header_up X-Forwarded-Proto https
            header_up X-Forwarded-Ssl on
        }
    }
```

- [ ] **Step 2: Update Grafana dashboard log queries**

In `network/grafana/provisioning/dashboards/restorate.json`, change three Loki queries:

Line 597: `{compose_project="restorate"}` → `{job="restorate"}`

Line 619: `sum(rate({compose_project="restorate"} |= "error" [5m]))` → `sum(rate({job="restorate"} |= "error" [5m]))`

Line 639: `sum by (level) (rate({compose_project="restorate"}[5m]))` → `sum by (level) (rate({job="restorate"}[5m]))`

- [ ] **Step 3: Commit**

```bash
git add network/caddy/Caddyfile network/grafana/provisioning/dashboards/restorate.json
git commit -m "fix(network): remove sonarqube from Caddy, update restorate log queries for LXC"
```

---

## Task 12: Cleanup — Remove Decommissioned VM Directories

**Do this AFTER successful cutover and verification of both LXC containers.**

**Files:**
- Remove: `compute/sonarqube_vm/` (entire directory)
- Remove: `compute/smart_resume_vm/` (entire directory, after LXC cutover verified)
- Remove: `compute/restorate_vm/` (entire directory, after LXC cutover verified)
- Modify: `compute/.gitignore` — remove stale vault entries

- [ ] **Step 1: Remove SonarQube VM directory**

```bash
git rm -r compute/sonarqube_vm/
```

- [ ] **Step 2: Remove smart_resume_vm directory**

```bash
git rm -r compute/smart_resume_vm/
```

- [ ] **Step 3: Remove restorate_vm directory**

```bash
git rm -r compute/restorate_vm/
```

- [ ] **Step 4: Clean up `.gitignore`**

Remove the old vault entries from `compute/.gitignore`:

```
smart_resume_vm/group_vars/all/vault.yml
sonarqube_vm/group_vars/all/vault.yml
```

Keep the new LXC vault entries.

- [ ] **Step 5: Commit**

```bash
git add -A compute/
git commit -m "chore(compute): remove decommissioned VM directories (sonarqube, smart_resume, restorate)"
```

---

## Execution Order and Dependencies

```
Task 1  (proxmox_host scaffolding + playbooks)     — do first, independent
Task 2  (smart_resume_lxc scaffolding)              — independent of Task 1
Task 3  (smart_resume_lxc create playbook)          — depends on Task 2
Task 4  (smart_resume_lxc configure playbook)       — depends on Task 3
Task 5  (smart_resume_lxc templates + deploy)       — depends on Task 4
Task 6  (restorate_lxc scaffolding)                 — independent, can parallel Task 2-5
Task 7  (restorate_lxc create playbook)             — depends on Task 6
Task 8  (restorate_lxc configure playbook)          — depends on Task 7
Task 9  (restorate_lxc templates)                   — depends on Task 8
Task 10 (restorate_lxc deploy playbook)             — depends on Task 9
Task 11 (network stack updates)                     — after cutover verification
Task 12 (cleanup old VM dirs)                       — after all cutovers verified
```

**Parallelizable:** Tasks 2-5 (smart_resume) and Tasks 6-10 (restorate) are independent and can be developed in parallel. Task 1 (proxmox_host) is also independent.

---

## Manual Steps (not automated in playbooks)

These require operator intervention and cannot be safely automated:

1. **Before starting:** Back up PostgreSQL data from restorate VM: `cd compute/restorate_vm && make db-backup`
2. **After Task 1, zfs_arc:** Reboot Proxmox host, then run `make verify-gpu`
3. **After Task 1, ollama_balloon:** Restart Ollama VM from Proxmox UI
4. **After Tasks 5/10 deploy:** Test each LXC on its temporary IP
5. **Cutover:** Stop VM, change LXC IP in vars.yml + inventory, re-run configure to update network, restart LXC
6. **After cutover:** Verify services on final IP, check Grafana dashboards, check Prometheus scrape
7. **After all verified:** Run Task 12 cleanup
