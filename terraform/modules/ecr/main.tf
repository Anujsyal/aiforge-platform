# ECR repos: rag-app (sample RAG app) + backstage (platform portal).
# IMMUTABLE tags: ek baar push hua tag dobara overwrite nahi ho sakta (cosign signature
# digest pe hoti hai, par immutable tags se "kaunsa code chal raha hai" hamesha clear rehta hai).

resource "aws_ecr_repository" "this" {
  for_each             = toset(var.repositories)
  name                 = "${var.prefix}/${each.value}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = true # basic scan (free). Asli gate CI mein Trivy hai.
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Sirf last N images rakho, untagged 1 din mein delete (cosign .sig/.att tags bhi isi repo mein aate hain)
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Untagged images 1 din baad hatao"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Last ${var.keep_images} images rakho"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.keep_images
        }
        action = { type = "expire" }
      }
    ]
  })
}
