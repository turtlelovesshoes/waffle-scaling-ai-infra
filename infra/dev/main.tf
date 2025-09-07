terraform {
  backend "s3" {}
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.9"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

##################################
### Random / Local Example Resources
##################################

resource "random_pet" "name" { length = 2 }

resource "local_file" "demo" {
  filename = "demo-output.txt"
  content  = "hello from ${random_pet.name.id}"
}

output "demo_message" {
  value = local_file.demo.content
}

##################################
### EKS Cluster IAM Roles
##################################

# Cluster Role
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role-ai-dev"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Principal = { Service = "eks.amazonaws.com" }
      Effect    = "Allow"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Node Group Role
resource "aws_iam_role" "eks_node_role" {
  name = "eks-node-role-ai-dev"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
      Effect    = "Allow"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ECR_ReadOnly" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

##################################
### VPC
##################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name                 = "eks-ai-dev-vpc"
  cidr                 = "10.0.0.0/16"
  azs                  = ["us-west-2a", "us-west-2b", "us-west-2c"]
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Environment = "dev" }
}

##################################
### EKS Cluster
##################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "ai-demo"
  cluster_version = "1.32"
  subnet_ids      = module.vpc.private_subnets
  vpc_id          = module.vpc.vpc_id
  cluster_endpoint_public_access      = true
  enable_cluster_creator_admin_permissions = true

  tags = { Environment = "dev" }

  eks_managed_node_groups = {
    dev_nodes = {
      desired_size   = 2
      min_size       = 1
      max_size       = 3
      instance_types = ["t3.large"]
      capacity_type  = "SPOT"
      iam_role_arn   = aws_iam_role.eks_node_role.arn
      tags = { Environment = "dev" }
    }
  }

  cluster_addons = {
    coredns   = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true }
  }

  access_entries = {
    example = {
      kubernetes_groups = []
      principal_arn     = aws_iam_role.eks_node_role.arn

      policy_associations = {
        example = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
          access_scope = {
            namespaces = ["default", "aidemo", "argocd"]
            type       = "namespace"
          }
        }
      }
    }
  }
}

output "cluster_name" { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "cluster_certificate_authority_data" { value = module.eks.cluster_certificate_authority_data }

##################################
### Kubernetes & Helm Providers
##################################

data "aws_eks_cluster" "main" { name = module.eks.cluster_name }
data "aws_eks_cluster_auth" "main" { name = module.eks.cluster_name }

provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

##################################
### Kubernetes Namespaces
##################################

resource "kubernetes_namespace" "aws_lb_controller" {
  metadata { name = "aws-load-balancer-controller" }
  depends_on = [module.eks]
}

resource "kubernetes_namespace" "argocd" {
  metadata { name = "argocd" }
  depends_on = [module.eks]
}

##################################
### Helm Releases
##################################

resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = kubernetes_namespace.aws_lb_controller.metadata[0].name
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.10.3"
  depends_on = [module.eks, kubernetes_namespace.aws_lb_controller]
}

data "aws_acm_certificate" "argocd" {
  domain      = "argocd.designcodemonkey.space"
  statuses    = ["ISSUED"]
  most_recent = true
}

resource "aws_acm_certificate_validation" "argocd" {
  certificate_arn         = data.aws_acm_certificate.argocd.arn
  validation_record_fqdns = ["argocd.designcodemonkey.space"]
}

data "aws_secretsmanager_secret_version" "github_oauth" {
  secret_id = "github_oauth"
}

locals { github_oauth = jsondecode(data.aws_secretsmanager_secret_version.github_oauth.secret_string) }

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = kubernetes_namespace.argocd.metadata[0].name
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "8.3.1"
  create_namespace = false
  wait             = true
  cleanup_on_fail  = true
  depends_on       = [module.eks, kubernetes_namespace.argocd]

  values = [
    yamlencode({
      server = {
        ingress = {
          enabled          = true
          ingressClassName = "alb"
          hosts            = ["argocd.designcodemonkey.space"]
          paths            = ["/"]
          pathType         = "Prefix"
          https = { enabled = true, servicePort = 443 }
          annotations = {
            "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
            "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTPS\":443}]"
            "alb.ingress.kubernetes.io/certificate-arn" = data.aws_acm_certificate.argocd.arn
            "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
            "alb.ingress.kubernetes.io/target-type"     = "ip"
            "alb.ingress.kubernetes.io/group.name"      = "argocd-alb-target-group"
            "kubernetes.io/ingress.class"               = "alb"
          }
        }
      }
      dex = {
        connectors = [{
          type   = "github"
          id     = "github"
          name   = "GitHub"
          config = {
            clientID     = local.github_oauth.github_oauth_client_id
            clientSecret = local.github_oauth.github_oauth_client_secret
            orgs         = [{ name = "turtlelovesshoes" }]
          }
        }]
      }
      rbac = { policyCSV = "g, turtlelovesshoes, role:admin" }
      repoServer = {
        defaultRepos = [{
          url    = "https://github.com/turtlelovesshoes/waffle-scaling-ai-infra.git"
          path   = "k8s/"
          branch = "main"
        }]
      }
    })
  ]
}
## missing ##
# 1. ACM Certificate for your domain
resource "aws_acm_certificate" "argocd_cert" {
  domain_name       = "argocd.designcodemonkey.space"
  validation_method = "DNS"

  tags = {
    Name = "argocd-cert"
  }
}

# 2. Route 53 Zone (existing)
data "aws_route53_zone" "main" {
  name         = "designcodemonkey.space."
  private_zone = false
}

# 3. Route 53 DNS Record for Certificate Validation
resource "aws_route53_record" "argocd_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.argocd_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.record]
}

# 4. Validate ACM Certificate
resource "aws_acm_certificate_validation" "argocd_cert_validation" {
  certificate_arn         = aws_acm_certificate.argocd_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.argocd_cert_validation : record.fqdn]
}

# 5. IAM Role for ArgoCD Controller
resource "aws_iam_role" "argocd_controller_role" {
  name = "argocd-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"  # EKS service account if using IRSA
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# 6. IAM Policy for Controller
resource "aws_iam_policy" "argocd_controller_policy" {
  name        = "argocd-controller-policy"
  description = "Policy for ArgoCD to manage ACM & Route53 DNS validation"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "acm:DescribeCertificate",
          "acm:ListCertificates",
          "acm:GetCertificate",
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets",
          "route53:GetHostedZone"
        ]
        Resource = "*"
      }
    ]
  })
}

# 7. Attach IAM Policy to Role
resource "aws_iam_role_policy_attachment" "argocd_attach" {
  role       = aws_iam_role.argocd_controller_role.name
  policy_arn = aws_iam_policy.argocd_controller_policy.arn
}
