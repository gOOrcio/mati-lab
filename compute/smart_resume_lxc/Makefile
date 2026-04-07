.PHONY: provision configure deploy install-deps

install-deps:
	ansible-galaxy collection install -r requirements.yml

provision: install-deps
	ansible-playbook playbooks/site.yml

configure:
	ansible-playbook playbooks/configure_lxc.yml

deploy:
	ansible-playbook playbooks/deploy_app.yml
