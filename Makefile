.PHONY: help init plan apply destroy fmt validate clean
.PHONY: init-all plan-all validate-modules install-provider
.DEFAULT_GOAL := help

include Makefile.common

# Delegate to unified cluster Makefile
# Pattern: make cluster.<cluster-name>.<operation>
# Examples: make cluster.public.init, make cluster.egress-zero.apply, make cluster.egress-zero2.init
# If no operation is specified (make cluster.public), defaults to apply then bootstrap-cluster
# Match pattern: cluster.<cluster-name>.<operation> where cluster-name is the directory under clusters/
cluster.%:
	@CLUSTER_NAME=$$(echo "$@" | cut -d'.' -f2); \
	OPERATION=$$(echo "$@" | cut -d'.' -f3-); \
	if [ -z "$$CLUSTER_NAME" ]; then \
		echo "$(YELLOW)Error: Invalid pattern. Use: make cluster.<cluster-name>.<operation>$(NC)"; \
		echo "$(YELLOW)Examples: make cluster.public.init, make cluster.egress-zero.apply$(NC)"; \
		echo "$(YELLOW)Or: make cluster.public (runs apply then bootstrap-cluster)$(NC)"; \
		exit 1; \
	fi; \
	if [ ! -d "clusters/$$CLUSTER_NAME" ]; then \
		echo "$(YELLOW)Error: Cluster directory 'clusters/$$CLUSTER_NAME' does not exist$(NC)"; \
		echo "$(YELLOW)Available clusters:$$(ls -1 clusters/ 2>/dev/null | sed 's/^/  - /' || echo '  (none)')$(NC)"; \
		exit 1; \
	fi; \
	if [ -z "$$OPERATION" ]; then \
		echo "$(BLUE)No operation specified. Running default: apply then bootstrap-cluster$(NC)"; \
		$(MAKE) -f Makefile.cluster CLUSTER_NAME=$$CLUSTER_NAME apply bootstrap-cluster; \
	else \
		$(MAKE) -f Makefile.cluster CLUSTER_NAME=$$CLUSTER_NAME $$OPERATION; \
	fi


help: ## Show this help message
	@echo "$(BLUE)ROSA HCP Infrastructure - Root Makefile$(NC)"
	@echo ""
	@echo "$(GREEN)Usage:$(NC) make cluster.<type>.<operation> [CLUSTER=<cluster-name>]"
	@echo ""
	@echo "$(GREEN)Unified Cluster Management (Recommended):$(NC)"
	@echo "  make cluster.public                            Apply and bootstrap cluster (default)"
	@echo "  make cluster.public.init                     Initialize public cluster"
	@echo "  make cluster.public.plan                     Plan public cluster"
	@echo "  make cluster.public.apply                    Apply public cluster"
	@echo "  make cluster.public.bootstrap-cluster        Bootstrap GitOps operator"
	@echo "  make cluster.egress-zero.init                Initialize egress-zero cluster"
	@echo "  make cluster.egress-zero.apply               Apply egress-zero cluster"
	@echo "  make cluster.egress-zero2.init               Initialize another egress-zero cluster"
	@echo "  make cluster.us-east-1-production.apply      Apply production cluster"
	@echo ""
	@echo "$(GREEN)Common Operations:$(NC)"
	@echo "  cluster.<type>                    Apply infrastructure then bootstrap GitOps (default)"
	@echo "  cluster.<type>.init              Initialize infrastructure"
	@echo "  cluster.<type>.plan              Plan infrastructure changes"
	@echo "  cluster.<type>.apply             Apply infrastructure"
	@echo "  cluster.<type>.bootstrap-cluster Bootstrap GitOps operator"
	@echo "  cluster.<type>.destroy           Destroy all resources"
	@echo "  cluster.<type>.sleep             Sleep cluster (destroy with preserved resources)"
	@echo ""
	@echo "$(GREEN)Cluster Access:$(NC)"
	@echo "  cluster.<type>.show-endpoints    Show API and console URLs"
	@echo "  cluster.<type>.show-credentials Show admin credentials and endpoints"
	@echo "  cluster.<type>.login             Login to cluster using oc CLI"
	@echo ""
	@echo "$(GREEN)Bastion & Tunnel Management:$(NC)"
	@echo "  cluster.<type>.tunnel-start      Start sshuttle VPN tunnel via bastion (egress-zero only)"
	@echo "  cluster.<type>.tunnel-stop       Stop sshuttle tunnel"
	@echo "  cluster.<type>.tunnel-status    Check if tunnel is running"
	@echo "  cluster.<type>.bastion-connect   Connect to bastion via SSM Session Manager"
	@echo ""
	@echo "$(GREEN)Global Targets:$(NC)"
	@echo "  make fmt                  Format all Terraform files"
	@echo "  make validate             Validate all Terraform modules and examples"
	@echo "  make clean                Clean Terraform files"
	@echo "  make install-provider     Install OpenShift operator provider"
	@echo ""
	@echo "$(GREEN)Destroy Protection:$(NC)"
	@echo "  Note: By default, persists_through_sleep=true keeps cluster active"
	@echo "        When persists_through_sleep=false, cluster is put to sleep (resources destroyed)"

# Code quality
fmt: ## Format all Terraform files
	@echo "$(BLUE)Formatting Terraform files...$(NC)"
	terraform fmt -recursive

validate: validate-modules ## Validate all Terraform code

validate-modules: ## Validate all modules
	@echo "$(BLUE)Validating modules...$(NC)"
	@for dir in modules/infrastructure/*/; do \
		if [ -d "$$dir" ]; then \
			echo "Validating $$dir..."; \
			cd $$dir && terraform init -backend=false >/dev/null 2>&1 && terraform validate && cd - >/dev/null || echo "  ✗ Failed: $$dir"; \
		fi; \
	done

# Install OpenShift Provider
PROVIDER_VERSION ?= 0.1.2
install-provider: ## Install OpenShift operator provider from GitHub releases (default: v0.1.2, override with PROVIDER_VERSION=0.1.2)
	@echo "$(BLUE)Installing OpenShift operator provider v$(PROVIDER_VERSION)...$(NC)"
	@if [ ! -f scripts/install-openshift-provider.sh ]; then \
		echo "$(YELLOW)Error: Installation script not found at scripts/install-openshift-provider.sh$(NC)"; \
		exit 1; \
	fi
	@chmod +x scripts/install-openshift-provider.sh
	@scripts/install-openshift-provider.sh $(PROVIDER_VERSION)
	@echo "$(GREEN)Provider installation complete$(NC)"
	@echo "$(BLUE)Next steps: Run 'terraform init' in your infrastructure directory$(NC)"

# Cleanup
clean: ## Clean Terraform files (.terraform directories and lock files)
	@echo "$(BLUE)Cleaning Terraform files...$(NC)"
	find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	find . -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	@echo "$(GREEN)Cleanup complete$(NC)"
