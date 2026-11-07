variable "name" {
  type = string
}

variable "github_repo" {
  description = "owner/repo, jaise anujsyal/aiforge-platform"
  type        = string
}

variable "ecr_repository_arns" {
  type = list(string)
}

variable "create_oidc_provider" {
  description = "Account mein GitHub OIDC provider pehle se hai (kisi aur project se) to false"
  type        = bool
  default     = true
}
