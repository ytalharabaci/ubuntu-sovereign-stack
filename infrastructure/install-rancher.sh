#!/usr/bin/env bash
# Install cert-manager and Rancher (pinned versions) via Helm.
# Re-runnable: uses `helm upgrade --install`.
#
# Optional environment:
#   RANCHER_HOSTNAME             (default: rancher.sovereign.lan)
#   RANCHER_BOOTSTRAP_PASSWORD   (default: randomly generated, never printed)
set -euo pipefail

CERT_MANAGER_VERSION="v1.21.2"
RANCHER_VERSION="2.15.2"
RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-rancher.sovereign.lan}"
RANCHER_BOOTSTRAP_PASSWORD="${RANCHER_BOOTSTRAP_PASSWORD:-$(openssl rand -base64 32 | tr -d '\n/+=' | cut -c1-32)}"

# cert-manager
helm repo add jetstack https://charts.jetstack.io --force-update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --version "${CERT_MANAGER_VERSION}" \
  --set crds.enabled=true \
  --wait

# Rancher (internal self-signed certs for air-gapped / sovereign setups)
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable --force-update
helm upgrade --install rancher rancher-stable/rancher \
  --namespace cattle-system --create-namespace \
  --version "${RANCHER_VERSION}" \
  --set hostname="${RANCHER_HOSTNAME}" \
  --set bootstrapPassword="${RANCHER_BOOTSTRAP_PASSWORD}" \
  --set ingress.tls.source=rancher

kubectl -n cattle-system rollout status deploy/rancher --timeout=10m

cat <<EOF
Rancher is available at https://${RANCHER_HOSTNAME}
Retrieve the bootstrap password with:
  kubectl -n cattle-system get secret bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}{{"\n"}}'
Change it on first login.
EOF
