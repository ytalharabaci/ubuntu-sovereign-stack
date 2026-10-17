#!/usr/bin/env bash
# Create the Kubernetes Secrets referenced by the manifests under kubernetes/.
# Values are generated locally with openssl and never written to disk or Git.
#
# Usage:
#   scripts/bootstrap-secrets.sh            # create missing secrets, keep existing ones
#   scripts/bootstrap-secrets.sh --rotate   # regenerate ALL secrets (restart workloads afterwards)
#
# Requires: kubectl (pointing at the target cluster), openssl.
set -euo pipefail

ROTATE=false
case "${1:-}" in
  --rotate) ROTATE=true ;;
  "") ;;
  -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
  *) echo "Unknown argument: $1" >&2; exit 2 ;;
esac

for bin in kubectl openssl; do
  command -v "$bin" >/dev/null || { echo "Missing dependency: $bin" >&2; exit 1; }
done

rand() { openssl rand -base64 "${1:-32}" | tr -d '\n/+=' | cut -c1-"${2:-40}"; }

ensure_ns() {
  kubectl create namespace "$1" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
}

exists() { kubectl -n "$1" get secret "$2" >/dev/null 2>&1; }

# apply_secret <namespace> <name> <kubectl create secret generic args...>
apply_secret() {
  local ns=$1 name=$2; shift 2
  kubectl -n "$ns" create secret generic "$name" "$@" --dry-run=client -o yaml \
    | kubectl apply -f - >/dev/null
  echo "  ${ns}/${name}: written"
}

should_write() {
  if exists "$1" "$2" && [ "$ROTATE" = false ]; then
    echo "  $1/$2: exists, skipped (use --rotate to regenerate)"
    return 1
  fi
  return 0
}

echo "Bootstrapping secrets (rotate=${ROTATE})"

ensure_ns identity
if should_write identity authentik-secrets; then
  apply_secret identity authentik-secrets \
    --from-literal=postgres-password="$(rand 32 40)" \
    --from-literal=authentik-secret-key="$(rand 64 60)"
fi

ensure_ns core
if should_write core samba-secrets; then
  # Samba requires upper/lower case, digits and a symbol.
  apply_secret core samba-secrets \
    --from-literal=admin-password="Aa1!$(rand 24 28)"
fi

ensure_ns monitoring
if should_write monitoring grafana-admin; then
  apply_secret monitoring grafana-admin \
    --from-literal=password="$(rand 24 32)"
fi

# MinIO root credentials and the Velero S3 credentials must match.
ensure_ns backup
ensure_ns velero
if should_write backup minio-credentials; then
  MINIO_ACCESS_KEY="velero-$(rand 12 12)"
  MINIO_SECRET_KEY="$(rand 32 40)"
  apply_secret backup minio-credentials \
    --from-literal=accesskey="$MINIO_ACCESS_KEY" \
    --from-literal=secretkey="$MINIO_SECRET_KEY"
  apply_secret velero cloud-credentials \
    --from-literal=cloud="$(printf '[default]\naws_access_key_id=%s\naws_secret_access_key=%s\n' \
      "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY")"
  unset MINIO_ACCESS_KEY MINIO_SECRET_KEY
fi

cat <<'EOF'

Done. Retrieve a value when needed (avoid shell history / screen sharing):
  kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.password}' | base64 -d
  kubectl -n core get secret samba-secrets -o jsonpath='{.data.admin-password}' | base64 -d
  kubectl -n backup get secret minio-credentials -o jsonpath='{.data.secretkey}' | base64 -d
After --rotate, restart the affected workloads (kubectl rollout restart ...).
Note: rotating authentik/postgres or samba passwords after first start also
requires changing them inside the running service; see docs/OPERATIONAL_RUNBOOK.md.
EOF
