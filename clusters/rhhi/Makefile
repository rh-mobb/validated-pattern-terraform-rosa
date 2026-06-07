# clusters/rhhi/Makefile — RHHI supply chain Day-2 operations (bash + Helm)
# Cluster lifecycle: make cluster.rhhi.init plan apply login (from repo root)

SCRIPT_DIR := scripts
.PHONY: help preflight render-values install post-aws-config seed-cache run-demo status test all

help: ## Show RHHI targets
	@echo "RHHI Supply Chain — run from repo root for cluster ops: make cluster.rhhi.apply"
	@echo ""
	@grep -E '^[a-zA-Z0-9_.-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/:/' | column -t -s ':'

preflight: ## Validate CLI prerequisites
	@$(SCRIPT_DIR)/preflight.sh

render-values: ## Render values.generated.yaml from Terraform outputs
	@$(SCRIPT_DIR)/render-values.sh

install: ## Helm install/upgrade supply chain chart
	@$(SCRIPT_DIR)/install.sh

post-aws-config: ## Configure ECR enhanced scanning (post-terraform apply)
	@$(SCRIPT_DIR)/post-aws-config.sh

seed-cache: ## Pull RHHI base images through ECR pull-through cache
	@$(SCRIPT_DIR)/seed-cache.sh

run-demo: ## Run Tekton pipeline with demo-app
	@$(SCRIPT_DIR)/run-pipeline.sh

status: ## Show component status
	@$(SCRIPT_DIR)/status.sh

test: ## Run verification checks
	@$(SCRIPT_DIR)/test.sh

all: post-aws-config install ## Post-apply Day-2 setup (excludes run-demo; seed-cache is optional debug)
