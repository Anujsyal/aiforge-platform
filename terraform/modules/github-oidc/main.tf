# GitHub Actions → AWS bina long-lived access keys ke (OIDC federation).
# Workflow ek short-lived JWT leta hai, AWS STS usko verify karke 1 ghante ka role session deta hai.
# Trust policy sirf IS repo ki main branch (aur PRs plan ke liye nahi) ko allow karti hai.

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS ab GitHub ke liye thumbprint khud verify karta hai; field ab bhi accepted hai
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  # GitHub ab sub claim mein owner/repo ke numeric IDs bhi bhejta hai (asli run, 2026-11-09, CloudTrail se pakda):
  #   repo:Anujsyal@86842727/aiforge-platform@1449398889:ref:refs/heads/main
  # Fayda: repo delete karke same naam se naya banaya ("repo resurrection") to uske IDs alag honge → role nahi milega.
  # IDs diye hain to sirf naya format, warna purana (naam wala) format.
  owner = split("/", var.github_repo)[0]
  repo  = split("/", var.github_repo)[1]
  main_sub = var.github_owner_id != "" && var.github_repo_id != "" ? (
    "repo:${local.owner}@${var.github_owner_id}/${local.repo}@${var.github_repo_id}:ref:refs/heads/main"
  ) : "repo:${var.github_repo}:ref:refs/heads/main"

  oidc_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Sirf main branch push kar sakti hai. Fork ya feature branch se ECR push nahi.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.main_sub]
    }
  }
}

resource "aws_iam_role" "ci" {
  name                 = "${var.name}-github-ci"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "EcrPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:DescribeImages",
      "ecr:ListImages",
    ]
    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ecr_push.json
}
