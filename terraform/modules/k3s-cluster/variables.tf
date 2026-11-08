variable "name" {
  description = "Cluster naam (tags + SSM paths). VPC module ke cluster_name se match hona chahiye."
  type        = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "server_subnet_id" {
  type = string
}

variable "server_subnet_cidr" {
  description = "Server ka fixed private IP isi CIDR ka .10 hoga"
  type        = string
}

variable "agent_subnet_ids" {
  type = list(string)
}

variable "k3s_version" {
  description = "https://github.com/k3s-io/k3s/releases se stable version"
  type        = string
  default     = "v1.37.2+k3s1"
}

variable "alb_controller_version" {
  description = "IAM policy isi tag se download hoti hai. Helm chart ka appVersion isse match kar."
  type        = string
  default     = "v3.6.2"
}

variable "server_instance_type" {
  type    = string
  default = "m7i-flex.large" # 2 vCPU / 8 GB, Free plan eligible (paid account: t3.large)
}

variable "agent_instance_type" {
  type    = string
  default = "m7i-flex.large" # 2 vCPU / 8 GB, Free plan eligible (paid account: t3.xlarge)
}

variable "agent_count" {
  type    = number
  default = 3
}

variable "agents_use_spot" {
  description = "Agents spot pe (~60-70% sasta, par kabhi bhi band ho sakte hain)"
  type        = bool
  default     = false
}

variable "server_disk_gb" {
  type    = number
  default = 40
}

variable "agent_disk_gb" {
  type    = number
  default = 60 # models + images + local-path PVCs
}

variable "ecr_credential_provider_version" {
  description = "kubernetes/cloud-provider-aws ka ecr-credential-provider (k8s minor se match). k3s pe ECR pull ke liye zaruri."
  type        = string
  default     = "v1.37.0"
}
