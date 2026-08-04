# Route Server Module

AWS VPC Route Server for BGP routing with the [CUDN BGP routing operator](https://github.com/jingczhang/rosa-bgp-operator).

## What it creates

- **VPC Route Server** with configurable Amazon-side ASN
- **Route Server endpoints** (2 per private subnet) for BGP peering
- **Route propagation** to private and public route tables
- **IAM role and policy** for the CUDN BGP routing operator (IRSA)

## How it works with the operator

1. Terraform creates the Route Server, endpoints, and IAM role
2. The BGP operator discovers endpoints automatically via `DescribeRouteServerEndpoints`
3. The operator creates Route Server peers for each BGP-enabled worker node
4. The operator manages ENI SourceDestCheck and FRR configuration

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| cluster_name | Name prefix for resources | string | - | yes |
| vpc_id | VPC to associate Route Server with | string | - | yes |
| private_subnet_ids | Private subnets for endpoints (2 per subnet) | list(string) | - | yes |
| private_route_table_ids | Private route tables for propagation | list(string) | - | yes |
| public_route_table_ids | Public route tables for propagation | list(string) | [] | no |
| oidc_endpoint_url | OIDC endpoint URL for IRSA trust | string | - | yes |
| route_server_asn | Amazon-side ASN | number | 64512 | no |
| persist_routes | Persist routes on BGP session loss | string | "disable" | no |
| tags | Tags for all resources | map(string) | {} | no |
| persists_through_sleep | Sleep mode gating | bool | true | no |
| custom_permissions_boundary_arn | Permission boundary for IAM role | string | null | no |

## Outputs

| Name | Description |
|------|-------------|
| route_server_id | Route Server ID (for CUDNBgpConfig CR `spec.aws.routeServerIDs`) |
| route_server_asn | Amazon-side ASN |
| endpoint_ips | Map of endpoint key to ENI IP address |
| endpoint_details | Map of endpoint key to full details |
| bgp_operator_role_arn | IAM role ARN (for ServiceAccount annotation) |

## Post-deploy steps

After `terraform apply`, annotate the operator's ServiceAccount:

```bash
BGP_ROLE_ARN=$(terraform output -raw bgp_operator_role_arn)
oc annotate serviceaccount openshift-cudn-bgp-routing-controller-manager \
  -n openshift-cudn-bgp-routing \
  eks.amazonaws.com/role-arn=$BGP_ROLE_ARN
```
