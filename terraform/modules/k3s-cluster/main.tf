# k3s cluster on EC2 (EKS ka sasta option).
# - 1 server (control plane + kuch workloads) + N agents, sab PRIVATE subnets mein
# - Koi SSH key nahi, koi port 22 nahi: access sirf SSM Session Manager se
# - k3s join token SSM Parameter Store (SecureString) mein; kubeconfig bhi wahin upload hota hai
# - Nodes ka providerID aws:///<az>/<instance-id> set hota hai, taaki AWS Load Balancer
#   Controller (instance target mode) aur OpenCost nodes ko EC2 instances se map kar saken

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    random = {
      source = "hashicorp/random"
    }
    http = {
      source = "hashicorp/http"
    }
  }
}

data "aws_caller_identity" "current" {}

# Ubuntu 24.04 LTS (Canonical ka official owner ID)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  token_param      = "/${var.name}/k3s/token"
  kubeconfig_param = "/${var.name}/k3s/kubeconfig"
  server_ip        = cidrhost(var.server_subnet_cidr, 10) # fixed IP: agents ko pehle se pata ho
}

# ---------------- Join token ----------------
resource "random_password" "k3s_token" {
  length  = 48
  special = false
}

resource "aws_ssm_parameter" "token" {
  name  = local.token_param
  type  = "SecureString"
  value = random_password.k3s_token.result
}

# ---------------- Security group ----------------
resource "aws_security_group" "nodes" {
  name        = "${var.name}-k3s-nodes"
  description = "k3s nodes: sirf apas mein baat. Koi SSH nahi."
  vpc_id      = var.vpc_id

  # Ye tag zaruri hai: ALB controller isi SG mein NodePort ke rules khud add karta hai.
  # Ek ENI pe sirf EK SG pe ye tag hona chahiye, warna controller confuse hota hai.
  tags = {
    Name                                = "${var.name}-k3s-nodes"
    "kubernetes.io/cluster/${var.name}" = "owned"
  }
}

resource "aws_vpc_security_group_ingress_rule" "self" {
  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "-1"
  description                  = "Node to node (k3s API 6443, kubelet 10250, flannel VXLAN 8472, NodePorts)"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.nodes.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Egress via NAT (packages, images, models). Pod-level egress NetworkPolicy se control hota hai."
}

# ---------------- IAM (instance profile) ----------------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "nodes" {
  name               = "${var.name}-k3s-node"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

data "aws_iam_policy_document" "k3s_params" {
  statement {
    sid       = "ReadJoinToken"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${local.token_param}"]
  }
  statement {
    sid       = "UploadKubeconfig"
    actions   = ["ssm:PutParameter"]
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${local.kubeconfig_param}"]
  }
}

resource "aws_iam_role_policy" "k3s_params" {
  name   = "k3s-ssm-parameters"
  role   = aws_iam_role.nodes.id
  policy = data.aws_iam_policy_document.k3s_params.json
}

# AWS Load Balancer Controller ki official IAM policy, controller ke version ke saath pinned.
# EKS pe ye IRSA/Pod Identity se sirf controller pod ko milti; k3s pe IRSA nahi hai,
# isliye node role pe hai (trade-off: guide ke "Problems faced" mein likha hai).
data "http" "alb_controller_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${var.alb_controller_version}/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "alb_controller" {
  name   = "${var.name}-alb-controller"
  policy = data.http.alb_controller_policy.response_body
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.nodes.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

resource "aws_iam_instance_profile" "nodes" {
  name = "${var.name}-k3s-node"
  role = aws_iam_role.nodes.name
}

# ---------------- Server ----------------
resource "aws_instance" "server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.server_instance_type
  subnet_id              = var.server_subnet_id
  private_ip             = local.server_ip
  vpc_security_group_ids = [aws_security_group.nodes.id]
  iam_instance_profile   = aws_iam_instance_profile.nodes.name

  user_data = templatefile("${path.module}/templates/server.sh.tpl", {
    region           = var.region
    k3s_version      = var.k3s_version
    token_param      = local.token_param
    kubeconfig_param = local.kubeconfig_param
  })
  user_data_replace_on_change = true

  # IMDSv2 required. hop limit 2: pods (ek network hop aage) bhi IMDS tak pahunch saken
  # (ALB controller, Kyverno ECR verification). 1 rakha to pods ko "no EC2 IMDS role found" aata hai.
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = var.server_disk_gb
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name                                = "${var.name}-k3s-server"
    Role                                = "k3s-server"
    "kubernetes.io/cluster/${var.name}" = "owned"
  }

  depends_on = [aws_ssm_parameter.token, aws_iam_role_policy.k3s_params]
}

# ---------------- Agents ----------------
resource "aws_instance" "agent" {
  count                  = var.agent_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.agent_instance_type
  subnet_id              = var.agent_subnet_ids[count.index % length(var.agent_subnet_ids)]
  vpc_security_group_ids = [aws_security_group.nodes.id]
  iam_instance_profile   = aws_iam_instance_profile.nodes.name

  user_data = templatefile("${path.module}/templates/agent.sh.tpl", {
    region      = var.region
    k3s_version = var.k3s_version
    token_param = local.token_param
    server_ip   = local.server_ip
    node_pool   = count.index == 0 ? "ai" : "general" # pehla agent Ollama ke liye
  })
  user_data_replace_on_change = true

  dynamic "instance_market_options" {
    for_each = var.agents_use_spot ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        spot_instance_type             = "one-time"
        instance_interruption_behavior = "terminate"
      }
    }
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = var.agent_disk_gb
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name                                = "${var.name}-k3s-agent-${count.index}"
    Role                                = "k3s-agent"
    "kubernetes.io/cluster/${var.name}" = "owned"
  }

  depends_on = [aws_instance.server]
}
