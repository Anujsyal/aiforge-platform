# AWS Budgets + SNS alerts (Project 1 FinOps showback wala logic yahan reuse).
# 2 budgets:
#   1. Account-wide monthly budget (safety net: kuch bhi bhool gaye to email)
#   2. Sirf "Project=aiforge" tag wale resources ka budget (showback)
# Note: tag-based budget tabhi kaam karta hai jab Billing console mein "Project" cost
# allocation tag ACTIVATE ho (Project 1 ka lesson: activate karne ke ~24h baad data aata hai).

data "aws_caller_identity" "current" {}

resource "aws_sns_topic" "budget" {
  name = "${var.name}-budget-alerts"
}

data "aws_iam_policy_document" "sns_budgets" {
  statement {
    sid       = "AllowBudgetsPublish"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.budget.arn]
    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "budget" {
  arn    = aws_sns_topic.budget.arn
  policy = data.aws_iam_policy_document.sns_budgets.json
}

# Email subscription: AWS confirm email bhejega, link click karna zaruri hai
resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.alert_emails)
  topic_arn = aws_sns_topic.budget.arn
  protocol  = "email"
  endpoint  = each.value
}

locals {
  thresholds = [
    { pct = 50, type = "ACTUAL" },
    { pct = 80, type = "ACTUAL" },
    { pct = 100, type = "ACTUAL" },
    { pct = 100, type = "FORECASTED" }, # mahine ke end tak cross hone wala hai = pehle hi warning
  ]
}

resource "aws_budgets_budget" "account" {
  name         = "${var.name}-account-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.account_monthly_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = local.thresholds
    content {
      comparison_operator       = "GREATER_THAN"
      threshold                 = notification.value.pct
      threshold_type            = "PERCENTAGE"
      notification_type         = notification.value.type
      subscriber_sns_topic_arns = [aws_sns_topic.budget.arn]
    }
  }

  depends_on = [aws_sns_topic_policy.budget]
}

resource "aws_budgets_budget" "project" {
  name         = "${var.name}-project-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.project_monthly_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name = "TagKeyValue"
    # Format: user:<TagKey>$<TagValue>  (beech mein literal $)
    values = [join("$", ["user:Project", var.project_tag_value])]
  }

  dynamic "notification" {
    for_each = local.thresholds
    content {
      comparison_operator       = "GREATER_THAN"
      threshold                 = notification.value.pct
      threshold_type            = "PERCENTAGE"
      notification_type         = notification.value.type
      subscriber_sns_topic_arns = [aws_sns_topic.budget.arn]
    }
  }

  depends_on = [aws_sns_topic_policy.budget]
}
