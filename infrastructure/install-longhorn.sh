#!/usr/bin/env bash
# Install Longhorn (pinned version) via Helm.
# Longhorn provides distributed block storage for the Kubernetes cluster.
# Prerequisite: open-iscsi and nfs-common on all nodes (handled in setup-rke2.yml).
# Single-node lab: pass --set persistence.defaultClassReplicaCount=1
set -euo pipefail

LONGHORN_VERSION="1.13.0"

echo "Adding Longhorn Helm repo..."
helm repo add longhorn https://charts.longhorn.io --force-update

echo "Installing Longhorn ${LONGHORN_VERSION}..."
helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system --create-namespace \
  --version "${LONGHORN_VERSION}" \
  --set defaultSettings.defaultDataPath="/var/lib/longhorn" \
  "$@"

echo "Longhorn installation initiated. Check status with: kubectl -n longhorn-system get pods"
