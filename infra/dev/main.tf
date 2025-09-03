terraform {
  backend "s3" {}
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
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

resource "random_pet" "name" {
  length = 2
}

resource "local_file" "demo" {
  filename = "demo-output.txt"
  content  = "hello from ${random_pet.name.id}"
}

output "demo_message" {
  value = local_file.demo.content
}

######################
### VPC
######################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "eks-ai-dev-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Environment = "dev"
  }
}

######################
### EKS Cluster
######################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "ai-demo"
  cluster_version = "1.32"
  
  subnet_ids = module.vpc.private_subnets
  vpc_id     = module.vpc.vpc_id

  cluster_addons = {
    coredns = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni = { most_recent = true }
    metrics-server = { most_recent = true }
  }

  eks_managed_node_groups = {
    dev_nodes = {
      desired_size = 2
      min_size     = 1
      max_size     = 3
      instance_types = ["t3.large"]
      capacity_type  = "SPOT"
      iam_role_arn   = aws_iam_role.eks_node_role.arn
      tags = { Environment = "dev" }
    }
  }

  node_security_group_additional_rules = {
    node_to_node_ig = {
      description = "Node to node ingress"
      from_port   = 1
      to_port     = 65535
      protocol    = "all"
      self        = true
      type        = "ingress"
    }
  }

  tags = {
    Environment = "dev"
  }
}

######################
### Providers (Top-Level)
######################
data "aws_eks_cluster_auth" "eks" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  alias                  = "eks"
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.eks.token
}

provider "helm" {
  alias = "eks"
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.eks.token
  }
}

######################
### ArgoCD Helm Deployment
######################
resource "kubernetes_namespace" "argocd" {
  metadata { name = "argocd" }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "8.3.1"
  create_namespace = false
  providers = { helm = helm.eks }

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
            "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
            "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTPS\":443}]"
            "alb.ingress.kubernetes.io/certificate-arn" = "arn:aws:acm:us-west-2:391767403730:certificate/your-cert-arn"
            "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
            "alb.ingress.kubernetes.io/target-type"     = "ip"
            "alb.ingress.kubernetes.io/group.name"      = "argocd-alb-target-group"
            "kubernetes.io/ingress.class"               = "alb"
          }
        }
      }
      dex = {
        connectors = [
          {
            type = "github"
            id   = "github"
            name = "GitHub"
            config = {
              clientID     = "Iv23li8fHaEMkjZoeqY"
              clientSecret = "70a4b7f1adf29d7065376030455edbdd5cf573c8"
              orgs = [{ name = "turtlelovesshoes" }]
            }
          }
        ]
      }
      rbac = { policyCSV = "g, turtlelovesshoes, role:admin" }
      repoServer = {
        defaultRepos = [
          { url = "https://github.com/turtlelovesshoes/waffle-scaling-ai-infra.git", path = "k8s/", branch = "main" }
        ]
      }
    })
  ]

  wait            = true
  cleanup_on_fail = true
}
