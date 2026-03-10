#!/bin/bash
#------------------------------------------------------------------------------
# Apply FRRConfiguration for BGP peering
# Generates and applies the FRRConfiguration CRD using Terraform outputs
#------------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/terraform"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}Generating FRRConfiguration from Terraform outputs...${NC}"

# Check prerequisites
if ! command -v oc &> /dev/null; then
    echo -e "${RED}Error: 'oc' CLI not found. Please install OpenShift CLI.${NC}"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: 'jq' not found. Please install jq.${NC}"
    exit 1
fi

if ! oc whoami &> /dev/null; then
    echo -e "${RED}Error: Not logged into OpenShift cluster. Run 'oc login' first.${NC}"
    exit 1
fi

#------------------------------------------------------------------------------
# Enable FRR and Route Advertisements on the cluster
#------------------------------------------------------------------------------
echo -e "${BLUE}Enabling FRR routing capabilities and route advertisements...${NC}"

# Check current state
CURRENT_PROVIDERS=$(oc get Network.operator.openshift.io cluster -o jsonpath='{.spec.additionalRoutingCapabilities.providers}' 2>/dev/null || echo "")
CURRENT_RA=$(oc get Network.operator.openshift.io cluster -o jsonpath='{.spec.defaultNetwork.ovnKubernetesConfig.routeAdvertisements}' 2>/dev/null || echo "")

if [[ "$CURRENT_PROVIDERS" == *"FRR"* ]] && [ "$CURRENT_RA" = "Enabled" ]; then
    echo -e "${GREEN}FRR and route advertisements already enabled.${NC}"
else
    echo -e "${YELLOW}Patching Network.operator.openshift.io cluster to enable FRR...${NC}"
    oc patch Network.operator.openshift.io cluster --type=merge -p='{"spec":{"additionalRoutingCapabilities": {"providers": ["FRR"]}, "defaultNetwork":{"ovnKubernetesConfig":{"routeAdvertisements":"Enabled"}}}}'
    
    echo -e "${YELLOW}Waiting for network operator to reconcile (this may take a few minutes)...${NC}"
    sleep 10
    
    # Wait for FRR namespace to be created
    echo -e "${BLUE}Waiting for openshift-frr-k8s namespace...${NC}"
    for i in {1..30}; do
        if oc get namespace openshift-frr-k8s &>/dev/null; then
            echo -e "${GREEN}openshift-frr-k8s namespace created.${NC}"
            break
        fi
        echo "  Waiting... ($i/30)"
        sleep 10
    done
    
    if ! oc get namespace openshift-frr-k8s &>/dev/null; then
        echo -e "${RED}Error: openshift-frr-k8s namespace not created after 5 minutes.${NC}"
        echo -e "${RED}Check network operator status: oc get co network${NC}"
        exit 1
    fi
fi

# Wait for FRR pods to be ready
echo -e "${BLUE}Waiting for FRR pods to be ready...${NC}"
for i in {1..60}; do
    READY_PODS=$(oc get pods -n openshift-frr-k8s -l app=frr-k8s --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$READY_PODS" -gt 0 ]; then
        echo -e "${GREEN}FRR pods are running ($READY_PODS pods).${NC}"
        break
    fi
    echo "  Waiting for FRR pods... ($i/60)"
    sleep 5
done

# Wait for webhook service to have endpoints
echo -e "${BLUE}Waiting for FRR webhook service to be ready...${NC}"
for i in {1..60}; do
    ENDPOINTS=$(oc get endpoints frr-k8s-webhook-service -n openshift-frr-k8s -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
    if [ -n "$ENDPOINTS" ]; then
        echo -e "${GREEN}FRR webhook service is ready.${NC}"
        break
    fi
    echo "  Waiting for webhook endpoints... ($i/60)"
    sleep 5
done

if [ -z "$ENDPOINTS" ]; then
    echo -e "${RED}Error: FRR webhook service not ready after 5 minutes.${NC}"
    echo -e "${RED}Check FRR pods: oc get pods -n openshift-frr-k8s${NC}"
    exit 1
fi

cd "$TERRAFORM_DIR"

# Check if BGP is enabled
BGP_ENABLED=$(terraform output -raw bgp_enabled 2>/dev/null || echo "false")
if [ "$BGP_ENABLED" != "true" ]; then
    echo -e "${YELLOW}Warning: BGP is not enabled (enable_bgp=false).${NC}"
    echo -e "${YELLOW}Set enable_bgp=true in terraform.tfvars and run terraform apply.${NC}"
    exit 1
fi

# Get Terraform outputs
ROSA_ASN=$(terraform output -raw bgp_rosa_asn 2>/dev/null || echo "")
RS_ASN=$(terraform output -raw bgp_route_server_asn 2>/dev/null || echo "")

if [ -z "$ROSA_ASN" ] || [ -z "$RS_ASN" ]; then
    echo -e "${RED}Error: Could not get BGP ASN values from Terraform outputs.${NC}"
    echo -e "${RED}Run 'terraform apply' first.${NC}"
    exit 1
fi

# Get route server endpoint IPs
EP_IPS=$(terraform output -json bgp_route_server_endpoint_ips 2>/dev/null || echo "null")
if [ "$EP_IPS" = "null" ]; then
    echo -e "${RED}Error: Could not get route server endpoint IPs.${NC}"
    echo -e "${RED}Ensure BGP infrastructure is created (terraform apply with enable_bgp=true).${NC}"
    exit 1
fi

SUBNET1_EP1=$(echo "$EP_IPS" | jq -r '.subnet1_ep1 // empty')
SUBNET1_EP2=$(echo "$EP_IPS" | jq -r '.subnet1_ep2 // empty')
SUBNET2_EP1=$(echo "$EP_IPS" | jq -r '.subnet2_ep1 // empty')
SUBNET2_EP2=$(echo "$EP_IPS" | jq -r '.subnet2_ep2 // empty')
SUBNET3_EP1=$(echo "$EP_IPS" | jq -r '.subnet3_ep1 // empty')
SUBNET3_EP2=$(echo "$EP_IPS" | jq -r '.subnet3_ep2 // empty')

cd - > /dev/null

echo -e "${GREEN}Configuration:${NC}"
echo "  ROSA ASN:         $ROSA_ASN"
echo "  Route Server ASN: $RS_ASN"
echo "  Endpoints:        ${SUBNET1_EP1:-N/A}, ${SUBNET1_EP2:-N/A}, ${SUBNET2_EP1:-N/A}, ${SUBNET2_EP2:-N/A}, ${SUBNET3_EP1:-N/A}, ${SUBNET3_EP2:-N/A}"

# Build neighbors array dynamically (only include non-empty endpoints)
NEIGHBORS=""
for EP in "$SUBNET1_EP1" "$SUBNET1_EP2" "$SUBNET2_EP1" "$SUBNET2_EP2" "$SUBNET3_EP1" "$SUBNET3_EP2"; do
    if [ -n "$EP" ]; then
        NEIGHBORS="${NEIGHBORS}
      - address: ${EP}
        asn: ${RS_ASN}
        disableMP: true
        toReceive:
          allowed:
            mode: all"
    fi
done

if [ -z "$NEIGHBORS" ]; then
    echo -e "${RED}Error: No route server endpoints found.${NC}"
    exit 1
fi

echo -e "${BLUE}Applying FRRConfiguration...${NC}"

cat << EOF | oc apply -f -
apiVersion: frrk8s.metallb.io/v1beta1
kind: FRRConfiguration
metadata:
  name: all-nodes
  namespace: openshift-frr-k8s
spec:
  nodeSelector:
    matchLabels:
      bgp_router: "true"
  bgp:
    routers:
    - asn: ${ROSA_ASN}
      neighbors:${NEIGHBORS}
EOF

echo -e "${GREEN}FRRConfiguration applied successfully!${NC}"
echo ""
echo -e "${BLUE}To verify BGP peering status:${NC}"
echo "  oc get frrconfiguration -n openshift-frr-k8s"
echo "  oc get pods -n openshift-frr-k8s -l app=frr-k8s"
