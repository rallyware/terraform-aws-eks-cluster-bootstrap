locals {
  helm_default_params = {
    max_history       = 10
    create_namespace  = true
    dependency_update = true
    reuse_values      = false
    timeout           = 300
  }
  eks_cluster_id              = one(data.aws_eks_cluster.default[*].id)
  eks_cluster_oidc_issuer_url = one(data.aws_eks_cluster.default[*].identity[0].oidc[0].issuer)
  region                      = one(data.aws_region.default[*].name)
  partition                   = one(data.aws_partition.default[*].partition)
  account_id                  = one(data.aws_caller_identity.default[*].account_id)
  currnet_time_rfc3339        = one(time_static.default[*].rfc3339)

  default_depends_on = [
    helm_release.calico,
    helm_release.kube_prometheus_stack,
    helm_release.node_local_dns,
    helm_release.ebs_csi_driver,
    helm_release.cluster_autoscaler,
    helm_release.ingress_nginx,
    kubectl_manifest.prometheus_operator_crds
  ]
}

data "aws_partition" "default" {
  count = module.this.enabled ? 1 : 0
}

data "aws_eks_cluster" "default" {
  count = module.this.enabled ? 1 : 0

  name = var.eks_cluster_id
}

data "aws_region" "default" {
  count = module.this.enabled ? 1 : 0
}

data "aws_caller_identity" "default" {
  count = module.this.enabled ? 1 : 0
}

resource "time_static" "default" {
  count = module.this.enabled ? 1 : 0
}
