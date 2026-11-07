output "role_arn" {
  description = "GitHub repo secret AWS_CI_ROLE_ARN mein ye daalna hai"
  value       = aws_iam_role.ci.arn
}
