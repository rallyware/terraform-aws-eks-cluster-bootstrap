locals {
  prometheus_operator_crd_urls = { for url in var.prometheus_operator_crd_urls : uuidv5("url", url) => url }
}

data "http" "prometheus_operator_crds" {
  for_each = local.prometheus_operator_crd_urls

  url = each.value
}

resource "kubectl_manifest" "prometheus_operator_crds" {
  for_each = local.prometheus_operator_crd_urls

  yaml_body = data.http.prometheus_operator_crds[each.key].body
  force_new = true
  wait      = true
}
