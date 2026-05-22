.PHONY: install-deps zfs-arc ollama-balloon verify-gpu remove-sonarqube wol wake

install-deps:
	ansible-galaxy collection install -r requirements.yml

zfs-arc: install-deps
	ansible-playbook playbooks/zfs_arc.yml

ollama-balloon: install-deps
	ansible-playbook playbooks/ollama_balloon.yml

verify-gpu: install-deps
	ansible-playbook playbooks/verify_gpu.yml

remove-sonarqube: install-deps
	ansible-playbook playbooks/remove_sonarqube.yml

# Persist Wake-on-LAN on the primary NIC (also installs ethtool).
# One-time BIOS setting required — see playbooks/wol.yml output.
wol: install-deps
	ansible-playbook playbooks/wol.yml

# Send a magic packet to the Proxmox host. Uses PROXMOX_MAC from env.
wake:
	PROXMOX_MAC="$${PROXMOX_MAC:?set PROXMOX_MAC to the Proxmox NIC MAC}" \
		PROXMOX_BROADCAST="$${PROXMOX_BROADCAST:-192.168.1.255}" \
		scripts/wake.sh
