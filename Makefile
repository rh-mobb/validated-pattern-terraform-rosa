.PHONY: help init plan apply destroy fmt validate clean
.DEFAULT_GOAL := help

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Cluster directories mapping
# Maps cluster name (e.g., "public") to base directory path
define cluster_dir
$(if $(filter public,$1),clusters/examples/public,\
$(if $(filter egress-zero,$1),clusters/examples/egress-zero,\
$(error Unknown cluster: $1)))
endef

# Helper function to get cluster directory from target suffix
# Usage: $(call get_cluster_dir,$*)
get_cluster_dir = $(call cluster_dir,$*)

# Helper function to get infrastructure directory
get_infrastructure_dir = $(call cluster_dir,$1)/infrastructure

# Helper function to get configuration directory
get_configuration_dir = $(call cluster_dir,$1)/configuration

# Shell function to get admin password from AWS Secrets Manager
# Usage: Call this function within a shell command block
# Sets ADMIN_PASSWORD variable in the shell context
# Requires: INFRA_DIR variable to be set to infrastructure directory
define get_admin_password_from_secret
	SECRET_ARN=$$(terraform output -raw admin_password_secret_arn 2>&1 | grep -E "^arn:aws:secretsmanager:" | head -1 || echo ""); \
	if [ -z "$$SECRET_ARN" ] || [ "$$SECRET_ARN" = "null" ]; then \
		if [ -n "$$TF_VAR_admin_password_override" ]; then \
			ADMIN_PASSWORD=$$TF_VAR_admin_password_override; \
		else \
			echo "$(YELLOW)Warning: admin_password_secret_arn not found in infrastructure state.$(NC)"; \
			echo "$(YELLOW)Infrastructure may already be destroyed or never created.$(NC)"; \
			echo "$(YELLOW)You can:$(NC)"; \
			echo "$(YELLOW)  1. Set TF_VAR_admin_password_override to provide password manually$(NC)"; \
			echo "$(YELLOW)  2. Set TF_VAR_k8s_token to provide token directly$(NC)"; \
			ADMIN_PASSWORD=""; \
		fi; \
	else \
		if ! command -v aws >/dev/null 2>&1; then \
			echo "$(YELLOW)Error: AWS CLI not found. Required to retrieve admin password from Secrets Manager.$(NC)"; \
			echo "$(YELLOW)Install AWS CLI: https://aws.amazon.com/cli/$(NC)"; \
			exit 1; \
		fi; \
		ADMIN_PASSWORD=$$(aws secretsmanager get-secret-value --secret-id $$SECRET_ARN --query SecretString --output text 2>/dev/null || echo "") && \
		if [ -z "$$ADMIN_PASSWORD" ]; then \
			echo "$(YELLOW)Error: Failed to retrieve admin password from Secrets Manager.$(NC)"; \
			echo "$(YELLOW)Secret ARN: $$SECRET_ARN$(NC)"; \
			echo "$(YELLOW)You may need to:$(NC)"; \
			echo "$(YELLOW)  1. Ensure AWS credentials are configured$(NC)"; \
			echo "$(YELLOW)  2. Ensure you have permission to read the secret$(NC)"; \
			echo "$(YELLOW)  3. Or set TF_VAR_admin_password_override environment variable$(NC)"; \
			exit 1; \
		fi; \
	fi; \
	:
endef

# Shell function to get Kubernetes token with retry logic (5 minute timeout)
# Usage: Call this function within a shell command block
# Sets K8S_TOKEN variable in the shell context
define get_k8s_token_with_retry
	if [ -z "$$TF_VAR_k8s_token" ]; then \
		echo "$(BLUE)Obtaining Kubernetes token via oc login...$(NC)"; \
		if ! command -v oc >/dev/null 2>&1; then \
			echo "$(YELLOW)Error: oc CLI not found. Required for authentication.$(NC)"; \
			echo "$(YELLOW)Install OpenShift CLI: https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/$(NC)"; \
			exit 1; \
		fi; \
		TIMEOUT=300; \
		ELAPSED=0; \
		INTERVAL=10; \
		K8S_TOKEN=""; \
		while [ $$ELAPSED -lt $$TIMEOUT ]; do \
			if oc login $$API_URL --username=admin --password=$$ADMIN_PASSWORD --insecure-skip-tls-verify=true >/dev/null 2>&1 || \
			   oc login $$API_URL --username=admin --password=$$ADMIN_PASSWORD --insecure-skip-tls-verify=false >/dev/null 2>&1; then \
				K8S_TOKEN=$$(oc whoami --show-token 2>/dev/null); \
				if [ -n "$$K8S_TOKEN" ]; then \
					echo "$(GREEN)Successfully obtained Kubernetes token$(NC)"; \
					break; \
				fi; \
			fi; \
			printf "$(YELLOW)Waiting for cluster to be ready... (%ds/%ds)$(NC)\n" $$ELAPSED $$TIMEOUT; \
			sleep $$INTERVAL; \
			ELAPSED=$$((ELAPSED + INTERVAL)); \
		done; \
		if [ -z "$$K8S_TOKEN" ]; then \
			echo "$(YELLOW)Error: Failed to login to cluster after $$TIMEOUT seconds$(NC)"; \
			exit 1; \
		fi; \
	else \
		echo "$(YELLOW)Note: Using TF_VAR_k8s_token from environment.$(NC)"; \
		K8S_TOKEN=$$TF_VAR_k8s_token; \
	fi
endef

# Backwards compatibility - explicit cluster directories
CLUSTER_PUBLIC := clusters/examples/public
CLUSTER_EGRESS_ZERO := clusters/examples/egress-zero

help: ## Show this help message
	@echo "$(BLUE)ROSA HCP Infrastructure - Makefile Targets$(NC)"
	@echo ""
	@echo "$(GREEN)Cluster Management (Infrastructure + Configuration):$(NC)"
	@echo "  Pattern syntax: make <action>.<cluster>"
	@echo "  Examples: make init.public, make plan.egress-zero, make apply.public"
	@echo ""
	@echo "  make init.<cluster>       Initialize both infrastructure and configuration"
	@echo "  make plan.<cluster>       Plan both infrastructure and configuration"
	@echo "  make apply.<cluster>      Apply both (infrastructure first, then configuration)"
	@echo "  make destroy.<cluster>    Destroy all resources (sets enable_destroy=true, runs apply)"
	@echo "  make cleanup.<cluster>    Same as destroy (no confirmation)"
	@echo ""
	@echo "$(GREEN)Infrastructure Management:$(NC)"
	@echo "  make init-infrastructure.<cluster>       Initialize infrastructure only"
	@echo "  make plan-infrastructure.<cluster>       Plan infrastructure changes"
	@echo "  make apply-infrastructure.<cluster>      Apply infrastructure"
	@echo "  make destroy-infrastructure.<cluster>     Destroy infrastructure resources"
	@echo "  make cleanup-infrastructure.<cluster>     Same as destroy (no confirmation)"
	@echo ""
	@echo "$(GREEN)Configuration Management:$(NC)"
	@echo "  make init-configuration.<cluster>         Initialize configuration only"
	@echo "  make plan-configuration.<cluster>         Plan configuration changes"
	@echo "  make apply-configuration.<cluster>         Apply configuration"
	@echo "  make destroy-configuration.<cluster>        Destroy configuration resources"
	@echo "  make cleanup-configuration.<cluster>        Same as destroy (no confirmation)"
	@echo ""
	@echo "$(GREEN)Code Quality:$(NC)"
	@echo "  make fmt                  Format all Terraform files"
	@echo "  make validate             Validate all Terraform modules and examples"
	@echo "  make validate-modules     Validate all modules"
	@echo "  make validate-examples    Validate all example clusters"
	@echo ""
	@echo "$(GREEN)Utilities:$(NC)"
	@echo "  make clean                Clean Terraform files (.terraform, .terraform.lock.hcl)"
	@echo "  make install-provider     Install OpenShift operator provider from GitHub releases"
	@echo "  make init-all             Initialize all clusters (infrastructure + configuration)"
	@echo "  make plan-all             Plan all clusters"
	@echo ""
	@echo "$(GREEN)Destroy Protection:$(NC)"
	@echo "  make destroy.<cluster>    Destroy all resources (sets enable_destroy=true, runs apply)"
	@echo "  make cleanup.<cluster>    Same as destroy (no confirmation)"
	@echo "  Note: By default, enable_destroy=false prevents accidental destruction"
	@echo "        When enable_destroy=true, resources are actually destroyed (not just removed from state)"
	@echo ""
	@echo "$(GREEN)Cluster Access:$(NC)"
	@echo "  Pattern syntax: make <action>.<cluster>"
	@echo "  Examples: make login.public, make show-endpoints.egress-zero, make show-credentials.public"
	@echo ""
	@echo "  make login.<cluster>            Login to cluster using oc CLI"
	@echo "  make show-endpoints.<cluster>    Show API and console URLs"
	@echo "  make show-credentials.<cluster>  Show admin credentials and endpoints"
	@echo ""
	@echo "$(GREEN)Bastion & Tunnel Management:$(NC)"
	@echo "  Pattern syntax: make <action>.<cluster>"
	@echo "  Examples: make tunnel-start.egress-zero, make tunnel-stop.egress-zero"
	@echo ""
	@echo "  make tunnel-start.<cluster>     Start sshuttle VPN tunnel via bastion (routes all VPC traffic)"
	@echo "                                   Requires: sshuttle (brew install sshuttle on macOS)"
	@echo "  make tunnel-stop.<cluster>      Stop sshuttle tunnel"
	@echo "  make tunnel-status.<cluster>    Check if tunnel is running"
	@echo "  make bastion-connect.<cluster>  Connect to bastion via SSM Session Manager"
	@echo ""

# Initialize Infrastructure
init-infrastructure.%:
	@echo "$(BLUE)Initializing $* cluster infrastructure...$(NC)"
	@cd $(call get_infrastructure_dir,$*) && terraform init -reconfigure

# Initialize Configuration
init-configuration.%: install-provider
	@echo "$(BLUE)Initializing $* cluster configuration...$(NC)"
	@cd $(call get_configuration_dir,$*) && terraform init -reconfigure

# Initialize both (infrastructure first, then configuration)
init.%: init-infrastructure.% init-configuration.%
	@echo "$(GREEN)Initialized $* cluster (infrastructure + configuration)$(NC)"

# Explicit targets for backwards compatibility
init-public: init.public ## Initialize Terraform for public cluster
init-egress-zero: init.egress-zero ## Initialize Terraform for egress-zero cluster

init-all: init.public init.egress-zero ## Initialize all clusters

# Plan Infrastructure
plan-infrastructure.%: init-infrastructure.%
	@echo "$(BLUE)Planning $* cluster infrastructure...$(NC)"
	@cd $(call get_infrastructure_dir,$*) && terraform plan -out=terraform.tfplan

# Plan Configuration
plan-configuration.%: init-configuration.%
	@echo "$(BLUE)Planning $* cluster configuration...$(NC)"
	@INFRA_DIR="$(call get_infrastructure_dir,$*)" && \
		CONFIG_DIR="$(call get_configuration_dir,$*)" && \
		cd $$INFRA_DIR && \
		API_URL=$$(terraform output -raw api_url 2>/dev/null) && \
		cd - >/dev/null && \
		if [ -z "$$API_URL" ]; then \
			echo "$(YELLOW)Error: Cluster not deployed or api_url output not available$(NC)"; \
			exit 1; \
		fi && \
		$(call get_admin_password_from_secret) && \
		if [ -z "$$ADMIN_PASSWORD" ] && [ -z "$$TF_VAR_k8s_token" ]; then \
			echo "$(YELLOW)Warning: admin_password not found and TF_VAR_k8s_token not set.$(NC)"; \
			echo "$(YELLOW)You may need to:$(NC)"; \
			echo "$(YELLOW)  1. Re-apply infrastructure: make apply-infrastructure.$*$(NC)"; \
			echo "$(YELLOW)  2. Or set TF_VAR_k8s_token environment variable$(NC)"; \
			exit 1; \
		fi && \
		$(call get_k8s_token_with_retry) && \
		cd $$CONFIG_DIR && \
		TF_VAR_k8s_token=$$K8S_TOKEN terraform plan -out=terraform.tfplan

# Plan both (infrastructure first, then configuration)
plan.%: plan-infrastructure.% plan-configuration.%
	@echo "$(GREEN)Planned $* cluster (infrastructure + configuration)$(NC)"

# Explicit targets for backwards compatibility
plan-public: plan.public ## Plan public cluster deployment
plan-egress-zero: plan.egress-zero ## Plan egress-zero cluster deployment

plan-all: plan.public plan.egress-zero ## Plan all clusters

# Apply Infrastructure
apply-infrastructure.%: plan-infrastructure.%
	@echo "$(YELLOW)Applying $* cluster infrastructure...$(NC)"
	@cd $(call get_infrastructure_dir,$*) && terraform apply terraform.tfplan

# Apply Configuration (depends on infrastructure being applied)
# Note: Infrastructure state must exist (run apply-infrastructure first if needed)
apply-configuration.%: plan-configuration.%
	@echo "$(YELLOW)Applying $* cluster configuration...$(NC)"
	@INFRA_DIR="$(call get_infrastructure_dir,$*)" && \
		CONFIG_DIR="$(call get_configuration_dir,$*)" && \
		cd $$INFRA_DIR && \
		API_URL=$$(terraform output -raw api_url 2>/dev/null) && \
		cd - >/dev/null && \
		if [ -z "$$API_URL" ]; then \
			echo "$(YELLOW)Error: Cluster not deployed or api_url output not available$(NC)"; \
			exit 1; \
		fi && \
		$(call get_admin_password_from_secret) && \
		if [ -z "$$ADMIN_PASSWORD" ] && [ -z "$$TF_VAR_k8s_token" ]; then \
			echo "$(YELLOW)Warning: admin_password not found and TF_VAR_k8s_token not set.$(NC)"; \
			echo "$(YELLOW)You may need to:$(NC)"; \
			echo "$(YELLOW)  1. Re-apply infrastructure: make apply-infrastructure.$*$(NC)"; \
			echo "$(YELLOW)  2. Or set TF_VAR_k8s_token environment variable$(NC)"; \
			exit 1; \
		fi && \
		$(call get_k8s_token_with_retry) && \
		cd $$CONFIG_DIR && \
		TF_VAR_k8s_token=$$K8S_TOKEN terraform apply terraform.tfplan

# Apply both (infrastructure first, then configuration)
apply.%: apply-infrastructure.% apply-configuration.%
	@echo "$(GREEN)Applied $* cluster (infrastructure + configuration)$(NC)"

# Explicit targets for backwards compatibility
apply-public: apply.public ## Apply public cluster configuration
apply-egress-zero: apply.egress-zero ## Apply egress-zero cluster configuration

# Destroy Configuration (destroys Kubernetes resources)
# Sets enable_destroy=true and runs terraform apply
# When count becomes 0, Terraform destroys the resources (GitOps operator will be deleted from cluster)
destroy-configuration.%:
	@echo "$(YELLOW)WARNING: This will destroy the $* cluster configuration!$(NC)"
	@echo "$(YELLOW)Kubernetes resources (GitOps operator) will be deleted from the cluster.$(NC)"
	@INFRA_DIR="$(call get_infrastructure_dir,$*)" && \
		CONFIG_DIR="$(call get_configuration_dir,$*)" && \
		cd $$INFRA_DIR && \
		API_URL=$$(terraform output -raw api_url 2>&1 | grep -E "^https?://" | head -1 || echo "") && \
		cd - >/dev/null && \
		if [ -z "$$API_URL" ]; then \
			echo "$(YELLOW)Warning: Cluster not deployed or api_url output not available.$(NC)"; \
			echo "$(YELLOW)Infrastructure may already be destroyed. Attempting to destroy configuration anyway...$(NC)"; \
		fi && \
		cd $$INFRA_DIR && \
		$(call get_admin_password_from_secret) && \
		cd - >/dev/null && \
		if [ -z "$$ADMIN_PASSWORD" ] && [ -z "$$TF_VAR_k8s_token" ]; then \
			echo "$(YELLOW)Warning: Cannot retrieve admin password and TF_VAR_k8s_token not set.$(NC)"; \
			echo "$(YELLOW)Configuration may already be destroyed or infrastructure is missing.$(NC)"; \
			echo "$(YELLOW)Attempting to destroy configuration anyway (may fail if cluster is still running)...$(NC)"; \
			cd $$CONFIG_DIR && \
			echo "$(BLUE)Setting enable_destroy=true and applying to remove resources from state...$(NC)" && \
			TF_VAR_enable_destroy=true terraform apply -auto-approve || \
			(echo "$(YELLOW)Configuration destroy completed (may have failed if cluster is not accessible)$(NC)" && exit 0) \
		else \
			if [ -n "$$API_URL" ]; then \
				$(call get_k8s_token_with_retry) && \
				cd $$CONFIG_DIR && \
				echo "$(BLUE)Setting enable_destroy=true and applying to remove resources from state...$(NC)" && \
				TF_VAR_k8s_token=$$K8S_TOKEN TF_VAR_enable_destroy=true terraform apply -auto-approve; \
			else \
				echo "$(YELLOW)Skipping Kubernetes authentication (cluster not available).$(NC)"; \
				cd $$CONFIG_DIR && \
				echo "$(BLUE)Setting enable_destroy=true and applying to remove resources from state...$(NC)" && \
				TF_VAR_enable_destroy=true terraform apply -auto-approve || \
				(echo "$(YELLOW)Configuration destroy completed$(NC)" && exit 0); \
			fi \
		fi

# Destroy Infrastructure (destroys AWS resources)
# Sets enable_destroy=true and runs terraform apply
# When count becomes 0, Terraform destroys the resources (cluster, VPC, IAM, etc. will be deleted)
destroy-infrastructure.%: destroy-configuration.%
	@echo "$(YELLOW)WARNING: This will destroy the $* cluster infrastructure!$(NC)"
	@echo "$(YELLOW)AWS resources (cluster, VPC, IAM roles, etc.) will be deleted.$(NC)"
	@cd $(call get_infrastructure_dir,$*) && \
		echo "$(BLUE)Setting enable_destroy=true and applying to destroy resources...$(NC)" && \
		TF_VAR_enable_destroy=true terraform apply -auto-approve

# Destroy both (configuration first, then infrastructure) - destroys all resources
destroy.%: destroy-configuration.% destroy-infrastructure.%
	@echo "$(GREEN)Destroyed $* cluster (configuration + infrastructure)$(NC)"
	@echo "$(GREEN)All resources have been deleted from Kubernetes and AWS.$(NC)"

# Cleanup Configuration (same as destroy - no confirmation)
# If credentials aren't available, skips configuration cleanup (assumes already deleted)
cleanup-configuration.%:
	@echo "$(RED)WARNING: This will DESTROY the $* cluster configuration!$(NC)"
	@echo "$(YELLOW)Kubernetes resources (GitOps operator) will be deleted from the cluster.$(NC)"
	@INFRA_DIR="$(call get_infrastructure_dir,$*)" && \
		CONFIG_DIR="$(call get_configuration_dir,$*)" && \
		cd $$INFRA_DIR && \
		API_URL=$$(terraform output -raw api_url 2>&1 | grep -E "^https?://" | head -1 || echo "") && \
		cd - >/dev/null && \
		if [ -z "$$API_URL" ]; then \
			echo "$(YELLOW)Warning: Cluster not deployed or api_url output not available.$(NC)"; \
			echo "$(YELLOW)Skipping configuration cleanup (infrastructure may already be destroyed).$(NC)"; \
			exit 0; \
		fi && \
		cd $$INFRA_DIR && \
		$(call get_admin_password_from_secret) && \
		cd - >/dev/null && \
		if [ -z "$$ADMIN_PASSWORD" ] && [ -z "$$TF_VAR_k8s_token" ]; then \
			echo "$(YELLOW)Warning: Cannot retrieve admin password and TF_VAR_k8s_token not set.$(NC)"; \
			echo "$(YELLOW)Configuration may already be destroyed. Skipping configuration cleanup.$(NC)"; \
			exit 0; \
		fi && \
		if [ -n "$$API_URL" ]; then \
			$(call get_k8s_token_with_retry) && \
			cd $$CONFIG_DIR && \
			echo "$(BLUE)Setting enable_destroy=true and applying to destroy resources...$(NC)" && \
			TF_VAR_k8s_token=$$K8S_TOKEN TF_VAR_enable_destroy=true terraform apply -auto-approve && \
			echo "$(GREEN)Configuration resources have been destroyed.$(NC)"; \
		else \
			echo "$(YELLOW)Skipping Kubernetes authentication (cluster not available).$(NC)"; \
			cd $$CONFIG_DIR && \
			echo "$(BLUE)Setting enable_destroy=true and applying to remove resources from state...$(NC)" && \
			TF_VAR_enable_destroy=true terraform apply -auto-approve || \
			(echo "$(YELLOW)Configuration cleanup skipped (cluster not accessible)$(NC)" && exit 0); \
		fi

# Cleanup Infrastructure (same as destroy - no confirmation)
cleanup-infrastructure.%: cleanup-configuration.%
	@echo "$(RED)WARNING: This will DESTROY the $* cluster infrastructure!$(NC)"
	@echo "$(YELLOW)AWS resources (cluster, VPC, IAM roles, etc.) will be deleted.$(NC)"
	@cd $(call get_infrastructure_dir,$*) && \
		echo "$(BLUE)Setting enable_destroy=true and applying to destroy resources...$(NC)" && \
		TF_VAR_enable_destroy=true terraform apply -auto-approve && \
		echo "$(GREEN)Infrastructure resources have been destroyed.$(NC)"

# Cleanup both (configuration first, then infrastructure) - same as destroy
# If configuration cleanup is skipped (no credentials), still proceeds to infrastructure cleanup
cleanup.%: cleanup-configuration.% cleanup-infrastructure.%
	@echo "$(GREEN)Cleanup completed for $* cluster$(NC)"
	@echo "$(GREEN)All resources have been deleted from Kubernetes and AWS.$(NC)"

# Explicit targets for backwards compatibility
destroy-public: destroy.public ## Destroy public cluster
destroy-egress-zero: destroy.egress-zero ## Destroy egress-zero cluster

cleanup-public: cleanup.public ## Destroy public cluster
cleanup-egress-zero: cleanup.egress-zero ## Destroy egress-zero cluster

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
	@for cluster in public egress-zero; do \
		echo "Validating $$cluster infrastructure..."; \
		cd $(call get_infrastructure_dir,$$cluster) && terraform init -backend=false >/dev/null 2>&1 && terraform validate && cd - >/dev/null || echo "  ✗ Failed: $$cluster infrastructure"; \
		echo "Validating $$cluster configuration..."; \
		cd $(call get_configuration_dir,$$cluster) && terraform init -backend=false >/dev/null 2>&1 && terraform validate && cd - >/dev/null || echo "  ✗ Failed: $$cluster configuration"; \
	done

# Cluster Access - Show Endpoints
# Reads from infrastructure state (cluster endpoints are infrastructure outputs)
show-endpoints.%:
	@echo "$(BLUE)$(shell echo $* | tr '[:lower:]' '[:upper:]' | sed 's/-/ /g') Cluster Endpoints:$(NC)"
	@cd $(call get_infrastructure_dir,$*) && \
		API_URL=$$(terraform output -raw api_url 2>/dev/null) && \
		if [ -z "$$API_URL" ]; then \
			echo "$(YELLOW)Cluster not deployed or terraform outputs not available$(NC)"; \
			exit 1; \
		fi && \
		VPC_CIDR=$$(terraform output -raw vpc_cidr_block 2>/dev/null || terraform output -json 2>/dev/null | jq -r '.vpc_cidr_block.value // empty') && \
		terraform output -json 2>/dev/null | \
			jq -r '"API URL:     " + .api_url.value, "Console URL:  " + .console_url.value' 2>/dev/null && \
		if [ -n "$$VPC_CIDR" ] && pgrep -f "sshuttle.*$$VPC_CIDR" >/dev/null 2>&1; then \
			echo "$(GREEN)✓ sshuttle tunnel active - all VPC traffic routed through bastion$(NC)"; \
		fi

# Explicit targets for backwards compatibility
show-endpoints-public: show-endpoints.public ## Show API and console URLs for public cluster
show-endpoints-egress-zero: show-endpoints.egress-zero ## Show API and console URLs for egress-zero cluster

# Cluster Access - Show Credentials (includes endpoints)
# Reads admin password from configuration terraform.tfvars
show-credentials.%: show-endpoints.%
	@echo "$(BLUE)$(shell echo $* | tr '[:lower:]' '[:upper:]' | sed 's/-/ /g') Cluster Credentials:$(NC)"
	@cd $(call get_configuration_dir,$*) && \
		if [ -z "$$TF_VAR_admin_password" ]; then \
			echo "$(YELLOW)Warning: TF_VAR_admin_password not set. Checking terraform.tfvars...$(NC)"; \
			if [ -f "terraform.tfvars" ]; then \
				admin_password=$$(grep -E "^admin_password\s*=" terraform.tfvars | sed -E "s/^[^=]*=\s*['\"]?([^'\"]+)['\"]?/\1/" | head -1); \
				if [ -n "$$admin_password" ]; then \
					echo "Admin Username: admin"; \
					echo "Admin Password: $$admin_password"; \
				else \
					echo "$(YELLOW)Admin password not found in terraform.tfvars$(NC)"; \
				fi; \
			else \
				echo "$(YELLOW)terraform.tfvars not found$(NC)"; \
			fi; \
		else \
			echo "Admin Username: admin"; \
			echo "Admin Password: $$TF_VAR_admin_password"; \
		fi

# Explicit targets for backwards compatibility
show-credentials-public: show-credentials.public ## Show admin credentials and endpoints for public cluster
show-credentials-egress-zero: show-credentials.egress-zero ## Show admin credentials and endpoints for egress-zero cluster

# Cluster Access - Login
# Reads API URL from infrastructure state and password from configuration
login.%:
	@echo "$(BLUE)Logging into $* cluster...$(NC)"
	@if ! command -v oc >/dev/null 2>&1; then \
		echo "$(YELLOW)Error: oc CLI not found. Please install OpenShift CLI.$(NC)"; \
		exit 1; \
	fi
	@INFRA_DIR="$(call get_infrastructure_dir,$*)" && \
		cd $$INFRA_DIR && \
		API_URL=$$(terraform output -raw api_url 2>/dev/null) && \
		if [ -z "$$API_URL" ]; then \
			echo "$(YELLOW)Error: Cluster not deployed or api_url output not available$(NC)"; \
			exit 1; \
		fi && \
		VPC_CIDR=$$(terraform output -raw vpc_cidr_block 2>/dev/null || terraform output -json 2>/dev/null | jq -r '.vpc_cidr_block.value // empty') && \
		if [ -n "$$VPC_CIDR" ] && pgrep -f "sshuttle.*$$VPC_CIDR" >/dev/null 2>&1; then \
			echo "$(GREEN)sshuttle tunnel active - using direct API URL (traffic routed through bastion)$(NC)"; \
		fi && \
		$(call get_admin_password_from_secret) && \
		if [ -z "$$ADMIN_PASSWORD" ] && [ -z "$$TF_VAR_admin_password_override" ]; then \
			echo "$(YELLOW)Error: Admin password not found and TF_VAR_admin_password_override not set.$(NC)"; \
			echo "$(YELLOW)You may need to:$(NC)"; \
			echo "$(YELLOW)  1. Re-apply infrastructure: make apply-infrastructure.$*$(NC)"; \
			echo "$(YELLOW)  2. Or set TF_VAR_admin_password_override environment variable$(NC)"; \
			exit 1; \
		fi && \
		PASSWORD=$${ADMIN_PASSWORD:-$$TF_VAR_admin_password_override} && \
		oc login $$API_URL --username admin --password $$PASSWORD --insecure-skip-tls-verify=false || \
		(echo "$(YELLOW)Login failed. Check credentials and cluster status.$(NC)" && exit 1)

# Explicit targets for backwards compatibility
login-public: login.public ## Login to public cluster using oc CLI
login-egress-zero: login.egress-zero ## Login to egress-zero cluster using oc CLI

# Bastion & Tunnel Management
# Reads bastion info from configuration state (bastion is in configuration)
tunnel-start.%:
	@echo "$(BLUE)Starting sshuttle VPN tunnel to $* cluster via bastion...$(NC)"
	@if ! command -v sshuttle >/dev/null 2>&1; then \
		echo "$(YELLOW)Error: sshuttle not found.$(NC)"; \
		echo "$(YELLOW)Installation instructions:$(NC)"; \
		echo "  macOS:  brew install sshuttle"; \
		echo "  Linux:  pip install sshuttle  (or use your package manager)"; \
		echo "  See:    https://github.com/sshuttle/sshuttle"; \
		exit 1; \
	fi
	@if ! command -v aws >/dev/null 2>&1; then \
		echo "$(YELLOW)Error: aws CLI not found. Please install AWS CLI.$(NC)"; \
		exit 1; \
	fi
	@cd $(call get_configuration_dir,$*) && \
		BASTION_ID=$$(terraform output -raw bastion_instance_id 2>/dev/null) && \
		if [ -z "$$BASTION_ID" ] || [ "$$BASTION_ID" = "null" ]; then \
			echo "$(YELLOW)Error: Bastion not deployed. Enable bastion with enable_bastion=true$(NC)"; \
			exit 1; \
		fi && \
		cd $(call get_infrastructure_dir,$*) && \
		VPC_CIDR=$$(terraform output -raw vpc_cidr_block 2>/dev/null || terraform output -json 2>/dev/null | jq -r '.vpc_cidr_block.value // empty') && \
		if [ -z "$$VPC_CIDR" ]; then \
			echo "$(YELLOW)Error: VPC CIDR not found in terraform outputs$(NC)"; \
			exit 1; \
		fi && \
		REGION=$$(terraform output -raw region 2>/dev/null || terraform output -json 2>/dev/null | jq -r '.region.value // empty' || echo "us-east-1") && \
		if [ -z "$$REGION" ]; then \
			REGION=$$(grep -E "^region\s*=" terraform.tfvars 2>/dev/null | cut -d'"' -f2 | cut -d"'" -f2 | head -1 || echo "us-east-1"); \
		fi && \
		if pgrep -f "sshuttle.*$$VPC_CIDR" >/dev/null 2>&1; then \
			echo "$(YELLOW)sshuttle tunnel already running for $$VPC_CIDR$(NC)"; \
			exit 0; \
		fi && \
		echo "$(YELLOW)Note: sshuttle requires sudo privileges. You will be prompted for your local sudo password.$(NC)" && \
		sudo sshuttle --ssh-cmd "ssh -o ProxyCommand='aws --region $$REGION ssm start-session --target $$BASTION_ID --document-name AWS-StartSSHSession --parameters portNumber=22' -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
			--remote ec2-user@$$BASTION_ID \
			--dns $$VPC_CIDR \
			$$VPC_CIDR \
			--daemon \
			--pidfile /tmp/sshuttle-$$*-$$BASTION_ID.pid && \
		echo "$(GREEN)sshuttle tunnel started for VPC $$VPC_CIDR$(NC)" && \
		echo "$(GREEN)All traffic to $$VPC_CIDR is now routed through the bastion$(NC)" && \
		echo "$(GREEN)You can now use oc login with the direct API URL$(NC)" || \
		(echo "$(YELLOW)Failed to start tunnel. Check bastion status and AWS credentials.$(NC)" && echo "$(YELLOW)Note: sshuttle requires sudo privileges.$(NC)" && exit 1)

tunnel-stop.%:
	@echo "$(BLUE)Stopping sshuttle tunnel for $* cluster...$(NC)"
	@cd $(call get_configuration_dir,$*) && \
		BASTION_ID=$$(terraform output -raw bastion_instance_id 2>/dev/null) && \
		if [ -z "$$BASTION_ID" ] || [ "$$BASTION_ID" = "null" ]; then \
			echo "$(YELLOW)Bastion not deployed$(NC)"; \
			exit 0; \
		fi && \
		cd $(call get_infrastructure_dir,$*) && \
		VPC_CIDR=$$(terraform output -raw vpc_cidr_block 2>/dev/null || terraform output -json 2>/dev/null | jq -r '.vpc_cidr_block.value // empty') && \
		PIDFILE="/tmp/sshuttle-$$*-$$BASTION_ID.pid" && \
		if [ -f "$$PIDFILE" ]; then \
			PID=$$(cat $$PIDFILE 2>/dev/null) && \
			if [ -n "$$PID" ] && kill -0 $$PID 2>/dev/null; then \
				sudo kill $$PID && \
				sudo rm -f $$PIDFILE && \
				echo "$(GREEN)Tunnel stopped$(NC)"; \
			else \
				sudo rm -f $$PIDFILE && \
				echo "$(YELLOW)Tunnel process not found (cleaned up PID file)$(NC)"; \
			fi; \
		else \
			if [ -n "$$VPC_CIDR" ] && pgrep -f "sshuttle.*$$VPC_CIDR" >/dev/null 2>&1; then \
				sudo pkill -f "sshuttle.*$$VPC_CIDR" && \
				echo "$(GREEN)Tunnel stopped$(NC)"; \
			else \
				echo "$(YELLOW)No tunnel found running$(NC)"; \
			fi \
		fi

tunnel-status.%:
	@echo "$(BLUE)Checking sshuttle tunnel status for $* cluster...$(NC)"
	@cd $(call get_configuration_dir,$*) && \
		BASTION_ID=$$(terraform output -raw bastion_instance_id 2>/dev/null) && \
		if [ -z "$$BASTION_ID" ] || [ "$$BASTION_ID" = "null" ]; then \
			echo "$(YELLOW)Bastion not deployed$(NC)"; \
			exit 1; \
		fi && \
		cd $(call get_infrastructure_dir,$*) && \
		VPC_CIDR=$$(terraform output -raw vpc_cidr_block 2>/dev/null || terraform output -json 2>/dev/null | jq -r '.vpc_cidr_block.value // empty') && \
		if [ -z "$$VPC_CIDR" ]; then \
			echo "$(YELLOW)VPC CIDR not found$(NC)"; \
			exit 1; \
		fi && \
		PIDFILE="/tmp/sshuttle-$$*-$$BASTION_ID.pid" && \
		if [ -f "$$PIDFILE" ]; then \
			PID=$$(cat $$PIDFILE 2>/dev/null) && \
			if [ -n "$$PID" ] && kill -0 $$PID 2>/dev/null && pgrep -f "sshuttle.*$$VPC_CIDR" >/dev/null 2>&1; then \
				echo "$(GREEN)Tunnel is running: VPC $$VPC_CIDR routed through bastion$$BASTION_ID$(NC)"; \
				ps aux | grep -E "sshuttle.*$$VPC_CIDR" | grep -v grep; \
			else \
				echo "$(YELLOW)Tunnel is not running$(NC)"; \
				rm -f $$PIDFILE; \
				exit 1; \
			fi; \
		elif pgrep -f "sshuttle.*$$VPC_CIDR" >/dev/null 2>&1; then \
			echo "$(GREEN)Tunnel is running: VPC $$VPC_CIDR routed through bastion$$BASTION_ID$(NC)"; \
			ps aux | grep -E "sshuttle.*$$VPC_CIDR" | grep -v grep; \
		else \
			echo "$(YELLOW)Tunnel is not running$(NC)"; \
			exit 1; \
		fi

bastion-connect.%:
	@echo "$(BLUE)Connecting to $* cluster bastion via SSM Session Manager...$(NC)"
	@if ! command -v aws >/dev/null 2>&1; then \
		echo "$(YELLOW)Error: aws CLI not found. Please install AWS CLI.$(NC)"; \
		exit 1; \
	fi
	@cd $(call get_configuration_dir,$*) && \
		BASTION_ID=$$(terraform output -raw bastion_instance_id 2>/dev/null) && \
		if [ -z "$$BASTION_ID" ] || [ "$$BASTION_ID" = "null" ]; then \
			echo "$(YELLOW)Error: Bastion not deployed. Enable bastion with enable_bastion=true$(NC)"; \
			exit 1; \
		fi && \
		cd $(call get_infrastructure_dir,$*) && \
		REGION=$$(terraform output -raw region 2>/dev/null || terraform output -json 2>/dev/null | jq -r '.region.value // empty' || echo "us-east-1") && \
		if [ -z "$$REGION" ]; then \
			REGION=$$(grep -E "^region\s*=" terraform.tfvars 2>/dev/null | cut -d'"' -f2 | cut -d"'" -f2 | head -1 || echo "us-east-1"); \
		fi && \
		echo "$(GREEN)Connecting to bastion $$BASTION_ID in region $$REGION...$(NC)" && \
		aws ssm start-session --target $$BASTION_ID --region $$REGION || \
		(echo "$(YELLOW)Failed to connect. Check AWS credentials and bastion status.$(NC)" && exit 1)

# Explicit targets for backwards compatibility
tunnel-start-egress-zero: tunnel-start.egress-zero ## Start SSH tunnel for egress-zero cluster
tunnel-stop-egress-zero: tunnel-stop.egress-zero ## Stop SSH tunnel for egress-zero cluster
tunnel-status-egress-zero: tunnel-status.egress-zero ## Check tunnel status for egress-zero cluster
bastion-connect-egress-zero: bastion-connect.egress-zero ## Connect to egress-zero cluster bastion

# Install OpenShift Provider
PROVIDER_VERSION ?= 0.1.1
install-provider: ## Install OpenShift operator provider from GitHub releases (default: v0.1.1, override with PROVIDER_VERSION=0.1.1)
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
