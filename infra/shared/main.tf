terraform {
  backend "s3" {}
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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
#### EKS CLUSTER ###
provider "aws" {
  region = "us-west-2"
}

# EKS cluster IAM role
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role-ai-dev"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Principal = {
        Service = "eks.amazonaws.com"
      }
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
      Principal = {
        Service = "ec2.amazonaws.com"
      }
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

# VPC + Subnets
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
    Give = "Get"
  }
}

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "ai-demo"
  cluster_version = "1.32"
  
  subnet_ids = module.vpc.private_subnets
  vpc_id     = module.vpc.vpc_id

  tags = {
    Environment = "dev"
  }
  cluster_endpoint_public_access  = true
  enable_cluster_creator_admin_permissions = true

  access_entries = {
    # One access entry with a policy associated
    example = {
      kubernetes_groups = []
      principal_arn     = aws_iam_role.eks_node_role.arn

      policy_associations = {
        example = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
          access_scope = {
            namespaces = ["default", "aidemo"]
            type       = "namespace"
          }
        }
      }
    }
  }

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }
    # EKS Managed Node Group(s)
  eks_managed_node_group_defaults = {
    instance_types = ["m6i.large", "m5.large", "m5n.large", "m5zn.large"]
  }

  eks_managed_node_groups = {
    dev_nodes = {
      min_size     = 1
      max_size     = 3
      desired_size = 2

      instance_types = ["t3.large"]

      capacity_type = "SPOT"

      iam_role_arn = aws_iam_role.eks_node_role.arn

      tags = {
        Environment = "dev"
      }
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

### route53 ###
# Fetch your existing VPC
data "aws_vpc" "eks_vpc" {
  id = module.vpc.vpc_id  # Replace with your cluster VPC
}

# Fetch the hosted zone (private)
data "aws_route53_zone" "private_zone" {
  name         = "designcodemonkey.space"  # Replace with your domain
  private_zone = true
}

resource "aws_route53_vpc_association_authorization" "auth" {
  vpc_id        = data.aws_vpc.eks_vpc.id
  zone_id       = data.aws_route53_zone.private_zone.id
}

resource "aws_route53_zone_association" "assoc" {
  zone_id = data.aws_route53_zone.private_zone.id
  vpc_id  = data.aws_vpc.eks_vpc.id
}
# Associate the private zone
resource "aws_route53_zone_association" "eks_private_zone" {
  zone_id = data.aws_route53_zone.private_zone.id
  vpc_id  = module.eks.vpc_id
}
## we need to deploy our  application called portfolio

#Ecr build repository
provider "aws" {
  region = "us-west-2"
}

resource "aws_ecr_repository" "portfolio" {
  name = "portfolio"
  image_scanning_configuration {
    scan_on_push = true
  }
}


#route53 entry
#helm chart refernece
provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

data "aws_eks_cluster" "main" {
  name = "ai-demo"
}

data "aws_eks_cluster_auth" "main" {
  name = data.aws_eks_cluster.main.name
}

resource "helm_release" "portfolio" {
  name       = "portfolio"
  namespace  = "portfolio"
  repository = "https://raw.githubusercontent.com/turtlelovesshoes/waffle-scaling-ai-infra/main/k8s/portfolio-hlem"
  chart      = "portfolio"
  version    = "0.1.0"

  set {
    name  = "image.repository"
    value = "391767403730.dkr.ecr.us-west-2.amazonaws.com/portfolio"
  }

  set {
    name  = "image.tag"
    value = "rachelm-deploysite-48544db4eefbf6df03bd831743a041c318cb59fd" # <- this comes from CI/CD (Spacelift sets it)
  }
}
