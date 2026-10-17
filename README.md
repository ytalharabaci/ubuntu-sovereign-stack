# Ubuntu Sovereign Stack

[![CI](https://github.com/yusufarbc/ubuntu-sovereign-stack/actions/workflows/ci.yml/badge.svg)](https://github.com/yusufarbc/ubuntu-sovereign-stack/actions/workflows/ci.yml)

> **Archived (2026-10-17).** This project is no longer maintained. Issues and
> pull requests are closed. Pinned component versions were current as of
> October 2026 and will not receive security updates; review and update every
> version before reusing any part of this repository.

> **Project status: reference architecture / infrastructure-as-code.**
> Manifests, playbooks and scripts are statically validated in CI (YAML lint,
> ansible-lint, Kubernetes schema validation, ShellCheck, secret scanning, Trivy
> IaC scan). They have **not** yet been verified end-to-end on a live cluster and
> are not production-certified. Verified components and known limitations are
> tracked in [docs/TEST_RESULTS.md](docs/TEST_RESULTS.md).

## Abstract
Enterprise workloads increasingly depend on hyperscale clouds governed by extraterritorial laws (e.g., the U.S. CLOUD Act). Even when data resides in-region, vendor-operated control planes and encryption keys can be compelled for disclosure. The Ubuntu Sovereign Stack is an on-premise, open-source reference architecture that keeps identity, collaboration, and observability fully under organizational custody. It pairs Ubuntu Server LTS with Kubernetes (RKE2) and Rancher for cluster governance (workloads on RKE2's bundled containerd; Podman for daemonless image builds on admin hosts), Samba 4 + Authentik for identity, Zimbra for mail/collaboration (experimental), and Wazuh/Prometheus/Grafana for security and metrics. Client flexibility is preserved via ten Ubuntu-based desktops tuned to user personas, minimizing lock-in while sustaining manageability.

## Architecture at a Glance
| Layer | Choice / Rationale |
| --- | --- |
| Server OS | Ubuntu Server LTS (5y support, HWE, broad ecosystem) |
| Orchestration | Kubernetes (RKE2) managed by Rancher (UI, RBAC, lifecycle) |
| Container Runtime | containerd (bundled with RKE2) for workloads; Podman (daemonless, rootless) on admin/build hosts; no Docker daemon |
| Identity | Samba 4 AD (source of truth) + Authentik (SSO/MFA) |
| Collaboration | Zimbra CE + ClamAV + SpamAssassin (experimental; no trusted image yet) |
| Security/Observability | Wazuh (SIEM/XDR), Prometheus + Grafana (metrics/dashboards) |
| Storage/Networking | Longhorn (CSI), MetalLB (L2 LB), Cert-Manager (PKI) |
| Management | Ansible for provisioning; Rancher for day-2 K8s ops |
| Client Strategy | 10 Ubuntu-based distros aligned to roles (below) |

### The “Flexible 10” Client Strategy
1) Ubuntu Desktop (standard) • 2) Linux Mint (office) • 3) Zorin OS (management) • 4) Pop!_OS (engineering) • 5) Kubuntu (power users) • 6) Xubuntu (legacy HW) • 7) Lubuntu (thin) • 8) Ubuntu MATE (traditional) • 9) elementary OS (kiosk/public) • 10) KDE Neon (R&D).

## Quick Start (lab)
Prereqs: a control machine with `ansible-core`, `kubectl`, `helm`, `openssl` and SSH key access to Ubuntu Server LTS nodes.
Full walkthrough: [docs/QUICKSTART.md](docs/QUICKSTART.md).

```bash
git clone https://github.com/yusufarbc/ubuntu-sovereign-stack.git && cd ubuntu-sovereign-stack

# 1. Inventory: [rke2_servers] (odd count: 1 lab / 3 HA) and [rke2_agents]
$EDITOR infrastructure/hosts.ini

# 2. RKE2: first server bootstraps, other servers and agents join with its token
ansible-playbook -i infrastructure/hosts.ini infrastructure/setup-rke2.yml

# 3. System layer (pinned Helm charts)
infrastructure/install-longhorn.sh
helm repo add metallb https://metallb.github.io/metallb
helm upgrade --install metallb metallb/metallb --version 0.16.1 -n metallb-system --create-namespace --wait
kubectl apply -f kubernetes/system/metallb.yaml
infrastructure/install-rancher.sh && kubectl apply -f kubernetes/system/cert-manager.yaml

# 4. Secrets: generated in-cluster, never committed
scripts/bootstrap-secrets.sh

# 5. Workloads
kubectl apply -f kubernetes/core/ -f kubernetes/monitoring/prometheus.yaml -f kubernetes/monitoring/grafana.yaml
kubectl apply -f kubernetes/backup/minio.yaml   # then Velero, see kubernetes/backup/velero.yaml
```

## Repository Layout
- `.github/workflows/`: CI (`ci.yml`: lint, schema and security checks) and GitHub Pages (`static.yml`)
- `docs/`: thesis docs, architecture, setup guides, runbooks, test results
- `infrastructure/`: Ansible inventory, RKE2 playbook, `group_vars/`, templates, and Helm install scripts (Longhorn, cert-manager, Rancher)
- `scripts/`: operational helpers (`bootstrap-secrets.sh`)
- `kubernetes/`
  - `system/`: MetalLB pool, cert-manager issuers, Longhorn storage class
  - `core/`: Samba AD (`core` ns), Authentik (`identity` ns)
  - `monitoring/`: Prometheus, Grafana (`monitoring` ns), Wazuh (`security` ns, partial reference)
  - `backup/`: MinIO, Velero configuration
  - `experimental/`: unsupported components (Zimbra)
- `small-scale/`: Docker Compose variant for a single host (`.env.example` → `.env`)
- `website/`: static landing page

## Key Documentation
- [docs/QUICKSTART.md](docs/QUICKSTART.md): Single-node and small multi-node lab setup.
- [docs/CLUSTER_SETUP_GUIDE.md](docs/CLUSTER_SETUP_GUIDE.md): Target HA topology (3 servers + agents); not yet verified.
- [docs/DEPLOYMENT_ORDER.md](docs/DEPLOYMENT_ORDER.md): Required manifest sequence and validation checkpoints.
- [docs/DEPLOYMENT_CHECKLIST.md](docs/DEPLOYMENT_CHECKLIST.md): Post-install validation, troubleshooting, sign-off.
- [docs/OPERATIONAL_RUNBOOK.md](docs/OPERATIONAL_RUNBOOK.md): Day-2 operations (scaling, maintenance, rotations, restore drills).
- [docs/SECURITY_HARDENING.md](docs/SECURITY_HARDENING.md): Network policies, RBAC, pod security, image policy, secrets.
- [docs/TEST_RESULTS.md](docs/TEST_RESULTS.md): What has been verified, on which versions, and known limitations.
- [docs/AUDIT_REPORT.md](docs/AUDIT_REPORT.md): Historical 2024 documentation gap analysis (not a validation report).
- [SECURITY.md](SECURITY.md): Vulnerability reporting, secret handling and CI security gates.
