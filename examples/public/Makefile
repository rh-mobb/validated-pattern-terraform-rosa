# Public Example Makefile
# Manages ROSA HCP public cluster infrastructure and configuration

include ../../Makefile.common

.PHONY: help init plan apply destroy fmt validate clean
.PHONY: init-infrastructure init-configuration plan-infrastructure plan-configuration
.PHONY: apply-infrastructure apply-configuration destroy-infrastructure destroy-configuration
.PHONY: cleanup-infrastructure cleanup-configuration
.PHONY: show-endpoints show-credentials login
.PHONY: tunnel-start tunnel-stop tunnel-status bastion-connect

# Cluster name - defaults to "default" if not provided
# Usage: make apply CLUSTER=dev-public-01
#        make apply  (uses default cluster)
CLUSTER_NAME := $(if $(CLUSTER),$(CLUSTER),default)

# Directories (relative to example directory)
INFRA_DIR := infrastructure
CONFIG_DIR := configuration
CLUSTER_DIR := clusters/$(CLUSTER_NAME)

# Check cluster exists
check-cluster:
	@if [ -z "$(CLUSTER_NAME)" ]; then \
		echo "$(YELLOW)Error: CLUSTER variable is required$(NC)"; \
		echo "$(YELLOW)Usage: make <target> CLUSTER=<cluster-name>$(NC)"; \
		exit 1; \
	fi
	@if [ ! -d "$(CLUSTER_DIR)" ]; then \
		echo "$(YELLOW)Error: Cluster directory '$(CLUSTER_DIR)' does not exist$(NC)"; \
		echo "$(YELLOW)Available clusters:$$(ls -1 clusters/ 2>/dev/null | sed 's/^/  - /' || echo '  (none)')$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Using cluster: $(CLUSTER_NAME)$(NC)"

help: ## Show this help message
	@echo "$(GREEN)Public Example - ROSA HCP Cluster$(NC)"
	@echo ""
	@echo "$(BLUE)Usage:$(NC) make <target>"
	@echo ""
	@echo "$(GREEN)Cluster Management (Infrastructure + Configuration):$(NC)"
	@echo "  make init              Initialize both infrastructure and configuration"
	@echo "  make plan              Plan both infrastructure and configuration"
	@echo "  make apply             Apply both (infrastructure first, then configuration)"
	@echo "  make destroy           Destroy all resources (sets enable_destroy=true)"
	@echo "  make cleanup           Same as destroy (no confirmation)"
	@echo ""
	@echo "$(GREEN)Infrastructure Management:$(NC)"
	@echo "  make init-infrastructure       Initialize infrastructure only"
	@echo "  make plan-infrastructure       Plan infrastructure changes"
	@echo "  make apply-infrastructure      Apply infrastructure"
	@echo "  make destroy-infrastructure    Destroy infrastructure resources"
	@echo "  make cleanup-infrastructure    Same as destroy (no confirmation)"
	@echo ""
	@echo "$(GREEN)Configuration Management:$(NC)"
	@echo "  make init-configuration         Initialize configuration only"
	@echo "  make plan-configuration         Plan configuration changes"
	@echo "  make apply-configuration        Apply configuration"
	@echo "  make destroy-configuration      Destroy configuration resources"
	@echo "  make cleanup-configuration      Same as destroy (no confirmation)"
	@echo ""
	@echo "$(GREEN)Cluster Access:$(NC)"
	@echo "  make show-endpoints    Show API and console URLs"
	@echo "  make show-credentials Show admin credentials and endpoints"
	@echo "  make login             Login to cluster using oc CLI"
	@echo ""
	@echo "$(GREEN)Bastion & Tunnel Management:$(NC)"
	@echo "  make tunnel-start      Start sshuttle VPN tunnel via bastion"
	@echo "  make tunnel-stop       Stop sshuttle tunnel"
	@echo "  make tunnel-status    Check if tunnel is running"
	@echo "  make bastion-connect   Connect to bastion via SSM Session Manager"
	@echo ""
	@echo "$(BLUE)Note:$(NC) CLUSTER parameter is optional (defaults to 'default')"
	@echo "$(BLUE)Usage:$(NC) make <target> [CLUSTER=<cluster-name>]"
	@echo "$(BLUE)Examples:$(NC)"
	@echo "  make apply                    (uses default cluster)"
	@echo "  make apply CLUSTER=dev-public-01  (uses specified cluster)"
	@echo ""
	@echo "$(BLUE)Available clusters:$(NC)"
	@ls -1 clusters/ 2>/dev/null | sed 's/^/  - /' || echo "  (none)"

# Initialize Infrastructure
init-infrastructure: check-cluster
	@echo "$(BLUE)Initializing infrastructure...$(NC)"
	@cd $(INFRA_DIR) && \
		terraform init -reconfigure -input=false \
		-backend-config=../$(CLUSTER_DIR)/backend-infrastructure.hcl

# Initialize Configuration
init-configuration: check-cluster
	@echo "$(BLUE)Initializing configuration...$(NC)"
	@cd $(CONFIG_DIR) && \
		terraform init -upgrade -input=false \
		-backend-config=../$(CLUSTER_DIR)/backend-configuration.hcl

# Initialize both (infrastructure first, then configuration)
init: init-infrastructure init-configuration
	@echo "$(GREEN)Initialized $(CLUSTER_NAME) (infrastructure + configuration)$(NC)"

# Plan Infrastructure
plan-infrastructure: init-infrastructure
	@echo "$(BLUE)Planning infrastructure...$(NC)"
	@cd $(INFRA_DIR) && \
		terraform plan \
		-var-file=../$(CLUSTER_DIR)/terraform.tfvars \
		-out=terraform.tfplan

# Plan Configuration
plan-configuration: init-configuration
	@echo "$(BLUE)Planning configuration...$(NC)"
	@INFRA_DIR="$(INFRA_DIR)" && \
	CONFIG_DIR="$(CONFIG_DIR)" && \
	cd $$INFRA_DIR && \
	API_URL=$$(terraform output -raw api_url 2>/dev/null) && \
	cd - >/dev/null && \
	if [ -z "$$API_URL" ]; then \
		echo "$(YELLOW)Error: Cluster not deployed or api_url output not available$(NC)"; \
		exit 1; \
	fi && \
	echo "$(BLUE)API URL: $$API_URL$(NC)" && \
	echo "$(BLUE)Retrieving admin password from Secrets Manager...$(NC)" && \
	REPO_ROOT=$$(git rev-parse --show-toplevel 2>/dev/null || pwd) && \
	SCRIPT_PATH="$$REPO_ROOT/scripts/get-admin-password.sh" && \
	if [ ! -f "$$SCRIPT_PATH" ]; then \
		SCRIPT_PATH="$$(pwd)/../../scripts/get-admin-password.sh"; \
	fi && \
	if [ ! -f "$$SCRIPT_PATH" ]; then \
		echo "$(YELLOW)Error: get-admin-password.sh script not found$(NC)"; \
		exit 1; \
	fi && \
	ADMIN_PASSWORD=$$($$SCRIPT_PATH "$$INFRA_DIR") && \
	export ADMIN_PASSWORD && \
	if [ -z "$$ADMIN_PASSWORD" ] && [ -z "$$TF_VAR_k8s_token" ]; then \
		echo "$(YELLOW)Warning: admin_password not found and TF_VAR_k8s_token not set.$(NC)"; \
		echo "$(YELLOW)You may need to:$(NC)"; \
		echo "$(YELLOW)  1. Re-apply infrastructure: make apply-infrastructure$(NC)"; \
		echo "$(YELLOW)  2. Or set TF_VAR_k8s_token environment variable$(NC)"; \
		exit 1; \
	fi && \
	echo "$(BLUE)Obtaining Kubernetes token...$(NC)" && \
	$(get_k8s_token_with_retry) && \
	if [ -z "$$K8S_TOKEN" ]; then \
		echo "$(YELLOW)Error: Failed to obtain Kubernetes token$(NC)"; \
		exit 1; \
	fi && \
	echo "$(BLUE)Running Terraform plan in $$CONFIG_DIR...$(NC)" && \
	cd $$CONFIG_DIR && \
	TF_VAR_k8s_token=$$K8S_TOKEN terraform plan -out=terraform.tfplan

# Plan both (infrastructure first, then configuration)
plan: plan-infrastructure plan-configuration
	@echo "$(GREEN)Planned $(CLUSTER_NAME) (infrastructure + configuration)$(NC)"

# Apply Infrastructure
apply-infrastructure: plan-infrastructure
	@echo "$(YELLOW)Applying infrastructure...$(NC)"
	@cd $(INFRA_DIR) && \
		terraform apply \
		-var-file=../$(CLUSTER_DIR)/terraform.tfvars \
		terraform.tfplan

# Apply Configuration
apply-configuration: plan-configuration
	@echo "$(YELLOW)Applying configuration...$(NC)"
	@INFRA_DIR="$(INFRA_DIR)" && \
	CONFIG_DIR="$(CONFIG_DIR)" && \
	cd $$INFRA_DIR && \
	API_URL=$$(terraform output -raw api_url 2>/dev/null) && \
	cd - >/dev/null && \
	if [ -z "$$API_URL" ]; then \
		echo "$(YELLOW)Error: Cluster not deployed or api_url output not available$(NC)"; \
		exit 1; \
	fi && \
	echo "$(BLUE)API URL: $$API_URL$(NC)" && \
	echo "$(BLUE)Retrieving admin password from Secrets Manager...$(NC)" && \
	REPO_ROOT=$$(git rev-parse --show-toplevel 2>/dev/null || pwd) && \
	SCRIPT_PATH="$$REPO_ROOT/scripts/get-admin-password.sh" && \
	if [ ! -f "$$SCRIPT_PATH" ]; then \
		SCRIPT_PATH="$$(pwd)/../../scripts/get-admin-password.sh"; \
	fi && \
	if [ ! -f "$$SCRIPT_PATH" ]; then \
		echo "$(YELLOW)Error: get-admin-password.sh script not found$(NC)"; \
		exit 1; \
	fi && \
	ADMIN_PASSWORD=$$($$SCRIPT_PATH "$$INFRA_DIR") && \
	export ADMIN_PASSWORD && \
	if [ -z "$$ADMIN_PASSWORD" ] && [ -z "$$TF_VAR_k8s_token" ]; then \
		echo "$(YELLOW)Warning: admin_password not found and TF_VAR_k8s_token not set.$(NC)"; \
		echo "$(YELLOW)You may need to:$(NC)"; \
		echo "$(YELLOW)  1. Re-apply infrastructure: make apply-infrastructure$(NC)"; \
		echo "$(YELLOW)  2. Or set TF_VAR_k8s_token environment variable$(NC)"; \
		exit 1; \
	fi && \
	echo "$(BLUE)Obtaining Kubernetes token...$(NC)" && \
	$(get_k8s_token_with_retry) && \
	if [ -z "$$K8S_TOKEN" ]; then \
		echo "$(YELLOW)Error: Failed to obtain Kubernetes token$(NC)"; \
		exit 1; \
	fi && \
	echo "$(BLUE)Running Terraform apply in $$CONFIG_DIR...$(NC)" && \
	cd $$CONFIG_DIR && \
	TF_VAR_k8s_token=$$K8S_TOKEN terraform apply terraform.tfplan

# Apply both (infrastructure first, then configuration)
apply: apply-infrastructure apply-configuration
	@echo "$(GREEN)Applied $(CLUSTER_NAME) (infrastructure + configuration)$(NC)"

# Destroy Configuration
destroy-configuration: check-cluster
	@echo "$(YELLOW)WARNING: This will destroy the configuration!$(NC)"
	@echo "$(YELLOW)Kubernetes resources (GitOps operator) will be deleted from the cluster.$(NC)"
	@INFRA_DIR="$(INFRA_DIR)" && \
	CONFIG_DIR="$(CONFIG_DIR)" && \
	cd $$INFRA_DIR && \
	API_URL=$$(terraform output -raw api_url 2>&1 | grep -E "^https?://" | head -1 || echo "") && \
	cd - >/dev/null && \
	if [ -z "$$API_URL" ]; then \
		echo "$(YELLOW)Warning: Cluster not deployed or api_url output not available.$(NC)"; \
		echo "$(YELLOW)Infrastructure may already be destroyed. Attempting to destroy configuration anyway...$(NC)"; \
	fi && \
	cd $$INFRA_DIR && \
	$(get_admin_password_from_secret,$$INFRA_DIR) && \
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
			$(get_k8s_token_with_retry) && \
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

# Destroy Infrastructure
destroy-infrastructure: destroy-configuration
	@echo "$(YELLOW)WARNING: This will destroy the infrastructure!$(NC)"
	@echo "$(YELLOW)AWS resources (cluster, VPC, IAM roles, etc.) will be deleted.$(NC)"
	@cd $(INFRA_DIR) && \
		echo "$(BLUE)Setting enable_destroy=true and applying to destroy resources...$(NC)" && \
		TF_VAR_enable_destroy=true terraform apply \
		-var-file=../$(CLUSTER_DIR)/terraform.tfvars \
		-auto-approve

# Destroy both (configuration first, then infrastructure)
destroy: destroy-configuration destroy-infrastructure
	@echo "$(GREEN)Destroyed $(CLUSTER_NAME) (configuration + infrastructure)$(NC)"
	@echo "$(GREEN)All resources have been deleted from Kubernetes and AWS.$(NC)"

# Cleanup Configuration
cleanup-configuration: check-cluster
	@echo "$(RED)WARNING: This will DESTROY the configuration!$(NC)"
	@echo "$(YELLOW)Kubernetes resources (GitOps operator) will be deleted from the cluster.$(NC)"
	@INFRA_DIR="$(INFRA_DIR)" && \
	CONFIG_DIR="$(CONFIG_DIR)" && \
	cd $$INFRA_DIR && \
	API_URL=$$(terraform output -raw api_url 2>&1 | grep -E "^https?://" | head -1 || echo "") && \
	cd - >/dev/null && \
	if [ -z "$$API_URL" ]; then \
		echo "$(YELLOW)Warning: Cluster not deployed or api_url output not available.$(NC)"; \
		echo "$(YELLOW)Skipping configuration cleanup (infrastructure may already be destroyed).$(NC)"; \
		exit 0; \
	fi && \
	echo "$(BLUE)Retrieving admin password from Secrets Manager...$(NC)" && \
	REPO_ROOT=$$(git rev-parse --show-toplevel 2>/dev/null || pwd) && \
	SCRIPT_PATH="$$REPO_ROOT/scripts/get-admin-password.sh" && \
	if [ ! -f "$$SCRIPT_PATH" ]; then \
		SCRIPT_PATH="$$(pwd)/../../scripts/get-admin-password.sh"; \
	fi && \
	if [ ! -f "$$SCRIPT_PATH" ]; then \
		echo "$(YELLOW)Error: get-admin-password.sh script not found$(NC)"; \
		exit 1; \
	fi && \
	ADMIN_PASSWORD=$$($$SCRIPT_PATH "$$INFRA_DIR") && \
	export ADMIN_PASSWORD && \
	if [ -z "$$ADMIN_PASSWORD" ] && [ -z "$$TF_VAR_k8s_token" ]; then \
		echo "$(YELLOW)Warning: Cannot retrieve admin password and TF_VAR_k8s_token not set.$(NC)"; \
		echo "$(YELLOW)Configuration may already be destroyed. Skipping configuration cleanup.$(NC)"; \
		exit 0; \
	fi && \
	if [ -n "$$API_URL" ]; then \
		$(get_k8s_token_with_retry) && \
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

# Cleanup Infrastructure
cleanup-infrastructure: cleanup-configuration
	@echo "$(RED)WARNING: This will DESTROY the infrastructure!$(NC)"
	@echo "$(YELLOW)AWS resources (cluster, VPC, IAM roles, etc.) will be deleted.$(NC)"
	@cd $(INFRA_DIR) && \
		echo "$(BLUE)Setting enable_destroy=true and applying to destroy resources...$(NC)" && \
		TF_VAR_enable_destroy=true terraform apply \
		-var-file=../$(CLUSTER_DIR)/terraform.tfvars \
		-auto-approve && \
		echo "$(GREEN)Infrastructure resources have been destroyed.$(NC)"

# Cleanup both (configuration first, then infrastructure)
cleanup: cleanup-configuration cleanup-infrastructure
	@echo "$(GREEN)Cleanup completed for $(CLUSTER_NAME)$(NC)"
	@echo "$(GREEN)All resources have been deleted from Kubernetes and AWS.$(NC)"

# Show Endpoints
show-endpoints: check-cluster
	@echo "$(BLUE)PUBLIC Cluster Endpoints:$(NC)"
	@cd $(INFRA_DIR) && \
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

# Show Credentials
show-credentials: show-endpoints
	@echo "$(BLUE)PUBLIC Cluster Credentials:$(NC)"
	@INFRA_DIR="$(INFRA_DIR)" && \
	REPO_ROOT=$$(git rev-parse --show-toplevel 2>/dev/null || pwd) && \
	SCRIPT_PATH="$$REPO_ROOT/scripts/get-admin-password.sh" && \
	if [ ! -f "$$SCRIPT_PATH" ]; then \
		SCRIPT_PATH="$$(pwd)/../../scripts/get-admin-password.sh"; \
	fi && \
	if [ -f "$$SCRIPT_PATH" ]; then \
		ADMIN_PASSWORD=$$($$SCRIPT_PATH "$$INFRA_DIR" 2>/dev/null) && \
		if [ -n "$$ADMIN_PASSWORD" ]; then \
			echo "Admin Username: admin"; \
			echo "Admin Password: $$ADMIN_PASSWORD"; \
		else \
			if [ -n "$$TF_VAR_admin_password_override" ]; then \
				echo "Admin Username: admin"; \
				echo "Admin Password: $$TF_VAR_admin_password_override"; \
			else \
				echo "$(YELLOW)Admin password not available.$(NC)"; \
				echo "$(YELLOW)Infrastructure may not be deployed or secret not found.$(NC)"; \
				echo "$(YELLOW)Set TF_VAR_admin_password_override to provide password manually.$(NC)"; \
			fi; \
		fi; \
	else \
		if [ -n "$$TF_VAR_admin_password_override" ]; then \
			echo "Admin Username: admin"; \
			echo "Admin Password: $$TF_VAR_admin_password_override"; \
		else \
			echo "$(YELLOW)Error: get-admin-password.sh script not found$(NC)"; \
			echo "$(YELLOW)Set TF_VAR_admin_password_override to provide password manually.$(NC)"; \
		fi; \
	fi

# Login
login: check-cluster
	@echo "$(BLUE)Logging into cluster...$(NC)"
	@if ! command -v oc >/dev/null 2>&1; then \
		echo "$(YELLOW)Error: oc CLI not found. Please install OpenShift CLI.$(NC)"; \
		exit 1; \
	fi
	@INFRA_DIR="$(INFRA_DIR)" && \
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
		$(get_admin_password_from_secret,$$INFRA_DIR) && \
		if [ -z "$$ADMIN_PASSWORD" ] && [ -z "$$TF_VAR_admin_password_override" ]; then \
			echo "$(YELLOW)Error: Admin password not found and TF_VAR_admin_password_override not set.$(NC)"; \
			echo "$(YELLOW)You may need to:$(NC)"; \
			echo "$(YELLOW)  1. Re-apply infrastructure: make apply-infrastructure$(NC)"; \
			echo "$(YELLOW)  2. Or set TF_VAR_admin_password_override environment variable$(NC)"; \
			exit 1; \
		fi && \
		PASSWORD=$${ADMIN_PASSWORD:-$$TF_VAR_admin_password_override} && \
		oc login $$API_URL --username admin --password $$PASSWORD --insecure-skip-tls-verify=false || \
		(echo "$(YELLOW)Login failed. Check credentials and cluster status.$(NC)" && exit 1)

# Tunnel Management
tunnel-start: check-cluster
	@echo "$(BLUE)Starting sshuttle VPN tunnel via bastion...$(NC)"
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
	@cd $(CONFIG_DIR) && \
		BASTION_ID=$$(terraform output -raw bastion_instance_id 2>/dev/null) && \
		if [ -z "$$BASTION_ID" ] || [ "$$BASTION_ID" = "null" ]; then \
			echo "$(YELLOW)Error: Bastion not deployed. Enable bastion with enable_bastion=true$(NC)"; \
			exit 1; \
		fi && \
		cd ../$(INFRA_DIR) && \
		VPC_CIDR=$$(terraform output -raw vpc_cidr_block 2>/dev/null || terraform output -json 2>/dev/null | jq -r '.vpc_cidr_block.value // empty') && \
		if [ -z "$$VPC_CIDR" ]; then \
			echo "$(YELLOW)Error: VPC CIDR not found in terraform outputs$(NC)"; \
			exit 1; \
		fi && \
		REGION=$$(terraform output -raw region 2>/dev/null || terraform output -json 2>/dev/null | jq -r '.region.value // empty' || echo "us-east-1") && \
		if [ -z "$$REGION" ]; then \
			REGION=$$(grep -E "^region\s*=" ../$(CLUSTER_DIR)/terraform.tfvars 2>/dev/null | cut -d'"' -f2 | cut -d"'" -f2 | head -1 || echo "us-east-1"); \
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
			--pidfile /tmp/sshuttle-public-$$BASTION_ID.pid && \
		echo "$(GREEN)sshuttle tunnel started for VPC $$VPC_CIDR$(NC)" && \
		echo "$(GREEN)All traffic to $$VPC_CIDR is now routed through the bastion$(NC)" && \
		echo "$(GREEN)You can now use oc login with the direct API URL$(NC)" || \
		(echo "$(YELLOW)Failed to start tunnel. Check bastion status and AWS credentials.$(NC)" && echo "$(YELLOW)Note: sshuttle requires sudo privileges.$(NC)" && exit 1)

tunnel-stop: check-cluster
	@echo "$(BLUE)Stopping sshuttle tunnel...$(NC)"
	@cd $(CONFIG_DIR) && \
		BASTION_ID=$$(terraform output -raw bastion_instance_id 2>/dev/null) && \
		if [ -z "$$BASTION_ID" ] || [ "$$BASTION_ID" = "null" ]; then \
			echo "$(YELLOW)Bastion not deployed$(NC)"; \
			exit 0; \
		fi && \
		cd ../$(INFRA_DIR) && \
		VPC_CIDR=$$(terraform output -raw vpc_cidr_block 2>/dev/null || terraform output -json 2>/dev/null | jq -r '.vpc_cidr_block.value // empty') && \
		PIDFILE="/tmp/sshuttle-public-$$BASTION_ID.pid" && \
		if [ -f "$$PIDFILE" ]; then \
			PID=$$(cat $$PIDFILE 2>/dev/null) && \
			if [ -n "$$PID" ] && kill -0 $$PID 2>/dev/null; then \
				sudo kill $$PID && \
				rm -f $$PIDFILE && \
				echo "$(GREEN)Tunnel stopped$(NC)"; \
			else \
				rm -f $$PIDFILE && \
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

tunnel-status: check-cluster
	@echo "$(BLUE)Checking sshuttle tunnel status...$(NC)"
	@cd $(CONFIG_DIR) && \
		BASTION_ID=$$(terraform output -raw bastion_instance_id 2>/dev/null) && \
		if [ -z "$$BASTION_ID" ] || [ "$$BASTION_ID" = "null" ]; then \
			echo "$(YELLOW)Bastion not deployed$(NC)"; \
			exit 1; \
		fi && \
		cd ../$(INFRA_DIR) && \
		VPC_CIDR=$$(terraform output -raw vpc_cidr_block 2>/dev/null || terraform output -json 2>/dev/null | jq -r '.vpc_cidr_block.value // empty') && \
		if [ -z "$$VPC_CIDR" ]; then \
			echo "$(YELLOW)VPC CIDR not found$(NC)"; \
			exit 1; \
		fi && \
		PIDFILE="/tmp/sshuttle-public-$$BASTION_ID.pid" && \
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

bastion-connect: check-cluster
	@echo "$(BLUE)Connecting to bastion via SSM Session Manager...$(NC)"
	@if ! command -v aws >/dev/null 2>&1; then \
		echo "$(YELLOW)Error: aws CLI not found. Please install AWS CLI.$(NC)"; \
		exit 1; \
	fi
	@cd $(CONFIG_DIR) && \
		BASTION_ID=$$(terraform output -raw bastion_instance_id 2>/dev/null) && \
		if [ -z "$$BASTION_ID" ] || [ "$$BASTION_ID" = "null" ]; then \
			echo "$(YELLOW)Error: Bastion not deployed. Enable bastion with enable_bastion=true$(NC)"; \
			exit 1; \
		fi && \
		cd ../$(INFRA_DIR) && \
		REGION=$$(terraform output -raw region 2>/dev/null || terraform output -json 2>/dev/null | jq -r '.region.value // empty' || echo "us-east-1") && \
		if [ -z "$$REGION" ]; then \
			REGION=$$(grep -E "^region\s*=" ../$(CLUSTER_DIR)/terraform.tfvars 2>/dev/null | cut -d'"' -f2 | cut -d"'" -f2 | head -1 || echo "us-east-1"); \
		fi && \
		echo "$(GREEN)Connecting to bastion $$BASTION_ID in region $$REGION...$(NC)" && \
		aws ssm start-session --target $$BASTION_ID --region $$REGION || \
		(echo "$(YELLOW)Failed to connect. Check AWS credentials and bastion status.$(NC)" && exit 1)

# Validate
validate:
	@cd $(INFRA_DIR) && terraform init -backend=false && terraform validate
	@cd $(CONFIG_DIR) && terraform init -backend=false && terraform validate

# Format
fmt:
	@terraform fmt -recursive

# Clean
clean:
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	@find . -name "terraform.tfplan" -delete 2>/dev/null || true
