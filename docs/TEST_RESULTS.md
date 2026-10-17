# Test Results

This file records **evidence**, not intentions. An entry moves to *Verified*
only with the environment, date, commands and outcome written down. Anything
not listed as verified should be treated as untested.

_Last updated: 2026-10-17 (final; the project is archived and no end-to-end run is planned)_

## Static validation (CI)

Run on every push / pull request by [`.github/workflows/ci.yml`](../.github/workflows/ci.yml).
"Passing locally" means the same tool and version was run on a developer
machine; GitHub Actions run history is the authoritative record.

| Check | Scope | Status |
| --- | --- | --- |
| yamllint (strict) | all YAML except `website/`, `small-scale/mailcow/` | Passing locally 2026-10-17 |
| kubeconform (strict, K8s 1.35 + CRDs catalog) | `kubernetes/` (41 resources) | Passing locally 2026-10-17 |
| gitleaks (working tree) | repository | Passing locally 2026-10-17 |
| ansible-lint (production profile) + syntax check | `infrastructure/` | Passing locally 2026-10-17 (ansible-lint 26.10.1, ansible-core 2.21.5) |
| ShellCheck | `infrastructure/*.sh`, `scripts/*.sh` | Passing locally 2026-10-17 (0.11.0) |
| Trivy config (HIGH/CRITICAL) | repository (excl. `website/`, `small-scale/mailcow/`, `kubernetes/experimental/`) | Passing locally 2026-10-17 (v0.76.0, with `.trivyignore.yaml`) |
| `docker compose config` | `small-scale/*.yml` with `.env.example` | Passing locally 2026-10-17 |

## Deployment verification

Environment template: hypervisor, node count/sizes, Ubuntu release, kernel,
network. Fill in per run.

| Component | Pinned version | Environment | Result | Date | Notes |
| --- | --- | --- | --- | --- | --- |
| RKE2 single server | v1.35.9+rke2r1 | — | Not yet verified | — | |
| RKE2 server + 2 agents (join flow) | v1.35.9+rke2r1 | — | Not yet verified | — | |
| RKE2 3-server HA (etcd quorum, server loss) | v1.35.9+rke2r1 | — | Not yet verified | — | |
| Longhorn | 1.13.0 | — | Not yet verified | — | |
| MetalLB (L2) | chart 0.16.1 | — | Not yet verified | — | |
| cert-manager | v1.21.2 | — | Not yet verified | — | |
| Rancher | 2.15.2 | — | Not yet verified | — | |
| Samba AD | nowsci/samba-domain:20261001025201 | — | Not yet verified | — | |
| Authentik | 2026.8.4 | — | Not yet verified | — | |
| Prometheus | v3.15.0 | — | Not yet verified | — | |
| Grafana | 13.2.4 | — | Not yet verified | — | |
| Wazuh (upstream wazuh-kubernetes) | 4.14.9 | — | Not yet verified | — | Repo manifest is partial |
| MinIO | RELEASE.2024-12-18T13-15-44Z | — | Not yet verified | — | Upstream image publishing stopped |
| Velero backup | v1.18.4 / plugin-aws v1.14.4 | — | Not yet verified | — | |
| Velero **restore** into clean namespace | v1.18.4 | — | Not yet verified | — | Record duration (RTO) and data age (RPO) |
| Zimbra | — | — | Not supported | — | `kubernetes/experimental/` |
| small-scale Compose stack | see compose files | — | Not yet verified | — | |

## Known limitations

- No end-to-end deployment has been recorded yet; all deployment rows above are unverified.
- HA behaviour (server/node failure, rolling upgrades) is untested.
- No restore drill has been performed; RPO/RTO targets are not yet defined.
- Velero and MinIO run in the same cluster; MinIO is single-replica and is not yet replicated off-site.
- Kubernetes-object backups are not consistent database backups; application-level dumps are not yet automated.
- NetworkPolicies are documented as a baseline example only; no tested per-service policy set exists.
- `kubernetes/monitoring/wazuh.yaml` does not deploy the Wazuh indexer.
- MinIO community container images are no longer published upstream; the pinned image receives no updates.
- Images are pinned by version tag, not by digest.
- Zimbra has no trusted container image and is excluded from the supported flow.
