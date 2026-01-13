.PHONY: help init plan apply destroy fmt validate clean
.PHONY: init-all plan-all validate-modules install-provider
.DEFAULT_GOAL := help

include Makefile.common

# Delegate to unified cluster Makefile
# Pattern: make cluster.<cluster-name>.<operation>
# Examples: make cluster.public.init, make cluster.egress-zero.apply, make cluster.egress-zero2.init
# Match pattern: cluster.<cluster-name>.<operation> where cluster-name is the directory under clusters/
cluster.%:
	@CLUSTER_NAME=$$(echo "$@" | cut -d'.' -f2); \
	OPERATION=$$(echo "$@" | cut -d'.' -f3-); \
	if [ -z "$$CLUSTER_NAME" ] || [ -z "$$OPERATION" ]; then \
		echo "$(YELLOW)Error: Invalid pattern. Use: make cluster.<cluster-name>.<operation>$(NC)"; \
		echo "$(YELLOW)Examples: make cluster.public.init, make cluster.egress-zero.apply$(NC)"; \
		exit 1; \
	fi; \
	if [ ! -d "clusters/$$CLUSTER_NAME" ]; then \
		echo "$(YELLOW)Error: Cluster directory 'clusters/$$CLUSTER_NAME' does not exist$(NC)"; \
		echo "$(YELLOW)Available clusters:$$(ls -1 clusters/ 2>/dev/null | sed 's/^/  - /' || echo '  (none)')$(NC)"; \
		exit 1; \
	fi; \
	$(MAKE) -f Makefile.cluster CLUSTER_NAME=$$CLUSTER_NAME $$OPERATION


help: ## Show this help message
	@echo "$(BLUE)ROSA HCP Infrastructure - Root Makefile$(NC)"
	@echo ""
	@echo "$(GREEN)Usage:$(NC) make cluster.<type>.<operation> [CLUSTER=<cluster-name>]"
	@echo ""
	@echo "$(GREEN)Unified Cluster Management (Recommended):$(NC)"
	@echo "  make cluster.public.init                     Initialize public cluster"
	@echo "  make cluster.public.plan                     Plan public cluster"
	@echo "  make cluster.public.apply                    Apply public cluster"
	@echo "  make cluster.egress-zero.init                Initialize egress-zero cluster"
	@echo "  make cluster.egress-zero.apply               Apply egress-zero cluster"
	@echo "  make cluster.egress-zero2.init               Initialize another egress-zero cluster"
	@echo "  make cluster.us-east-1-production.apply      Apply production cluster"
	@echo ""
	@echo "$(GREEN)Common Operations:$(NC)"
	@echo "  cluster.<type>.init              Initialize both infrastructure and configuration"
	@echo "  cluster.<type>.plan              Plan both infrastructure and configuration"
	@echo "  cluster.<type>.apply             Apply both (infrastructure first, then configuration)"
	@echo "  cluster.<type>.destroy           Destroy all resources"
	@echo "  cluster.<type>.cleanup           Same as destroy (no confirmation)"
	@echo ""
	@echo "$(GREEN)Infrastructure Management:$(NC)"
	@echo "  cluster.<type>.init-infrastructure       Initialize infrastructure only"
	@echo "  cluster.<type>.plan-infrastructure       Plan infrastructure changes"
	@echo "  cluster.<type>.apply-infrastructure      Apply infrastructure"
	@echo "  cluster.<type>.destroy-infrastructure    Destroy infrastructure resources"
	@echo ""
	@echo "$(GREEN)Configuration Management:$(NC)"
	@echo "  cluster.<type>.init-configuration         Initialize configuration only"
	@echo "  cluster.<type>.plan-configuration         Plan configuration changes"
	@echo "  cluster.<type>.apply-configuration        Apply configuration"
	@echo "  cluster.<type>.destroy-configuration      Destroy configuration resources"
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
	@echo "  Note: By default, enable_destroy=false prevents accidental destruction"
	@echo "        When enable_destroy=true, resources are actually destroyed"

# Code quality
fmt: ## Format all Terraform files
	@echo "$(BLUE)Formatting Terraform files...$(NC)"
	terraform fmt -recursive

validate: validate-modules ## Validate all Terraform code

validate-modules: ## Validate all modules
	@echo "$(BLUE)Validating modules...$(NC)"
	@for dir in modules/infrastructure/*/ modules/configuration/*/; do \
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
	@echo "$(BLUE)Next steps: Run 'terraform init' in your configuration directory$(NC)"

# Cleanup
clean: ## Clean Terraform files (.terraform directories and lock files)
	@echo "$(BLUE)Cleaning Terraform files...$(NC)"
	find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	find . -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	@echo "$(GREEN)Cleanup complete$(NC)"
