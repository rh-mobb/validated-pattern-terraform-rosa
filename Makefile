.PHONY: help init plan apply destroy fmt validate clean
.DEFAULT_GOAL := help

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
NC := \033[0m # No Color

# Cluster directories mapping
# Maps cluster name (e.g., "public") to directory path
define cluster_dir
$(if $(filter public,$1),clusters/examples/public,\
$(if $(filter private,$1),clusters/examples/private,\
$(if $(filter egress-zero,$1),clusters/examples/egress-zero,\
$(error Unknown cluster: $1))))
endef

# Helper function to get cluster directory from target suffix
# Usage: $(call get_cluster_dir,$*)
get_cluster_dir = $(call cluster_dir,$*)

# Backwards compatibility - explicit cluster directories
CLUSTER_PUBLIC := clusters/examples/public
CLUSTER_PRIVATE := clusters/examples/private
CLUSTER_EGRESS_ZERO := clusters/examples/egress-zero

help: ## Show this help message
	@echo "$(BLUE)ROSA HCP Infrastructure - Makefile Targets$(NC)"
	@echo ""
	@echo "$(GREEN)Cluster Management:$(NC)"
	@echo "  Pattern syntax: make <action>.<cluster>"
	@echo "  Examples: make init.public, make plan.private, make apply.egress-zero"
	@echo ""
	@echo "  make init.<cluster>       Initialize Terraform (clusters: public, private, egress-zero)"
	@echo "  make plan.<cluster>       Plan cluster deployment (saves to terraform.tfplan)"
	@echo "  make apply.<cluster>      Apply cluster configuration (uses terraform.tfplan)"
	@echo "  make destroy.<cluster>    Destroy cluster"
	@echo ""
	@echo "  Legacy syntax (still supported):"
	@echo "  make init-public, plan-public, apply-public, destroy-public"
	@echo "  make init-private, plan-private, apply-private, destroy-private"
	@echo "  make init-egress-zero, plan-egress-zero, apply-egress-zero, destroy-egress-zero"
	@echo ""
	@echo "$(GREEN)Code Quality:$(NC)"
	@echo "  make fmt                  Format all Terraform files"
	@echo "  make validate             Validate all Terraform modules"
	@echo "  make validate-modules     Validate all modules"
	@echo "  make validate-examples    Validate all example clusters"
	@echo ""
	@echo "$(GREEN)Utilities:$(NC)"
	@echo "  make clean                Clean Terraform files (.terraform, .terraform.lock.hcl)"
	@echo "  make init-all             Initialize all clusters"
	@echo "  make plan-all             Plan all clusters"
	@echo ""
	@echo "$(GREEN)Cluster Access:$(NC)"
	@echo "  Pattern syntax: make <action>.<cluster>"
	@echo "  Examples: make login.public, make show-endpoints.private, make show-credentials.egress-zero"
	@echo ""
	@echo "  make login.<cluster>            Login to cluster using oc CLI"
	@echo "  make show-endpoints.<cluster>    Show API and console URLs"
	@echo "  make show-credentials.<cluster>  Show admin credentials and endpoints"
	@echo ""
	@echo "$(GREEN)Bastion & Tunnel Management:$(NC)"
	@echo "  Pattern syntax: make <action>.<cluster>"
	@echo "  Examples: make tunnel-start.private, make tunnel-stop.egress-zero"
	@echo ""
	@echo "  make tunnel-start.<cluster>     Start sshuttle VPN tunnel via bastion (routes all VPC traffic)"
	@echo "                                   Requires: sshuttle (brew install sshuttle on macOS)"
	@echo "  make tunnel-stop.<cluster>      Stop sshuttle tunnel"
	@echo "  make tunnel-status.<cluster>    Check if tunnel is running"
	@echo "  make bastion-connect.<cluster>  Connect to bastion via SSM Session Manager"
	@echo ""
	@echo "  Legacy syntax (still supported):"
	@echo "  make login-public, show-endpoints-public, show-credentials-public"
	@echo "  make login-private, show-endpoints-private, show-credentials-private"
	@echo "  make login-egress-zero, show-endpoints-egress-zero, show-credentials-egress-zero"
	@echo ""

# Initialize Terraform for clusters
# Pattern rule: make init.public, make init.private, make init.egress-zero
init.%:
	@echo "$(BLUE)Initializing $* cluster...$(NC)"
	@cd $(call get_cluster_dir,$*) && terraform init -reconfigure

# Explicit targets for backwards compatibility
init-public: init.public ## Initialize Terraform for public cluster
init-private: init.private ## Initialize Terraform for private cluster
init-egress-zero: init.egress-zero ## Initialize Terraform for egress-zero cluster

init-all: init.public init.private init.egress-zero ## Initialize all clusters

# Plan deployments (depend on init to ensure backend is configured)
# Pattern rule: make plan.public, make plan.private, make plan.egress-zero
plan.%: init.%
	@echo "$(BLUE)Planning $* cluster...$(NC)"
	@cd $(call get_cluster_dir,$*) && terraform plan -out=terraform.tfplan

# Explicit targets for backwards compatibility
plan-public: plan.public ## Plan public cluster deployment
plan-private: plan.private ## Plan private cluster deployment
plan-egress-zero: plan.egress-zero ## Plan egress-zero cluster deployment

plan-all: plan.public plan.private plan.egress-zero ## Plan all clusters

# Apply configurations (depend on init and plan)
# Pattern rule: make apply.public, make apply.private, make apply.egress-zero
apply.%: init.% plan.%
	@echo "$(YELLOW)Applying $* cluster configuration...$(NC)"
	@cd $(call get_cluster_dir,$*) && terraform apply terraform.tfplan

# Explicit targets for backwards compatibility
apply-public: apply.public ## Apply public cluster configuration
apply-private: apply.private ## Apply private cluster configuration
apply-egress-zero: apply.egress-zero ## Apply egress-zero cluster configuration

# Destroy clusters
# Pattern rule: make destroy.public, make destroy.private, make destroy.egress-zero
# Terraform automatically handles destroy order: cluster depends on IAM outputs, so cluster is destroyed first
destroy.%:
	@echo "$(YELLOW)WARNING: This will destroy the $* cluster!$(NC)"
	@cd $(call get_cluster_dir,$*) && terraform destroy -auto-approve

# Explicit targets for backwards compatibility
destroy-public: destroy.public ## Destroy public cluster
destroy-private: destroy.private ## Destroy private cluster
destroy-egress-zero: destroy.egress-zero ## Destroy egress-zero cluster

# Code quality
fmt: ## Format all Terraform files
	@echo "$(BLUE)Formatting Terraform files...$(NC)"
	terraform fmt -recursive

validate: validate-modules validate-examples ## Validate all Terraform code

validate-modules: ## Validate all modules
	@echo "$(BLUE)Validating modules...$(NC)"
	@for dir in modules/*/; do \
		echo "Validating $$dir..."; \
		cd $$dir && terraform init -backend=false >/dev/null 2>&1 && terraform validate && cd - >/dev/null || echo "  ✗ Failed: $$dir"; \
	done

validate-examples: ## Validate all example clusters
	@echo "$(BLUE)Validating example clusters...$(NC)"
	@for dir in $(CLUSTER_PUBLIC) $(CLUSTER_PRIVATE) $(CLUSTER_EGRESS_ZERO); do \
		echo "Validating $$dir..."; \
		cd $$dir && terraform init -backend=false >/dev/null 2>&1 && terraform validate && cd - >/dev/null || echo "  ✗ Failed: $$dir"; \
	done

# Cluster Access - Show Endpoints
# Pattern rule: make show-endpoints.public, make show-endpoints.private, make show-endpoints.egress-zero
show-endpoints.%:
	@echo "$(BLUE)$(shell echo $* | tr '[:lower:]' '[:upper:]' | sed 's/-/ /g') Cluster Endpoints:$(NC)"
	@cd $(call get_cluster_dir,$*) && \
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
show-endpoints-private: show-endpoints.private ## Show API and console URLs for private cluster
show-endpoints-egress-zero: show-endpoints.egress-zero ## Show API and console URLs for egress-zero cluster

# Cluster Access - Show Credentials (includes endpoints)
# Pattern rule: make show-credentials.public, make show-credentials.private, make show-credentials.egress-zero
show-credentials.%: show-endpoints.%
	@echo "$(BLUE)$(shell echo $* | tr '[:lower:]' '[:upper:]' | sed 's/-/ /g') Cluster Credentials:$(NC)"
	@cd $(call get_cluster_dir,$*) && \
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
show-credentials-private: show-credentials.private ## Show admin credentials and endpoints for private cluster
show-credentials-egress-zero: show-credentials.egress-zero ## Show admin credentials and endpoints for egress-zero cluster

# Cluster Access - Login
# Pattern rule: make login.public, make login.private, make login.egress-zero
login.%:
	@echo "$(BLUE)Logging into $* cluster...$(NC)"
	@if ! command -v oc >/dev/null 2>&1; then \
		echo "$(YELLOW)Error: oc CLI not found. Please install OpenShift CLI.$(NC)"; \
		exit 1; \
	fi
	@cd $(call get_cluster_dir,$*) && \
		API_URL=$$(terraform output -raw api_url 2>/dev/null) && \
		if [ -z "$$API_URL" ]; then \
			echo "$(YELLOW)Error: Cluster not deployed or api_url output not available$(NC)"; \
			exit 1; \
		fi && \
		VPC_CIDR=$$(terraform output -raw vpc_cidr_block 2>/dev/null || terraform output -json 2>/dev/null | jq -r '.vpc_cidr_block.value // empty') && \
		if [ -n "$$VPC_CIDR" ] && pgrep -f "sshuttle.*$$VPC_CIDR" >/dev/null 2>&1; then \
			echo "$(GREEN)sshuttle tunnel active - using direct API URL (traffic routed through bastion)$(NC)"; \
		fi && \
		LOGIN_URL=$$API_URL && \
		if [ -z "$$TF_VAR_admin_password" ]; then \
			if [ -f "terraform.tfvars" ]; then \
				ADMIN_PASSWORD=$$(grep -E "^admin_password\s*=" terraform.tfvars | sed -E "s/^[^=]*=\s*['\"]?([^'\"]+)['\"]?/\1/" | head -1); \
				if [ -z "$$ADMIN_PASSWORD" ]; then \
					echo "$(YELLOW)Error: Admin password not found. Set TF_VAR_admin_password or add to terraform.tfvars$(NC)"; \
					exit 1; \
				fi; \
			else \
				echo "$(YELLOW)Error: Admin password required. Set TF_VAR_admin_password or add to terraform.tfvars$(NC)"; \
				exit 1; \
			fi; \
		else \
			ADMIN_PASSWORD=$$TF_VAR_admin_password; \
		fi && \
		oc login $$LOGIN_URL --username admin --password $$ADMIN_PASSWORD --insecure-skip-tls-verify=false || \
		(echo "$(YELLOW)Login failed. Check credentials and cluster status.$(NC)" && exit 1)

# Explicit targets for backwards compatibility
login-public: login.public ## Login to public cluster using oc CLI
login-private: login.private ## Login to private cluster using oc CLI
login-egress-zero: login.egress-zero ## Login to egress-zero cluster using oc CLI

# Bastion & Tunnel Management
# Pattern rule: make tunnel-start.private, make tunnel-stop.egress-zero, etc.
# Uses sshuttle to create a VPN-like tunnel for full cluster access (including OAuth)
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
	@cd $(call get_cluster_dir,$*) && \
		BASTION_ID=$$(terraform output -raw bastion_instance_id 2>/dev/null) && \
		if [ -z "$$BASTION_ID" ] || [ "$$BASTION_ID" = "null" ]; then \
			echo "$(YELLOW)Error: Bastion not deployed. Enable bastion with enable_bastion=true$(NC)"; \
			exit 1; \
		fi && \
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
	@cd $(call get_cluster_dir,$*) && \
		BASTION_ID=$$(terraform output -raw bastion_instance_id 2>/dev/null) && \
		if [ -z "$$BASTION_ID" ] || [ "$$BASTION_ID" = "null" ]; then \
			echo "$(YELLOW)Bastion not deployed$(NC)"; \
			exit 0; \
		fi && \
		PIDFILE="/tmp/sshuttle-$$*-$$BASTION_ID.pid" && \
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
			VPC_CIDR=$$(terraform output -raw vpc_cidr_block 2>/dev/null || terraform output -json 2>/dev/null | jq -r '.vpc_cidr_block.value // empty') && \
			if [ -n "$$VPC_CIDR" ] && pgrep -f "sshuttle.*$$VPC_CIDR" >/dev/null 2>&1; then \
				sudo pkill -f "sshuttle.*$$VPC_CIDR" && \
				echo "$(GREEN)Tunnel stopped$(NC)"; \
			else \
				echo "$(YELLOW)No tunnel found running$(NC)"; \
			fi; \
		fi

tunnel-status.%:
	@echo "$(BLUE)Checking sshuttle tunnel status for $* cluster...$(NC)"
	@cd $(call get_cluster_dir,$*) && \
		BASTION_ID=$$(terraform output -raw bastion_instance_id 2>/dev/null) && \
		if [ -z "$$BASTION_ID" ] || [ "$$BASTION_ID" = "null" ]; then \
			echo "$(YELLOW)Bastion not deployed$(NC)"; \
			exit 1; \
		fi && \
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
	@cd $(call get_cluster_dir,$*) && \
		BASTION_ID=$$(terraform output -raw bastion_instance_id 2>/dev/null) && \
		if [ -z "$$BASTION_ID" ] || [ "$$BASTION_ID" = "null" ]; then \
			echo "$(YELLOW)Error: Bastion not deployed. Enable bastion with enable_bastion=true$(NC)"; \
			exit 1; \
		fi && \
		REGION=$$(terraform output -raw region 2>/dev/null || terraform output -json 2>/dev/null | jq -r '.region.value // empty' || echo "us-east-1") && \
		if [ -z "$$REGION" ]; then \
			REGION=$$(grep -E "^region\s*=" terraform.tfvars 2>/dev/null | cut -d'"' -f2 | cut -d"'" -f2 | head -1 || echo "us-east-1"); \
		fi && \
		echo "$(GREEN)Connecting to bastion $$BASTION_ID in region $$REGION...$(NC)" && \
		aws ssm start-session --target $$BASTION_ID --region $$REGION || \
		(echo "$(YELLOW)Failed to connect. Check AWS credentials and bastion status.$(NC)" && exit 1)

# Explicit targets for backwards compatibility
tunnel-start-private: tunnel-start.private ## Start SSH tunnel for private cluster
tunnel-start-egress-zero: tunnel-start.egress-zero ## Start SSH tunnel for egress-zero cluster
tunnel-stop-private: tunnel-stop.private ## Stop SSH tunnel for private cluster
tunnel-stop-egress-zero: tunnel-stop.egress-zero ## Stop SSH tunnel for egress-zero cluster
tunnel-status-private: tunnel-status.private ## Check tunnel status for private cluster
tunnel-status-egress-zero: tunnel-status.egress-zero ## Check tunnel status for egress-zero cluster
bastion-connect-private: bastion-connect.private ## Connect to private cluster bastion
bastion-connect-egress-zero: bastion-connect.egress-zero ## Connect to egress-zero cluster bastion

# Cleanup
clean: ## Clean Terraform files (.terraform directories and lock files)
	@echo "$(BLUE)Cleaning Terraform files...$(NC)"
	find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	find . -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	@echo "$(GREEN)Cleanup complete$(NC)"
