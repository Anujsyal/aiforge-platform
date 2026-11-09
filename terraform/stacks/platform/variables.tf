variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "cluster_name" {
  type    = string
  default = "aiforge"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "interface_endpoints" {
  description = "Paid interface endpoints. Kharcha bachana ho to [] (sab NAT se jayega)."
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr"]
}

variable "flow_log_traffic_type" {
  type    = string
  default = "REJECT"
}

variable "k3s_version" {
  type    = string
  default = "v1.37.2+k3s1"
}

variable "alb_controller_version" {
  type    = string
  default = "v3.6.2"
}

variable "server_instance_type" {
  type    = string
  default = "m7i-flex.large"
}

variable "agent_instance_type" {
  type    = string
  default = "m7i-flex.large"
}

variable "agent_count" {
  type    = number
  default = 3
}

variable "agents_use_spot" {
  type    = bool
  default = false
}

variable "github_repo" {
  description = "owner/repo (GitHub OIDC trust ke liye)"
  type        = string
}

# GitHub OIDC sub claim ab IDs ke saath aata hai: repo:<owner>@<owner_id>/<repo>@<repo_id>:ref:...
# Nikalne ka tareeka:  curl -s https://api.github.com/repos/<owner>/<repo> | grep -m2 '"id"'  (pehla = repo, owner.id = owner)
variable "github_owner_id" {
  type    = string
  default = ""
}

variable "github_repo_id" {
  type    = string
  default = ""
}

variable "create_github_oidc_provider" {
  type    = bool
  default = true
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
