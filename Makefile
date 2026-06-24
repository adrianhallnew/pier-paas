.PHONY: doctor apply destroy test-infra

doctor:
	@bash scripts/doctor.sh

apply:
	cd infra && terraform init && terraform apply

destroy:
	cd infra && terraform destroy

test-infra:
	@bash scripts/smoke.sh
