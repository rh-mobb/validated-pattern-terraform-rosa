#!/bin/bash
#------------------------------------------------------------------------------
# Apply CUDN and BGP test resources
# Applies the bgp.yaml containing CUDNs, RouteAdvertisements, and test VMs
#------------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BGP_YAML="${SCRIPT_DIR}/bgp.yaml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}Applying BGP/CUDN resources...${NC}"

# Check prerequisites
if ! command -v oc &> /dev/null; then
    echo -e "${RED}Error: 'oc' CLI not found. Please install OpenShift CLI.${NC}"
    exit 1
fi

if ! oc whoami &> /dev/null; then
    echo -e "${RED}Error: Not logged into OpenShift cluster. Run 'oc login' first.${NC}"
    exit 1
fi

if [ ! -f "$BGP_YAML" ]; then
    echo -e "${RED}Error: bgp.yaml not found at ${BGP_YAML}${NC}"
    exit 1
fi

# Check if RouteAdvertisements CRD exists
if ! oc api-resources | grep -q "RouteAdvertisements"; then
    echo -e "${YELLOW}Warning: RouteAdvertisements CRD not found.${NC}"
    echo -e "${YELLOW}The OVN-Kubernetes RouteAdvertisements feature may not be enabled.${NC}"
    echo -e "${YELLOW}Continuing anyway - CRD may be created after FRR operator is installed.${NC}"
fi

# Apply the resources
echo -e "${BLUE}Applying resources from bgp.yaml...${NC}"
oc apply -f "$BGP_YAML"

echo ""
echo -e "${GREEN}BGP/CUDN resources applied successfully!${NC}"
echo ""
echo -e "${BLUE}Resources created:${NC}"
echo "  - Namespaces: cudn1, cudn2, cudn3, cudn4"
echo "  - Layer2 CUDNs: cluster-udn-layer2-prod (10.100.0.0/16), cluster-udn-layer2-dev (10.200.0.0/16)"
echo "  - Layer3 CUDN: cluster-udn-layer3 (10.150.0.0/16)"
echo "  - RouteAdvertisements: default"
echo "  - VirtualMachines:"
echo "      Layer2: l2-vm1 (cudn1), l2-vm2 (cudn2), l2-vm3 (cudn2)"
echo "      Layer3: l3-vm1 (cudn3), l3-vm2 (cudn3), l3-vm3 (cudn4)"
echo ""
echo -e "${BLUE}To check resources:${NC}"
echo "  oc get clusteruserdefinednetworks"
echo "  oc get routeadvertisements"
echo "  oc get vm -A"
echo ""
echo -e "${BLUE}VM credentials:${NC}"
echo "  Username: fedora"
echo "  Password: redhat"
echo ""
echo -e "${BLUE}To access VMs:${NC}"
echo "  virtctl console l2-vm1 -n cudn1"
echo "  virtctl console l3-vm1 -n cudn3"
