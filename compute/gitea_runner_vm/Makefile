.PHONY: help install create-vm configure deploy site smoke

help:
	@echo "Targets:"
	@echo "  install     - install Ansible collections"
	@echo "  create-vm   - provision the VM via Proxmox API"
	@echo "  configure   - install OS deps + docker + qemu binfmt"
	@echo "  deploy      - deploy act_runner container"
	@echo "  site        - run all of the above"
	@echo "  smoke       - run a hello-world workflow against Gitea"

install:
	ansible-galaxy collection install -r requirements.yml

create-vm:
	ansible-playbook playbooks/create_vm.yml

configure:
	ansible-playbook playbooks/configure_vm.yml -K

deploy:
	ansible-playbook playbooks/deploy_app.yml

site:
	ansible-playbook playbooks/site.yml -K

smoke:
	@echo "Push the test workflow in compute/gitea_runner_vm/smoke-test/ to a Gitea repo and watch Actions."
