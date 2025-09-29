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
      version = "~> 2.16"
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

  public_subnet_tags = {
    "kubernetes.io/role/elb"        = "1"
    "kubernetes.io/cluster/ai-demo" = "owned"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/ai-demo"   = "owned"
  }
}

##################################
### EKS Cluster
##################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name                             = "ai-demo"
  cluster_version                          = "1.32"
  subnet_ids                               = module.vpc.private_subnets
  vpc_id                                   = module.vpc.vpc_id
  cluster_endpoint_public_access           = true
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
      tags           = { Environment = "dev" }
    }
  }

  cluster_addons = {
    coredns    = { most_recent = true }
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
  metadata {
    name = "aws-load-balancer-controller"
  }
  depends_on = [module.eks]
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
  depends_on = [module.eks]
}


#### helm for externaldns #####


##################################
### IAM Role & Policy for AWS LB Controller
##################################

# IAM Role for AWS LB Controller Service Account
resource "aws_iam_role" "aws_lb_controller_role" {
  name = "aws-lb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:aws-load-balancer-controller:aws-load-balancer-controller"
        }
      }
    }]
  })
}

# IAM Policy for AWS LB Controller
resource "aws_iam_policy" "aws_lb_controller_policy" {
  name        = "aws-lb-controller-policy"
  description = "Policy for AWS Load Balancer Controller"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "elasticloadbalancing:*",
        "ec2:Describe*",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:CreateSecurityGroup",
        "iam:CreateServiceLinkedRole",
        "cognito-idp:DescribeUserPoolClient",
        "waf-regional:GetWebACL",
        "waf-regional:GetWebACLForResource",
        "waf-regional:AssociateWebACL",
        "tag:GetResources",
        "tag:TagResources",
        "ec2:CreateTags",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeTags"
      ]
      Resource = "*"
    }]
  })
}

# Attach IAM Policy to Role
resource "aws_iam_role_policy_attachment" "aws_lb_controller_attach" {
  role       = aws_iam_role.aws_lb_controller_role.name
  policy_arn = aws_iam_policy.aws_lb_controller_policy.arn
}

##################################
### Kubernetes Service Account
##################################

resource "kubernetes_service_account" "aws_lb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = kubernetes_namespace.aws_lb_controller.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.aws_lb_controller_role.arn
    }
  }
}

##################################
### Helm Release for AWS LB Controller
##################################

resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = kubernetes_namespace.aws_lb_controller.metadata[0].name
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.11.0"
  depends_on = [module.eks, kubernetes_namespace.aws_lb_controller, kubernetes_service_account.aws_lb_controller]

  values = [yamlencode({
    clusterName = module.eks.cluster_name
    serviceAccount = {
      create = false
      name   = "aws-load-balancer-controller"
    }
  })]
}

##################################
### ACM Certificate & Validation for ArgoCD
##################################

resource "aws_acm_certificate" "argocd_cert" {
  domain_name       = "argocd.designcodemonkey.space"
  validation_method = "DNS"
}

data "aws_route53_zone" "main" {
  name         = "designcodemonkey.space."
  private_zone = false
}

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

resource "aws_acm_certificate_validation" "argocd_cert_validation" {
  certificate_arn         = aws_acm_certificate.argocd_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.argocd_cert_validation : record.fqdn]
  depends_on              = [aws_route53_record.argocd_cert_validation]
}

##################################
### Secrets for Dex
##################################

data "aws_secretsmanager_secret_version" "github_oauth" {
  secret_id = "github_oauth"
}

locals {
  github_oauth = jsondecode(data.aws_secretsmanager_secret_version.github_oauth.secret_string)
}

##################################
### ArgoCD Helm Release
##################################
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = kubernetes_namespace.argocd.metadata[0].name
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "8.3.1"
  create_namespace = false
  wait             = true
  cleanup_on_fail  = true

  depends_on = [
    module.eks,
    kubernetes_namespace.argocd,
    aws_acm_certificate_validation.argocd_cert_validation
  ]

  values = [yamlencode({
    server = {
      extraArgs = ["--insecure"]
      service = {
        type = "ClusterIP"
        ports = {
          https = 80  # Internal port backend for ingress (HTTP, ALB terminates TLS)
        }
      }
      ingress = {
        enabled          = true
        ingressClassName = "alb"
        hosts = [
          {
            host = "argocd.designcodemonkey.space"
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = "argocd-server"
                    port = { number = 80 }  # backend port changed to 80
                  }
                }
              }
            ]
          }
        ]
        annotations = {
          "alb.ingress.kubernetes.io/scheme"              = "internet-facing"
          "alb.ingress.kubernetes.io/listen-ports" = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
          "alb.ingress.kubernetes.io/certificate-arn"     = aws_acm_certificate_validation.argocd_cert_validation.certificate_arn
          "alb.ingress.kubernetes.io/ssl-redirect"        = "443"
          "alb.ingress.kubernetes.io/target-type"         = "ip"
          "alb.ingress.kubernetes.io/group.name"          = "argocd-alb-target-group"
          "alb.ingress.kubernetes.io/loadbalancer-name"   = "argocd-alb"
          "alb.ingress.kubernetes.io/healthcheck-path"    = "/healthz"          # health check path
          "kubernetes.io/ingress.class"                    = "alb"
          "external-dns.alpha.kubernetes.io/hostname" = "argocd.designcodemonkey.space"
        }
      }
    }
    dex = {
      connectors = [{
        type = "github"
        id   = "github"
        name = "GitHub"
        config = {
          clientID     = local.github_oauth.github_oauth_client_id
          clientSecret = local.github_oauth.github_oauth_client_secret
          orgs         = [{ name = "turtlelovesshoes" }]
        }
      }]
    }
    rbac = {
      policyCSV = "g, turtlelovesshoes, role:admin"
    }
    repoServer = {
      defaultRepos = [{
        url    = "https://github.com/turtlelovesshoes/waffle-scaling-ai-infra.git"
        path   = "k8s/"
        branch = "main"
      }]
    }
  })]
}



##################################
### IAM Role & Policy for ArgoCD Controller
##################################

resource "aws_iam_role" "argocd_controller_role" {
  name = "argocd-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "argocd_controller_policy" {
  name        = "argocd-controller-policy"
  description = "Policy for ArgoCD to manage ACM & Route53 DNS validation"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow"
      Action = [
        "acm:DescribeCertificate",
        "acm:ListCertificates",
        "acm:GetCertificate",
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets",
        "route53:GetHostedZone"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "argocd_attach" {
  role       = aws_iam_role.argocd_controller_role.name
  policy_arn = aws_iam_policy.argocd_controller_policy.arn
}


# Kyverno Controller
resource "helm_release" "kyverno" {
  name             = "kyverno"
  repository       = "https://kyverno.github.io/kyverno/"
  chart            = "kyverno"
  namespace        = "kyverno"
  version          = "3.1.4" # check latest version
  create_namespace = true

  values = [
    yamlencode({
      replicaCount = 2
      serviceMonitor = {
        enabled = true
      }
    })
  ]
}

# Kyverno Policies
resource "helm_release" "kyverno_policies" {
  name       = "kyverno-policies"
  repository = "https://kyverno.github.io/kyverno/"
  chart      = "kyverno-policies"
  namespace  = "kyverno"
  version    = "3.1.4" # match the kyverno release version
  depends_on = [helm_release.kyverno]

  values = [
    yamlencode({
      policies = {
        podSecurity = {
          enabled = true
        }
        requireLabels = {
          enabled = true
        }
        disallowPrivileged = {
          enabled = true
        }
      }
    })
  ]
}




resource "helm_release" "kubernetes_dashboard" {
  name             = "kubernetes-dashboard"
  repository       = "https://kubernetes.github.io/dashboard/"
  chart            = "kubernetes-dashboard"
  namespace        = "kubernetes-dashboard"
  version          = "7.3.1"
  create_namespace = true

  values = [
    yamlencode({
      enableInsecureLogin = true
      protocolHttp        = true
      service = {
        type         = "ClusterIP"
        externalPort = 80
      }
    })
  ]
}
