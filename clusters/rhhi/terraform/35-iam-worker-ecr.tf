# Attach ECR read policy to ROSA worker instance role for runtime image pulls.
# Public clusters do not get this via module.iam unless zero_egress=true.
# Reference: modules/infrastructure/iam/10-main.tf worker_ecr_readonly

resource "aws_iam_role_policy_attachment" "worker_ecr_readonly" {
  count = var.persists_through_sleep ? 1 : 0

  role       = "${var.account_role_prefix}-HCP-ROSA-Worker-Role"
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
