resource "kubectl_manifest" "linkerd_webhook_trust_anchor_issuer" {
  count = local.linkerd_enabled ? 1 : 0

  yaml_body = <<YAML
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: webhook-issuer
  namespace: ${local.linkerd_namespace}
spec:
  ca:
    secretName: ${one(kubernetes_secret.linkerd_webhook_trust_anchor[*].metadata.0.name)}
YAML
}

resource "kubectl_manifest" "linkerd_proxy_injector_certificate" {
  count = local.linkerd_enabled ? 1 : 0

  yaml_body = <<YAML
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: linkerd-proxy-injector
  namespace: ${local.linkerd_namespace}
spec:
  secretName: linkerd-proxy-injector-k8s-tls
  duration: 24h
  renewBefore: 1h
  issuerRef:
    name: ${one(kubectl_manifest.linkerd_webhook_trust_anchor_issuer[*].name)}
    kind: Issuer
  commonName: linkerd-proxy-injector.linkerd.svc
  dnsNames:
  - linkerd-proxy-injector.linkerd.svc
  isCA: false
  privateKey:
    algorithm: ECDSA
  usages:
  - server auth
YAML
}

resource "kubectl_manifest" "linkerd_sp_validator_certificate" {
  count = local.linkerd_enabled ? 1 : 0

  yaml_body = <<YAML
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: linkerd-sp-validator
  namespace: ${local.linkerd_namespace}
spec:
  secretName: linkerd-sp-validator-k8s-tls
  duration: 24h
  renewBefore: 1h
  issuerRef:
    name: ${one(kubectl_manifest.linkerd_webhook_trust_anchor_issuer[*].name)}
    kind: Issuer
  commonName: linkerd-sp-validator.linkerd.svc
  dnsNames:
  - linkerd-sp-validator.linkerd.svc
  isCA: false
  privateKey:
    algorithm: ECDSA
  usages:
  - server auth
YAML
}
