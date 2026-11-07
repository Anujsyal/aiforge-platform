output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "private_subnet_cidrs" {
  value = aws_subnet.private[*].cidr_block
}

output "nat_public_ips" {
  description = "Cluster ka egress IP (external APIs ko yahi IP dikhta hai)"
  value       = aws_eip.nat[*].public_ip
}

output "flow_log_group" {
  value = aws_cloudwatch_log_group.flow.name
}
