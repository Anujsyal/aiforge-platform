output "repository_urls" {
  value = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "repository_arns" {
  value = [for r in aws_ecr_repository.this : r.arn]
}

output "registry" {
  description = "<account>.dkr.ecr.<region>.amazonaws.com"
  value       = split("/", values(aws_ecr_repository.this)[0].repository_url)[0]
}
