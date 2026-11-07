output "server_instance_id" {
  value = aws_instance.server.id
}

output "server_private_ip" {
  value = aws_instance.server.private_ip
}

output "agent_instance_ids" {
  value = aws_instance.agent[*].id
}

output "node_security_group_id" {
  value = aws_security_group.nodes.id
}

output "node_role_name" {
  value = aws_iam_role.nodes.name
}

output "kubeconfig_parameter" {
  value = local.kubeconfig_param
}
