locals {
  ebs_csi_driver_enabled = module.this.enabled && contains(var.apps_to_install, "ebs_csi_driver")
  ebs_csi_driver         = defaults(var.ebs_csi_driver, local.helm_default_params)
  ebs_csi_driver_values  = length(local.ebs_csi_driver["values"]) > 0 ? local.ebs_csi_driver["values"] : [yamlencode(local.ebs_csi_driver_default_values)]
  ebs_csi_driver_default_values = {
    "controller" = {
      "extraCreateMetadata" = true
      "k8sTagClusterId"     = "${one(data.aws_eks_cluster.default[*].id)}"
      "region"              = "${one(data.aws_region.default[*].name)}"
      "tolerateAllTaints"   = true
      "updateStrategy" = {
        "rollingUpdate" = {
          "maxSurge"       = 0
          "maxUnavailable" = 1
        }
        "type" = "RollingUpdate"
      }
    }
    "enableVolumeResizing" = true
    "enableVolumeSnapshot" = true
    "storageClasses" = [
      {
        "allowVolumeExpansion" = true
        "annotations" = {
          "storageclass.kubernetes.io/is-default-class" = "true"
        }
        "labels" = {
          "type" = "gp3"
        }
        "name" = "ebs-gp3"
        "parameters" = {
          "csi.storage.k8s.io/fstype" = "xfs"
          "encrypted"                 = "true"
          "kmsKeyId"                  = "${module.ebs_csi_driver_kms_key.key_id}"
          "type"                      = "gp3"
        }
        "provisioner"       = "ebs.csi.aws.com"
        "reclaimPolicy"     = "Delete"
        "volumeBindingMode" = "WaitForFirstConsumer"
      },
    ]
  }
}

module "ebs_csi_driver_label" {
  source  = "cloudposse/label/null"
  version = "0.24.1"

  enabled    = local.ebs_csi_driver_enabled
  attributes = ["ebs", "csi", "driver"]
  context    = module.this.context
}

module "ebs_csi_driver_kms_key" {
  source  = "cloudposse/kms-key/aws"
  version = "0.10.0"

  description             = format("KMS key for ebs-csi-driver on %s", one(data.aws_eks_cluster.default[*].id))
  deletion_window_in_days = 10
  enable_key_rotation     = true
  alias                   = format("alias/%s/ebs-csi-driver", one(data.aws_eks_cluster.default[*].id))

  context = module.ebs_csi_driver_label.context
}

data "aws_iam_policy_document" "ebs_csi_driver" {
  count = local.ebs_csi_driver_enabled ? 1 : 0

  statement {
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "ec2:CreateSnapshot",
      "ec2:AttachVolume",
      "ec2:DetachVolume",
      "ec2:ModifyVolume",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInstances",
      "ec2:DescribeSnapshots",
      "ec2:DescribeTags",
      "ec2:DescribeVolumes",
      "ec2:DescribeVolumesModifications",
    ]
  }

  statement {
    effect = "Allow"

    resources = [
      "arn:${one(data.aws_partition.default[*].partition)}:ec2:*:*:volume/*",
      "arn:${one(data.aws_partition.default[*].partition)}:ec2:*:*:snapshot/*",
    ]

    actions = ["ec2:CreateTags"]

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"

      values = [
        "CreateVolume",
        "CreateSnapshot",
      ]
    }
  }

  statement {
    effect = "Allow"

    resources = [
      "arn:${one(data.aws_partition.default[*].partition)}:ec2:*:*:volume/*",
      "arn:${one(data.aws_partition.default[*].partition)}:ec2:*:*:snapshot/*",
    ]

    actions = ["ec2:DeleteTags"]
  }

  statement {
    effect    = "Allow"
    resources = ["*"]
    actions   = ["ec2:CreateVolume"]

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/ebs.csi.aws.com/cluster"
      values   = ["true"]
    }
  }

  statement {
    effect    = "Allow"
    resources = ["*"]
    actions   = ["ec2:CreateVolume"]

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/CSIVolumeName"
      values   = ["*"]
    }
  }

  statement {
    effect    = "Allow"
    resources = ["*"]
    actions   = ["ec2:CreateVolume"]

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/kubernetes.io/cluster/*"
      values   = ["owned"]
    }
  }

  statement {
    effect    = "Allow"
    resources = ["*"]
    actions   = ["ec2:DeleteVolume"]

    condition {
      test     = "StringLike"
      variable = "ec2:ResourceTag/ebs.csi.aws.com/cluster"
      values   = ["true"]
    }
  }

  statement {
    effect    = "Allow"
    resources = ["*"]
    actions   = ["ec2:DeleteVolume"]

    condition {
      test     = "StringLike"
      variable = "ec2:ResourceTag/CSIVolumeName"
      values   = ["*"]
    }
  }

  statement {
    effect    = "Allow"
    resources = ["*"]
    actions   = ["ec2:DeleteVolume"]

    condition {
      test     = "StringLike"
      variable = "ec2:ResourceTag/kubernetes.io/cluster/*"
      values   = ["owned"]
    }
  }

  statement {
    effect    = "Allow"
    resources = ["*"]
    actions   = ["ec2:DeleteSnapshot"]

    condition {
      test     = "StringLike"
      variable = "ec2:ResourceTag/CSIVolumeSnapshotName"
      values   = ["*"]
    }
  }

  statement {
    effect    = "Allow"
    resources = ["*"]
    actions   = ["ec2:DeleteSnapshot"]

    condition {
      test     = "StringLike"
      variable = "ec2:ResourceTag/ebs.csi.aws.com/cluster"
      values   = ["true"]
    }
  }

  statement {
    effect    = "Allow"
    resources = [module.ebs_csi_driver_kms_key.key_id]

    actions = [
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant",
    ]

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }

  statement {
    effect    = "Allow"
    resources = [module.ebs_csi_driver_kms_key.key_id]


    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
  }
}

module "ebs_csi_driver_eks_iam_role" {
  source  = "cloudposse/eks-iam-role/aws"
  version = "0.10.0"

  aws_iam_policy_document     = one(data.aws_iam_policy_document.ebs_csi_driver[*].json)
  aws_partition               = one(data.aws_partition.default[*].partition)
  eks_cluster_oidc_issuer_url = one(data.aws_eks_cluster.default[*].identity[0].oidc[0].issuer)
  service_account_name        = local.ebs_csi_driver["name"]
  service_account_namespace   = local.ebs_csi_driver["namespace"]

  context = module.ebs_csi_driver_label.context
}

resource "helm_release" "ebs_csi_driver" {
  count = local.ebs_csi_driver_enabled ? 1 : 0

  name              = local.ebs_csi_driver["name"]
  repository        = local.ebs_csi_driver["repository"]
  chart             = local.ebs_csi_driver["chart"]
  version           = local.ebs_csi_driver["version"]
  namespace         = local.ebs_csi_driver["namespace"]
  max_history       = local.ebs_csi_driver["max_history"]
  create_namespace  = local.ebs_csi_driver["create_namespace"]
  dependency_update = local.ebs_csi_driver["dependency_update"]
  reuse_values      = local.ebs_csi_driver["reuse_values"]
  wait              = local.ebs_csi_driver["wait"]
  timeout           = local.ebs_csi_driver["timeout"]
  values            = local.ebs_csi_driver_values

  set {
    name  = "fullnameOverride"
    value = local.ebs_csi_driver["name"]
  }

  set {
    name  = "controller.k8sTagClusterId"
    value = one(data.aws_eks_cluster.default[*].id)
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.ebs_csi_driver_eks_iam_role.service_account_role_arn
  }

  set {
    name  = "node.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.ebs_csi_driver_eks_iam_role.service_account_role_arn
  }

  depends_on = [
    helm_release.ebs_csi_driver,
    module.ebs_csi_driver_eks_iam_role,
    module.ebs_csi_driver_kms_key
  ]
}
