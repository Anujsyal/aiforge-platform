variable "name" {
  type = string
}

variable "alert_emails" {
  type = list(string)
}

variable "account_monthly_limit_usd" {
  type    = number
  default = 60
}

variable "project_monthly_limit_usd" {
  type    = number
  default = 40
}

variable "project_tag_value" {
  type    = string
  default = "aiforge"
}
