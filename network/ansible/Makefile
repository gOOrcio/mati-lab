.PHONY: configure deploy security docker power netheal check backup backup-check

# Full setup: security + docker + all config
configure:
	ansible-playbook playbooks/configure.yml

# Security only: fail2ban, ufw, ssh hardening
security:
	ansible-playbook playbooks/configure.yml --tags security

# Docker only: install, daemon.json, registry mirror
docker:
	ansible-playbook playbooks/configure.yml --tags docker

# Power resilience: rpi-eeprom config + systemd watchdog
power:
	ansible-playbook playbooks/configure.yml --tags power

# Network self-heal: eth0 gateway probe + NIC reset/reboot timer (Pi 5 macb wedge)
netheal:
	ansible-playbook playbooks/configure.yml --tags netheal

# Dry run: show what would change
check:
	ansible-playbook playbooks/configure.yml --check --diff

backup:
	ansible-playbook playbooks/backup.yml --tags backup,nfs

backup-check:
	ansible-playbook playbooks/backup.yml --tags backup,nfs --check --diff
