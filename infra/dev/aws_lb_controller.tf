# Namespace for aws-load-balancer-controller
resource "kubernetes_namespace" "aws_lb_controller" {
  metadata {
    name = "aws-load-balancer-controller"
  }
}

# Get EKS OIDC provider
data "aws_eks_cluster" "this" {
  name = module.eks.cluster_name
}
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}
data "aws_iam_openid_connect_provider" "this" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

# IAM policy for the controller
data "aws_iam_policy_document" "aws_lb_controller_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.this.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values   = ["system:serviceaccount:aws-load-balancer-controller:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "aws_lb_controller" {
  name = "aws-lb-controller-role"

  assume_role_policy = data.aws_iam_policy_document.aws_lb_controller_assume_role.json

  tags = {
    Name = "aws-lb-controller"
    Environment = "dev"
  }
}

# Attach the AWS managed policy (or use a local json file for custom policy)
resource "aws_iam_policy" "aws_lb_controller" {
  name        = "AWSLoadBalancerControllerIAMPolicy"
  description = "Policy for AWS Load Balancer Controller"
  policy      = file("${path.module}/aws-lb-controller-policy.json")
}

resource "aws_iam_role_policy_attachment" "aws_lb_controller_attach" {
  role       = aws_iam_role.aws_lb_controller.name
  policy_arn = aws_iam_policy.aws_lb_controller.arn
}

# Service account for the controller
resource "kubernetes_service_account" "aws_lb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = kubernetes_namespace.aws_lb_controller.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.aws_lb_controller.arn
    }
    labels = {
      "app.kubernetes.io/name" = "aws-load-balancer-controller"
    }
  }
}

# Install AWS Load Balancer Controller via Helm
resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = kubernetes_namespace.aws_lb_controller.metadata[0].name
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.7.1" # Use latest stable as needed

  # Pass required values
  values = [yamlencode({
    clusterName         = module.eks.cluster_name
    serviceAccount = {
      create = false
      name   = kubernetes_service_account.aws_lb_controller.metadata[0].name
    }
    region = "us-west-2" 
    vpcId  = module.vpc.vpc_id
  })]

  depends_on = [
    kubernetes_service_account.aws_lb_controller
  ]
}