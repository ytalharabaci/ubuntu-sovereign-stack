# Quick Start Guide

> **Status: lab / unverified.** These steps are statically validated in CI
> (lint, schema, security scan) but have not yet been run end-to-end on a clean
> cluster. Results will be recorded in [TEST_RESULTS.md](TEST_RESULTS.md).
> Report anything that does not work as an issue.

This guide covers a **lab** deployment: one Ubuntu Server VM (single node) or a
small multi-node cluster. It is not a production/HA procedure; see
[CLUSTER_SETUP_GUIDE.md](CLUSTER_SETUP_GUIDE.md) for the HA topology.

## Prerequisites

| Item | Single-node lab | Multi-node lab |
| --- | --- | --- |
| Nodes | 1 × Ubuntu Server 24.04 LTS | 1 server + 2 agents (or 3 servers for HA) |
| Per node | 8 vCPU, 16 GB RAM, 100 GB disk | 4 vCPU, 8 GB RAM, 50 GB disk |
| Control machine | Linux/macOS/WSL with `ansible-core`, `kubectl`, `helm`, `openssl` | same |
| Network | SSH key access to every node; nodes reach each other on 6443, 9345, 10250, 2379-2380 (servers) | same |

## 1. Clone and configure the inventory

```bash
git clone https://github.com/yusufarbc/ubuntu-sovereign-stack.git
cd ubuntu-sovereign-stack
```

Edit [`infrastructure/hosts.ini`](../infrastructure/hosts.ini):

```ini
[rke2_servers]
192.168.1.10          # first server bootstraps the cluster

[rke2_agents]
192.168.1.11          # leave empty for a single-node lab
192.168.1.12

[k8s:children]
rke2_servers
rke2_agents

[k8s:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/id_ed25519
rke2_api_endpoint=192.168.1.10
rke2_tls_san=rke2.sovereign.lan
```

Use an **odd number of servers** (1 or 3) so etcd keeps quorum. The RKE2
version is pinned in [`infrastructure/group_vars/k8s.yml`](../infrastructure/group_vars/k8s.yml).

```bash
ansible -i infrastructure/hosts.ini k8s -m ping
```

## 2. Provision RKE2

```bash
ansible-playbook -i infrastructure/hosts.ini infrastructure/setup-rke2.yml
```

The playbook prepares the OS (Longhorn prerequisites, swap off), installs the
first server, reads its join token, joins additional servers one at a time,
and then joins the agents. Kubernetes workloads run on RKE2's bundled
**containerd**; Podman is not needed on cluster nodes.

Fetch the kubeconfig (it is root-only, mode 0600, on the server):

```bash
ssh ubuntu@192.168.1.10 'sudo cat /etc/rancher/rke2/rke2.yaml' > ~/.kube/sovereign.yaml
chmod 600 ~/.kube/sovereign.yaml
sed -i 's/127.0.0.1/192.168.1.10/' ~/.kube/sovereign.yaml
export KUBECONFIG=~/.kube/sovereign.yaml
kubectl get nodes -o wide     # all nodes Ready
```

## 3. System layer

```bash
# Longhorn storage (single-node lab: one replica)
infrastructure/install-longhorn.sh --set persistence.defaultClassReplicaCount=1
kubectl -n longhorn-system rollout status deploy/longhorn-driver-deployer --timeout=10m

# MetalLB (edit the address range in kubernetes/system/metallb.yaml first)
helm repo add metallb https://metallb.github.io/metallb --force-update
helm upgrade --install metallb metallb/metallb --version 0.16.1 -n metallb-system --create-namespace --wait
kubectl apply -f kubernetes/system/metallb.yaml

# cert-manager + Rancher (bootstrap password is random, see script output)
infrastructure/install-rancher.sh
kubectl apply -f kubernetes/system/cert-manager.yaml
```

## 4. Secrets

No credentials are stored in this repository. Generate them in the cluster:

```bash
scripts/bootstrap-secrets.sh
```

The script creates `identity/authentik-secrets`, `core/samba-secrets`,
`monitoring/grafana-admin`, `backup/minio-credentials` and
`velero/cloud-credentials` with random values, and prints how to read them.

## 5. Applications

```bash
kubectl apply -f kubernetes/core/samba-ad.yaml
kubectl apply -f kubernetes/core/authentik.yaml
kubectl apply -f kubernetes/monitoring/prometheus.yaml   # creates the monitoring namespace
kubectl apply -f kubernetes/monitoring/grafana.yaml
kubectl apply -f kubernetes/backup/minio.yaml

kubectl get pods -A
```

Wazuh ([`kubernetes/monitoring/wazuh.yaml`](../kubernetes/monitoring/wazuh.yaml))
is a partial reference manifest without the indexer; use the upstream
`wazuh-kubernetes` manifests for a working deployment.

Zimbra lives in [`kubernetes/experimental/`](../kubernetes/experimental/) and is
**not** part of this flow: there is no trusted container image yet.

## 6. Backups (Velero)

Install Velero with Helm as described in the header of
[`kubernetes/backup/velero.yaml`](../kubernetes/backup/velero.yaml), create the
`backup-uss` bucket in MinIO, then:

```bash
kubectl apply -f kubernetes/backup/velero.yaml
velero backup-location get                 # Phase: Available
velero backup create smoke-test --wait
velero restore create --from-backup smoke-test --namespace-mappings identity:identity-restore
```

A backup only counts once a restore into a clean namespace or cluster has been
verified. Record the result in [TEST_RESULTS.md](TEST_RESULTS.md).

## 7. Access services

Services are `ClusterIP` by default. For a quick lab check use port-forwarding:

```bash
kubectl -n monitoring port-forward svc/grafana 3000:80
kubectl -n identity   port-forward svc/authentik-server 9000:80
```

Grafana user is `admin`, password from `monitoring/grafana-admin`. Authentik
initial setup: `http://localhost:9000/if/flow/initial-setup/`.
For permanent access, create Ingresses with TLS from cert-manager.

## Adding nodes

Add the host to `[rke2_agents]` (or `[rke2_servers]`, keeping the count odd)
and re-run the playbook. Existing nodes are left unchanged: the install steps
are guarded with `creates:`.

## Troubleshooting

```bash
kubectl describe pod <pod> -n <ns>             # scheduling / image / probe errors
kubectl get pvc -A                             # storage binding
sudo journalctl -u rke2-server -f              # on a server node
sudo journalctl -u rke2-agent -f               # on an agent node
sudo /var/lib/rancher/rke2/bin/crictl ps -a    # containers on a node (containerd)
kubectl -n metallb-system get ipaddresspools,l2advertisements
```

**Status:** Lab / unverified · **Last updated:** 2026-10-17
