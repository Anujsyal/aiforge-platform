variable "name" {
  type = string
}

variable "region" {
  type = string
}

variable "cluster_name" {
  description = "Subnet tags kubernetes.io/cluster/<name> ke liye (ALB controller)"
  type        = string
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "az_count" {
  type    = number
  default = 2
  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "ALB ko kam se kam 2 AZ chahiye."
  }
}

variable "single_nat_gateway" {
  description = "true = ek hi NAT (sasta). false = har AZ ka NAT (HA)."
  type        = bool
  default     = true
}

variable "interface_endpoints" {
  description = "Interface VPC endpoints (paid). Khaali list = koi nahi."
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr"]
}

variable "flow_log_traffic_type" {
  type    = string
  default = "REJECT"
  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_log_traffic_type)
    error_message = "ACCEPT, REJECT ya ALL."
  }
}

variable "flow_log_retention_days" {
  type    = number
  default = 7
}
