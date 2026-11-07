output "vpc_id" {
  description = "ALB controller Helm values (vpcId) mein"
  value       = module.vpc.vpc_id
}

output "nat_public_ips" {
  value = module.vpc.nat_public_ips
}

output "server_instance_id" {
  description = "SSM port-forward aur session ke liye"
  value       = module.cluster.server_instance_id
}

output "agent_instance_ids" {
  value = module.cluster.agent_instance_ids
}

output "kubeconfig_parameter" {
  value = module.cluster.kubeconfig_parameter
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "ecr_registry" {
  value = module.ecr.registry
}

output "github_ci_role_arn" {
  description = "GitHub repo → Settings → Secrets → AWS_CI_ROLE_ARN"
  value       = module.github_oidc.role_arn
}

output "budget_sns_topic_arn" {
  value = module.budgets.sns_topic_arn
}

output "crossplane_iam_user" {
  value = aws_iam_user.crossplane.name
}

output "next_steps" {
  value = <<-EOT
    1. Bootstrap log (2-4 min):  aws ssm start-session --target ${module.cluster.server_instance_id}  →  sudo tail -f /var/log/k3s-bootstrap.log
    2. Kubeconfig:               ./scripts/get-kubeconfig.sh
    3. API tunnel (alag terminal): ./scripts/tunnel.sh
    4. kubectl get nodes -o wide
  EOT
}
