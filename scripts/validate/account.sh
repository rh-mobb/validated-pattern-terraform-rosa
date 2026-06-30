#!/usr/bin/env bash
# Account and operator-machine validation for ROSA HCP deployments.
# Adapted from reference/ROSAHcpZeroEgressPrerequisites/scripts/validate-bastion.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
MIN_VCPU=100
SKIP_CONNECTIVITY=false

while [[ $# -gt 0 ]]; do
	case "$1" in
	--region)
		REGION="$2"
		shift 2
		;;
	--min-vcpu)
		MIN_VCPU="$2"
		shift 2
		;;
	--skip-connectivity)
		SKIP_CONNECTIVITY=true
		shift
		;;
	-h | --help)
		echo "Usage: $0 [--region REGION] [--min-vcpu N] [--skip-connectivity]"
		exit 0
		;;
	*)
		echo "Unknown option: $1"
		exit 1
		;;
	esac
done

export AWS_DEFAULT_REGION="$REGION"

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║  ROSA HCP — Account Prerequisites Validation                ║"
printf "║  Region: %-52s ║\n" "$REGION"
echo "╚═══════════════════════════════════════════════════════════════╝"

header "CLI TOOLS"
check_tool rosa "1.2.48" "ROSA CLI"
check_tool aws "2.0" "AWS CLI"
check_tool oc "4.17" "OpenShift CLI (oc)"
check_tool terraform "1.4.0" "Terraform"
check_tool git "2.0" "Git"
check_tool jq "1.6" "jq"
check_tool curl "7.0" "curl"

header "AWS CREDENTIALS & REGION"
CALLER_IDENTITY=$(aws sts get-caller-identity --output json 2>&1) || true
if echo "$CALLER_IDENTITY" | jq -e '.Account' &>/dev/null; then
	AWS_ACCOUNT=$(echo "$CALLER_IDENTITY" | jq -r '.Account')
	AWS_ARN=$(echo "$CALLER_IDENTITY" | jq -r '.Arn')
	pass "AWS credentials valid — Account: $AWS_ACCOUNT"
	info "IAM identity: $AWS_ARN"
else
	fail "AWS credentials not configured or expired"
fi

if [[ -n "${AWS_DEFAULT_REGION:-}" ]]; then
	pass "Region is set to $REGION"
else
	warn "Set AWS_DEFAULT_REGION=$REGION for consistency"
fi

header "ROSA ACCOUNT LINKING"
if command -v rosa &>/dev/null; then
	ROSA_WHOAMI=$(rosa whoami 2>&1) || true
	if echo "$ROSA_WHOAMI" | grep -q "OCM API"; then
		pass "ROSA CLI logged in"
	else
		fail "ROSA CLI not logged in — run: rosa login --token=<OCM_TOKEN>"
	fi

	OCM_ROLE_OUTPUT=$(rosa list ocm-role 2>&1) || true
	if echo "$OCM_ROLE_OUTPUT" | grep -qi "yes.*yes"; then
		pass "OCM Role: linked with admin"
	elif echo "$OCM_ROLE_OUTPUT" | grep -qi "yes"; then
		warn "OCM Role exists but may not have admin"
	else
		fail "OCM Role not found or not linked"
	fi

	USER_ROLE_OUTPUT=$(rosa list user-role 2>&1) || true
	if echo "$USER_ROLE_OUTPUT" | grep -qi "yes"; then
		pass "User Role: linked"
	else
		fail "User Role not found or not linked"
	fi

	ACCOUNT_ROLES=$(rosa list account-roles 2>&1) || true
	HCP_ROLES=$(echo "$ACCOUNT_ROLES" | grep -c "HCP" || true)
	if [[ "$HCP_ROLES" -ge 3 ]]; then
		pass "HCP Account Roles found: $HCP_ROLES"
	else
		warn "HCP Account Roles: only $HCP_ROLES found"
	fi
else
	fail "ROSA CLI not installed"
fi

ELB_SLR=$(aws iam get-role --role-name AWSServiceRoleForElasticLoadBalancing 2>&1) || true
if echo "$ELB_SLR" | jq -e '.Role.RoleName' &>/dev/null; then
	pass "ELB service-linked role exists"
else
	fail "ELB service-linked role missing"
fi

header "AWS SERVICE QUOTAS"
VCPU_QUOTA=$(aws service-quotas get-service-quota \
	--service-code ec2 --quota-code L-1216C47A \
	--query 'Quota.Value' --output text 2>/dev/null || echo "0")
if float_gte "$VCPU_QUOTA" "$MIN_VCPU"; then
	pass "On-Demand Standard vCPU quota: $VCPU_QUOTA (minimum: $MIN_VCPU)"
else
	fail "On-Demand Standard vCPU quota: $VCPU_QUOTA — need at least $MIN_VCPU"
fi

header "ROSA VERIFY"
if command -v rosa &>/dev/null; then
	ROSA_VERIFY=$(rosa verify permissions 2>&1) || true
	if echo "$ROSA_VERIFY" | grep -qi "sufficient\|have required permissions"; then
		pass "rosa verify permissions: sufficient"
	elif echo "$ROSA_VERIFY" | grep -qi "error\|fail\|denied"; then
		fail "rosa verify permissions: failed"
	else
		info "rosa verify permissions: $(echo "$ROSA_VERIFY" | head -1)"
	fi

	ROSA_QUOTA=$(rosa verify quota --region="$REGION" 2>&1) || true
	if echo "$ROSA_QUOTA" | grep -qi "sufficient\|validated"; then
		pass "rosa verify quota: sufficient in $REGION"
	elif echo "$ROSA_QUOTA" | grep -qi "error\|fail\|insufficient"; then
		fail "rosa verify quota: failed in $REGION"
	else
		info "rosa verify quota: $(echo "$ROSA_QUOTA" | head -1)"
	fi
fi

if [[ "$SKIP_CONNECTIVITY" == "false" ]]; then
	header "NETWORK CONNECTIVITY"
	info "Testing HTTPS reachability to required external services..."
	check_url "https://sso.redhat.com" "sso.redhat.com"
	check_url "https://api.openshift.com" "api.openshift.com"
	check_url "https://console.redhat.com" "console.redhat.com"
	check_url "https://registry.terraform.io" "registry.terraform.io"
	check_url "https://releases.hashicorp.com" "releases.hashicorp.com"
	check_url "https://mirror.openshift.com" "mirror.openshift.com"
	check_url "https://github.com" "github.com"
fi

exit_with_summary "ACCOUNT PREREQUISITES SUMMARY"
