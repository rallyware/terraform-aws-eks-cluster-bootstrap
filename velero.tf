locals {
  velero_enabled = module.this.enabled && contains(var.apps_to_install, "velero")
  velero_helm_default_params = {
    repository      = "https://vmware-tanzu.github.io/helm-charts"
    chart           = "velero"
    version         = "2.23.6"
    override_values = ""
  }
  velero_helm_default_values = {
    "fullnameOverride" = "${local.velero["name"]}"
    "serviceAccount" = {
      "annotations" = {
        "eks.amazonaws.com/role-arn"               = module.velero_eks_iam_role.service_account_role_arn
        "eks.amazonaws.com/sts-regional-endpoints" = tostring(var.sts_regional_endpoints_enabled)
      }
    }
    "configuration" = {
      "backupStorageLocation" = {
        "bucket"   = module.velero_s3_bucket.bucket_id
        "name"     = "default"
        "prefix"   = format("backups/%s", local.eks_cluster_id)
        "provider" = "aws"
        "region"   = local.region
      }
      "provider" = "aws"
      "volumeSnapshotLocation" = {
        "name"     = "default"
        "provider" = "aws"
        "region"   = local.region
      }
    }
    "initContainers" = [
      {
        "image"           = "velero/velero-plugin-for-aws:v1.2.1"
        "imagePullPolicy" = "IfNotPresent"
        "name"            = "velero-plugin-for-aws"
        "volumeMounts" = [
          {
            "mountPath" = "/target"
            "name"      = "plugins"
          },
        ]
      },
    ]
    "metrics" = {
      "enabled"        = true
      "scrapeInterval" = "30s"
      "scrapeTimeout"  = "10s"
      "serviceMonitor" = {
        "enabled" = true
      }
    }
    "resources" = {
      "limits" = {
        "cpu"    = "1000m"
        "memory" = "512Mi"
      }
      "requests" = {
        "cpu"    = "500m"
        "memory" = "128Mi"
      }
    }
  }
  velero = defaults(var.velero, merge(local.helm_default_params, local.velero_helm_default_params))
}

module "velero_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  enabled = local.velero_enabled
  context = module.this.context
}

module "velero_s3_bucket" {
  source  = "cloudposse/s3-bucket/aws"
  version = "0.46.0"

  acl                = "private"
  user_enabled       = false
  versioning_enabled = false

  lifecycle_rules = [
    {
      enabled = false
      prefix  = ""
      tags    = {}

      enable_glacier_transition            = false
      enable_deeparchive_transition        = false
      enable_standard_ia_transition        = false
      enable_current_object_expiration     = false
      enable_noncurrent_version_expiration = false

      abort_incomplete_multipart_upload_days         = 90
      noncurrent_version_glacier_transition_days     = 30
      noncurrent_version_deeparchive_transition_days = 60
      noncurrent_version_expiration_days             = 90

      standard_transition_days    = 30
      glacier_transition_days     = 60
      deeparchive_transition_days = 90
      expiration_days             = 90
    }
  ]

  context    = module.velero_label.context
  attributes = [local.velero["name"]]
}

data "aws_iam_policy_document" "velero" {
  count = local.velero_enabled ? 1 : 0

  statement {
    effect = "Allow"

    resources = [
      format("%s/*", module.velero_s3_bucket.bucket_arn),
      module.velero_s3_bucket.bucket_arn
    ]

    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts"
    ]
  }

  # statement {
  #   effect = "Allow"

  #   resources = [
  #     module.ebs_csi_driver_kms_key.key_arn
  #   ]

  #   actions = [
  #     "kms:Encrypt",
  #     "kms:Decrypt",
  #     "kms:ReEncrypt*",
  #     "kms:GenerateDataKey*",
  #     "kms:DescribeKey",
  #   ]
  # }

  statement {
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "ec2:DescribeVolumes",
      "ec2:DescribeSnapshots",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:CreateSnapshot",
      "ec2:DeleteSnapshot"
    ]
  }
}

module "velero_eks_iam_role" {
  source  = "rallyware/eks-iam-role/aws"
  version = "0.1.1"

  aws_iam_policy_document     = one(data.aws_iam_policy_document.velero[*].json)
  eks_cluster_oidc_issuer_url = local.eks_cluster_oidc_issuer_url
  service_account_name        = local.velero["name"]
  service_account_namespace   = local.velero["namespace"]

  context = module.velero_label.context
}

data "utils_deep_merge_yaml" "velero" {
  count = local.velero_enabled ? 1 : 0

  input = [
    yamlencode(local.velero_helm_default_values),
    local.velero["override_values"]
  ]
}

resource "helm_release" "velero" {
  count = local.velero_enabled ? 1 : 0

  name              = local.velero["name"]
  repository        = local.velero["repository"]
  chart             = local.velero["chart"]
  version           = local.velero["version"]
  namespace         = local.velero["namespace"]
  max_history       = local.velero["max_history"]
  create_namespace  = local.velero["create_namespace"]
  dependency_update = local.velero["dependency_update"]
  reuse_values      = local.velero["reuse_values"]
  wait              = local.velero["wait"]
  timeout           = local.velero["timeout"]
  values            = [one(data.utils_deep_merge_yaml.velero[*].output)]

  depends_on = [
    helm_release.calico,
    helm_release.node_local_dns,
    helm_release.kube_prometheus_stack,
    helm_release.cluster_autoscaler
  ]
}
