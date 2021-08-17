locals {
  cluster_autoscaler_enabled = module.this.enabled && contains(var.apps_to_install, "cluster_autoscaler")
}

module "cluster_autoscaler_label" {
  source  = "cloudposse/label/null"
  version = "0.24.1"

  enabled    = local.cluster_autoscaler_enabled
  attributes = ["cluster", "autoscaler"]
  context    = module.this.context
}

module "cluster_autoscaler_eks_iam_policy" {
  source  = "cloudposse/iam-policy/aws"
  version = "0.1.0"

  iam_policy_statements = [
    {
      sid    = "ClusterAutoscaler"
      effect = "Allow"
      actions = [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeTags",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "ec2:DescribeLaunchTemplateVersions"
      ]
      resources = ["*"]
    }
  ]

  context = module.cluster_autoscaler_label.context
}

module "cluster_autoscaler_eks_iam_role" {
  source  = "cloudposse/eks-iam-role/aws"
  version = "0.10.0"

  aws_iam_policy_document     = module.cluster_autoscaler_eks_iam_policy.json
  aws_partition               = one(data.aws_partition.default[*].partition)
  eks_cluster_oidc_issuer_url = one(data.aws_eks_cluster.default[*].identity[0].oidc[0].issuer)
  service_account_name        = var.cluster_autoscaler["name"]
  service_account_namespace   = var.cluster_autoscaler["namespace"]

  context = module.cluster_autoscaler_label.context
}

resource "helm_release" "cluster_autoscaler" {
  count = local.cluster_autoscaler_enabled ? 1 : 0

  name              = var.cluster_autoscaler["name"]
  repository        = var.cluster_autoscaler["repository"]
  chart             = var.cluster_autoscaler["chart"]
  version           = var.cluster_autoscaler["version"]
  namespace         = var.cluster_autoscaler["namespace"]
  max_history       = var.cluster_autoscaler["max_history"]
  create_namespace  = var.cluster_autoscaler["create_namespace"]
  dependency_update = var.cluster_autoscaler["dependency_update"]
  values            = var.cluster_autoscaler["values"]

  set {
    name  = "fullnameOverride"
    value = var.cluster_autoscaler["name"]
  }

  set {
    name  = "cloudProvider"
    value = "aws"
  }

  set {
    name  = "awsRegion"
    value = one(data.aws_region.default[*].name)
  }

  set {
    name  = "autoDiscovery.clusterName"
    value = one(data.aws_eks_cluster.default[*].id)
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.cluster_autoscaler_eks_iam_role.service_account_role_arn
  }

  depends_on = [
    helm_release.kube_prometheus_stack,
    helm_release.node_local_dns,
    module.cluster_autoscaler_eks_iam_role
  ]
}
