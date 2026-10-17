# Deployment Order & Dependencies

> **Status: lab / unverified.** The order below matches the files in this
> repository and is statically validated in CI, but has not yet been executed
> end-to-end. See [TEST_RESULTS.md](TEST_RESULTS.md).

This document gives the order in which components must be deployed, what each
step depends on, and a checkpoint to confirm before moving on. Step-by-step
commands are in [QUICKSTART.md](QUICKSTART.md) (lab) and
[CLUSTER_SETUP_GUIDE.md](CLUSTER_SETUP_GUIDE.md) (HA target).

## Phases

```text
Phase 0: RKE2 cluster           infrastructure/setup-rke2.yml
  ↓
Phase 1: System layer
  ├→ Longhorn                   infrastructure/install-longhorn.sh
  ├→ MetalLB                    helm + kubernetes/system/metallb.yaml
  ├→ cert-manager + Rancher     infrastructure/install-rancher.sh + kubernetes/system/cert-manager.yaml
  └→ Secrets                    scripts/bootstrap-secrets.sh
  ↓
Phase 2: Identity
  ├→ Samba AD                   kubernetes/core/samba-ad.yaml      (ns: core)
  └→ Authentik                  kubernetes/core/authentik.yaml     (ns: identity)
  ↓
Phase 3: Observability & backup
  ├→ Prometheus, Grafana        kubernetes/monitoring/             (ns: monitoring)
  ├→ Wazuh (partial reference)  kubernetes/monitoring/wazuh.yaml   (ns: security)
  └→ MinIO, Velero              kubernetes/backup/                 (ns: backup, velero)
  ↓
Phase 4: Clients                Ubuntu desktops ("Flexible 10")

Not in the supported flow:
  Zimbra                        kubernetes/experimental/zimbra.yaml (ns: collaboration)
```

## Phase checkpoints

| Phase | Depends on | Checkpoint before continuing |
| --- | --- | --- |
| 0 RKE2 | SSH access, inventory groups `rke2_servers` / `rke2_agents`, odd server count | `kubectl get nodes` shows every node `Ready` |
| 1 Longhorn | Phase 0; `open-iscsi` on nodes (playbook) | `kubectl get sc longhorn`; test PVC binds |
| 1 MetalLB | Phase 0; free IP range on the LAN | `kubectl -n metallb-system get ipaddresspools` lists `default` |
| 1 cert-manager / Rancher | Phase 0 | `kubectl -n cert-manager get pods` Running; `kubectl get clusterissuers` Ready |
| 1 Secrets | namespaces can be created | `kubectl get secret -A \| grep -E 'authentik-secrets\|samba-secrets\|grafana-admin\|minio-credentials\|cloud-credentials'` lists 5 secrets |
| 2 Samba AD | Longhorn, `core/samba-secrets` | pod `samba-ad-0` Ready (LDAP port 389 open) |
| 2 Authentik | Longhorn, `identity/authentik-secrets` | `authentik-server` Ready (`/-/health/ready/`) |
| 3 Monitoring | Longhorn, `monitoring/grafana-admin` | Prometheus `/-/ready`; Grafana `/api/health` |
| 3 MinIO | Longhorn, `backup/minio-credentials` | `minio-0` Ready; bucket `backup-uss` exists |
| 3 Velero | MinIO, Velero Helm chart, `velero/cloud-credentials` | `velero backup-location get` → `Available`; a test restore succeeds |

## Validation script

```bash
#!/usr/bin/env bash
# check-phase.sh <1|2|3>
set -euo pipefail
case "${1:?phase}" in
  1) kubectl -n longhorn-system get pods
     kubectl -n metallb-system get pods,ipaddresspools,l2advertisements
     kubectl -n cert-manager get pods
     kubectl get storageclass ;;
  2) kubectl -n core get pods,svc
     kubectl -n identity get pods,svc ;;
  3) kubectl -n monitoring get pods
     kubectl -n backup get pods,pvc
     velero backup-location get ;;
esac
echo "Pods not Running/Succeeded:"
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
```

## Rollback

Delete in reverse order. **PVCs and Longhorn volumes hold data**: back up first.

```bash
# Phase 3
kubectl delete -f kubernetes/backup/velero.yaml
helm uninstall velero -n velero
kubectl delete -f kubernetes/backup/minio.yaml
kubectl delete -f kubernetes/monitoring/

# Phase 2
kubectl delete -f kubernetes/core/

# Phase 1
helm uninstall rancher -n cattle-system
kubectl delete -f kubernetes/system/cert-manager.yaml
helm uninstall cert-manager -n cert-manager
kubectl delete -f kubernetes/system/metallb.yaml
helm uninstall metallb -n metallb-system
helm uninstall longhorn -n longhorn-system   # set deleting-confirmation-flag first (Longhorn docs)
```

**Last updated:** 2026-10-17 · **Status:** Lab / unverified ·
**Next:** [DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md)
