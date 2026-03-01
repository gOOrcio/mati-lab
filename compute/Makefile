.PHONY: provision configure deploy

provision:
	cd smart_resume_vm && ansible-playbook playbooks/site.yml

configure:
	cd smart_resume_vm && ansible-playbook playbooks/configure_vm.yml

deploy:
	cd smart_resume_vm && ansible-playbook playbooks/deploy_app.yml
