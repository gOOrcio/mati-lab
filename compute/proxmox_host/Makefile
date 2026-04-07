.PHONY: install-deps zfs-arc ollama-balloon verify-gpu remove-sonarqube

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
