.PHONY: help init plan apply destroy fmt validate clean
.PHONY: init-all plan-all validate-modules validate-examples install-provider
.DEFAULT_GOAL := help

include Makefile.common

# Example directories
EXAMPLES := public egress-zero

# Delegate to example Makefiles
# Pattern: make <example>.<target>.<cluster> or make <example>.<target> (defaults to "default" cluster)
# Examples: make public.apply.dev-public-01, make public.init (uses default cluster)
# Match pattern: <example>.<target>.<cluster> where example is public or egress-zero
public.% egress-zero.%:
	@EXAMPLE=$$(echo "$@" | cut -d'.' -f1); \
	REST=$$(echo "$@" | cut -d'.' -f2-); \
	if [ ! -f "examples/$$EXAMPLE/Makefile" ]; then \
		echo "$(YELLOW)Error: Example '$$EXAMPLE' not found$(NC)"; \
		echo "$(YELLOW)Available examples: $(EXAMPLES)$(NC)"; \
		exit 1; \
	fi; \
	if echo "$$REST" | grep -q '\.'; then \
		TARGET=$$(echo "$$REST" | cut -d'.' -f1); \
		CLUSTER=$$(echo "$$REST" | cut -d'.' -f2-); \
	else \
		TARGET=$$REST; \
		CLUSTER="default"; \
		echo "$(BLUE)No cluster specified, using default cluster$(NC)"; \
	fi; \
	$(MAKE) -C examples/$$EXAMPLE $$TARGET CLUSTER=$$CLUSTER

help: ## Show this help message
	@echo "$(BLUE)ROSA HCP Infrastructure - Root Makefile$(NC)"
	@echo ""
	@echo "$(GREEN)Usage:$(NC) make <example>.<target> [.<cluster>]"
	@echo ""
	@echo "$(GREEN)Examples:$(NC)"
	@echo "  make public.init                     Initialize public example (uses default cluster)"
	@echo "  make public.init.dev-public-01       Initialize specific cluster"
	@echo "  make public.plan                    Plan public example (uses default cluster)"
	@echo "  make public.apply.dev-public-01      Apply specific cluster"
	@echo "  make egress-zero.apply.prod-egress-zero-01  Apply egress-zero cluster"
	@echo ""
	@echo "$(GREEN)Available examples:$(NC)"
	@for example in $(EXAMPLES); do \
		echo "  - $$example"; \
	done
	@echo ""
	@echo "$(GREEN)Common Targets:$(NC)"
	@echo "  <example>.init.<cluster>       Initialize both infrastructure and configuration"
	@echo "  <example>.plan.<cluster>       Plan both infrastructure and configuration"
	@echo "  <example>.apply.<cluster>      Apply both (infrastructure first, then configuration)"
	@echo "  <example>.destroy.<cluster>     Destroy all resources"
	@echo "  <example>.cleanup.<cluster>     Same as destroy (no confirmation)"
	@echo ""
	@echo "$(GREEN)Infrastructure Management:$(NC)"
	@echo "  <example>.init-infrastructure.<cluster>       Initialize infrastructure only"
	@echo "  <example>.plan-infrastructure.<cluster>       Plan infrastructure changes"
	@echo "  <example>.apply-infrastructure.<cluster>      Apply infrastructure"
	@echo "  <example>.destroy-infrastructure.<cluster>     Destroy infrastructure resources"
	@echo ""
	@echo "$(GREEN)Configuration Management:$(NC)"
	@echo "  <example>.init-configuration.<cluster>         Initialize configuration only"
	@echo "  <example>.plan-configuration.<cluster>         Plan configuration changes"
	@echo "  <example>.apply-configuration.<cluster>         Apply configuration"
	@echo "  <example>.destroy-configuration.<cluster>        Destroy configuration resources"
	@echo ""
	@echo "$(GREEN)Cluster Access:$(NC)"
	@echo "  <example>.show-endpoints.<cluster>    Show API and console URLs"
	@echo "  <example>.show-credentials.<cluster>  Show admin credentials and endpoints"
	@echo "  <example>.login.<cluster>             Login to cluster using oc CLI"
	@echo ""
	@echo "$(GREEN)Bastion & Tunnel Management:$(NC)"
	@echo "  <example>.tunnel-start.<cluster>     Start sshuttle VPN tunnel via bastion"
	@echo "  <example>.tunnel-stop.<cluster>      Stop sshuttle tunnel"
	@echo "  <example>.tunnel-status.<cluster>    Check if tunnel is running"
	@echo "  <example>.bastion-connect.<cluster>   Connect to bastion via SSM Session Manager"
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

validate: validate-modules validate-examples ## Validate all Terraform code

validate-modules: ## Validate all modules
	@echo "$(BLUE)Validating modules...$(NC)"
	@for dir in modules/infrastructure/*/ modules/configuration/*/; do \
		if [ -d "$$dir" ]; then \
			echo "Validating $$dir..."; \
			cd $$dir && terraform init -backend=false >/dev/null 2>&1 && terraform validate && cd - >/dev/null || echo "  ✗ Failed: $$dir"; \
		fi; \
	done

validate-examples: ## Validate all example clusters
	@echo "$(BLUE)Validating example clusters...$(NC)"
	@for example in $(EXAMPLES); do \
		echo "Validating $$example..."; \
		$(MAKE) -C examples/$$example validate || echo "  ✗ Failed: $$example"; \
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
