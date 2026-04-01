.PHONY: configure deploy security docker check

# Full setup: security + docker + all config
configure:
	ansible-playbook playbooks/configure.yml

# Security only: fail2ban, ufw, ssh hardening
security:
	ansible-playbook playbooks/configure.yml --tags security

# Docker only: install, daemon.json, registry mirror
docker:
	ansible-playbook playbooks/configure.yml --tags docker

# Dry run: show what would change
check:
	ansible-playbook playbooks/configure.yml --check --diff
