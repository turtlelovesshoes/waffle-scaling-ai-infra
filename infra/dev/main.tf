##############################
# Terraform & Providers
##############################

terraform {
  backend "s3" {}
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
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

##############################
# Demo Resources
##############################

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

##############################
# EKS Cluster IAM Roles
##############################

# Cluster IAM role
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role-ai-dev"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Principal = { Service = "eks.amazonaws.com" }
      Effect = "Allow"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Node group IAM role
resource "aws_iam_role" "eks_node_role" {
  name = "eks-node-role-ai-dev"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
      Effect = "Allow"
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

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryReadOnly" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

##############################
# VPC
##############################

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

  tags = { Environment = "dev" }
}

##############################
# EKS Cluster
##############################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "ai-demo"
  cluster_version = "1.32"
  
  subnet_ids = module.vpc.private_subnets
  vpc_id     = module.vpc.vpc_id

  cluster_endpoint_public_access              = true
  enable_cluster_creator_admin_permissions    = true
  iam_role_name                               = aws_iam_role.eks_cluster_role.name


  tags = { Environment = "dev" }

  cluster_addons = {
    coredns         = { most_recent = true }
    kube-proxy       = { most_recent = true }
    vpc-cni          = { most_recent = true }
    metrics-server   = { most_recent = true }
  }

  eks_managed_node_group_defaults = {
    instance_types = ["m6i.large", "m5.large", "m5n.large", "m5zn.large"]
  }

  eks_managed_node_groups = {
  dev_nodes = {
    min_size       = 1
    max_size       = 3
    desired_size   = 2
    instance_types = ["t3.large"]
    capacity_type  = "SPOT"
    iam_role_arn   = aws_iam_role.eks_node_role.arn
   }
  }
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

##############################
# Kubernetes & Helm Providers
##############################
data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "eks" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

##############################
# ArgoCD Helm Deployment
##############################

resource "kubernetes_namespace" "argocd" {
  metadata { name = "argocd" }
}

resource "helm_release" "argocd" {
  provider        = helm
  name            = "argocd"
  namespace       = kubernetes_namespace.argocd.metadata[0].name
  repository      = "https://argoproj.github.io/argo-helm"
  chart           = "argo-cd"
  version         = "8.3.1"
  create_namespace = false

  values = [yamlencode({
    server = {
      ingress = {
        enabled          = true
        ingressClassName = "alb"
        hosts            = ["argocd.designcodemonkey.io"]
        paths            = ["/"]
        pathType         = "Prefix"
        https = { enabled = true, servicePort = 443 }
        annotations = {
          "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
          "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTPS\":443}]"
          "alb.ingress.kubernetes.io/certificate-arn" = "arn:aws:acm:us-west-2:391767403730:certificate/f070bd2e-43a6-425e-bf33-b24e36647e42"
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
          clientID     = "Iv23li8fHaEMkjZoeqY"
          clientSecret = "70a4b7f1adf29d7065376030455edbdd5cf573c8"
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
  })]

  wait            = true
  cleanup_on_fail = true
  depends_on = [module.eks]
}
