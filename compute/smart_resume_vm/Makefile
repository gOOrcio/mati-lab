.PHONY: provision configure deploy

provision:
	ansible-playbook playbooks/site.yml

configure:
	ansible-playbook playbooks/configure_vm.yml

deploy:
	ansible-playbook playbooks/deploy_app.yml
