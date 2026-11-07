output "state_bucket" {
  description = "Ye naam terraform/stacks/platform/backend.hcl mein daalna hai"
  value       = aws_s3_bucket.state.bucket
}
