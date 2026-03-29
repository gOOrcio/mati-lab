.PHONY: provision configure deploy seed-watchlist install-deps

install-deps:
	ansible-galaxy collection install -r requirements.yml

provision: install-deps
	ansible-playbook playbooks/site.yml

configure:
	ansible-playbook playbooks/configure_vm.yml

deploy:
	ansible-playbook playbooks/deploy_app.yml

seed-watchlist:
	ansible-playbook playbooks/seed_watchlist.yml
