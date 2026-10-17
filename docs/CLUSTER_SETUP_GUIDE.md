# Kubernetes Cluster Setup Guide

> **Status: target architecture, lab / unverified.** The HA procedure below has
> not yet been executed end-to-end; see [TEST_RESULTS.md](TEST_RESULTS.md).

## Overview
This guide provides step-by-step instructions to deploy the Ubuntu Sovereign Stack on a bare-metal or IaaS Kubernetes cluster using RKE2, managed by Rancher.

**Target Audience:** Infrastructure operators, DevOps engineers  
**Duration:** 2–4 hours (depending on hardware provisioning)  
**Supported Platform:** Ubuntu Server 22.04 LTS / 24.04 LTS

---

## Part 1: Prerequisites & Planning

### 1.1 Hardware Requirements

| Component | Specification | Rationale |
|-----------|---------------|-----------|
| **Control Plane Nodes** | 3x (min 4 CPUs, 8GB RAM, 50GB disk each) | HA Kubernetes control plane; etcd replication |
| **Worker Nodes** | 2–5x (min 8 CPUs, 16GB RAM, 100GB disk each) | Workload distribution; Longhorn storage replication |
| **Network** | Layer 2 connectivity; static IPs | MetalLB L2 mode; DNS resolution |
| **Storage** | Raw block devices (for Longhorn) | Replicated distributed storage |
| **Total Cluster** | 5–8 nodes (minimum) | Target HA topology (not yet verified, see TEST_RESULTS.md) |

### 1.2 Network Planning

Before starting, plan and document:

```
Control Plane VIPs:
  - kube-api:       192.168.1.50 (Kubernetes API)
  - rancher:        192.168.1.51 (Rancher UI)
  - ingress:        192.168.1.52-100 (MetalLB pool)

DNS Records:
  - rancher.sovereign.lan → 192.168.1.51
  - *.apps.sovereign.lan → 192.168.1.52 (wildcard ingress)
  
Firewall Rules (inbound to control plane):
  - 6443 (Kubernetes API) from admins
  - 80, 443 (Ingress) from clients
  - 2379–2380 (etcd) between control nodes only
  - 10250 (kubelet) between nodes
  - 10251–10252 (scheduler, controller) internal
```

### 1.3 Infrastructure Inventory

Edit `infrastructure/hosts.ini`. Servers run the control plane and etcd; use an
**odd number** (3 for HA tolerates one server failure, 5 tolerates two).

```ini
[rke2_servers]
192.168.1.10   # cp1 - bootstraps the cluster
192.168.1.11   # cp2
192.168.1.12   # cp3

[rke2_agents]
192.168.1.20   # w1
192.168.1.21   # w2
192.168.1.22   # w3

[k8s:children]
rke2_servers
rke2_agents

[k8s:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/id_ed25519
# HA: a fixed registration address (VIP / DNS / L4 load balancer on 9345 + 6443)
rke2_api_endpoint=192.168.1.50
rke2_tls_san=kube-api.sovereign.lan
```

The RKE2 version is pinned in `infrastructure/group_vars/k8s.yml`.

For HA, the registration address must be reachable **before** the playbook joins
cp2/cp3. Point it at cp1 first (or configure the load balancer with cp1 as the
only backend), then add cp2/cp3 as backends once they are Ready.

### 1.4 Pre-Deployment Verification

Run from your Ansible control node:

```bash
ansible -i infrastructure/hosts.ini k8s -m ping
ansible -i infrastructure/hosts.ini k8s -m shell -a "lsb_release -ds && nproc && free -h && df -h /"
```

---

## Part 2: OS & RKE2 Installation

### 2.1 Run Ansible Provisioning

```bash
ansible-playbook -i infrastructure/hosts.ini infrastructure/setup-rke2.yml
```

**What this does (in order):**
1. All nodes: OS updates, `open-iscsi`/`nfs-common` for Longhorn, swap off, RKE2 installer download.
2. `rke2_servers[0]`: writes `/etc/rancher/rke2/config.yaml` (`tls-san`, kubeconfig mode 0600), installs and starts `rke2-server`, reads the node token.
3. `rke2_servers[1:]`: join through `https://<rke2_api_endpoint>:9345` with the token, **one at a time**.
4. `rke2_agents`: join as `rke2-agent`.
5. Servers: `kubectl`/`crictl` symlinks and PATH.

Kubernetes workloads run on RKE2's bundled **containerd**. Podman is not
installed on cluster nodes; use it only on admin/build hosts if needed.

The token is never written to the repository or printed (`no_log`).

### 2.2 Verify Cluster Readiness

```bash
ssh ubuntu@192.168.1.10 'sudo cat /etc/rancher/rke2/rke2.yaml' > ~/.kube/sovereign-stack.yaml
chmod 600 ~/.kube/sovereign-stack.yaml
sed -i 's/127.0.0.1/192.168.1.50/' ~/.kube/sovereign-stack.yaml   # API endpoint
export KUBECONFIG=~/.kube/sovereign-stack.yaml

kubectl get nodes -o wide
# Expect 3 nodes with roles control-plane,etcd,master and 3 worker nodes, all Ready
```

### 2.3 Manual join (reference)

The playbook automates this. Manually, each joining node needs
`/etc/rancher/rke2/config.yaml` **before** the service starts:

```yaml
server: https://192.168.1.50:9345   # supervisor port, not 6443
token: <contents of /var/lib/rancher/rke2/server/node-token on cp1>
```

followed by `curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_VERSION=<pinned> INSTALL_RKE2_TYPE=server|agent sh -`
and `sudo systemctl enable --now rke2-server` (or `rke2-agent`).

---

## Part 3: System Layer Installation

Deploy cluster prerequisites in this order. All chart versions are pinned.

### 3.1 Longhorn Storage

```bash
infrastructure/install-longhorn.sh
kubectl -n longhorn-system rollout status deploy/longhorn-driver-deployer --timeout=10m
kubectl get storageclass longhorn
```

### 3.2 MetalLB

```bash
# Edit the address pool in kubernetes/system/metallb.yaml first
helm repo add metallb https://metallb.github.io/metallb --force-update
helm upgrade --install metallb metallb/metallb --version 0.16.1   -n metallb-system --create-namespace --wait
kubectl apply -f kubernetes/system/metallb.yaml      # IPAddressPool + L2Advertisement
kubectl -n metallb-system get ipaddresspools,l2advertisements
```

### 3.3 cert-manager + Rancher

```bash
infrastructure/install-rancher.sh                 # cert-manager v1.21.2, Rancher 2.15.2
kubectl apply -f kubernetes/system/cert-manager.yaml
```

The Rancher bootstrap password is random unless `RANCHER_BOOTSTRAP_PASSWORD` is
set; the script prints the command to read it. Change it at first login.

### 3.4 Secrets

```bash
scripts/bootstrap-secrets.sh
```

All credentials are generated in-cluster; none are stored in Git. Use
`--rotate` to regenerate them (see OPERATIONAL_RUNBOOK.md for the follow-up
steps inside each application).

---

## Part 4: Core Identity Services

```bash
kubectl apply -f kubernetes/core/samba-ad.yaml       # namespace: core
kubectl apply -f kubernetes/core/authentik.yaml      # namespace: identity

kubectl -n core wait --for=condition=ready pod -l app=samba-ad --timeout=600s
kubectl -n identity rollout status deploy/authentik-server --timeout=600s
kubectl get pvc -n core; kubectl get pvc -n identity
```

---

## Part 5: Applications Layer

### 5.1 Monitoring (Prometheus + Grafana)

```bash
kubectl apply -f kubernetes/monitoring/prometheus.yaml   # creates namespace monitoring
kubectl apply -f kubernetes/monitoring/grafana.yaml
kubectl -n monitoring rollout status deploy/grafana
```

Grafana is `ClusterIP`; expose it with an Ingress + cert-manager TLS. User
`admin`, password in secret `monitoring/grafana-admin`.

Wazuh (`kubernetes/monitoring/wazuh.yaml`, namespace `security`) is a partial
reference manifest without the indexer. Use the upstream `wazuh-kubernetes`
manifests (v4.14.9) for a working SIEM.

### 5.2 Backup (MinIO + Velero)

```bash
kubectl apply -f kubernetes/backup/minio.yaml
kubectl -n backup wait --for=condition=ready pod -l app=minio --timeout=300s
# create bucket backup-uss in MinIO, then install Velero with Helm as described
# in the header of kubernetes/backup/velero.yaml
kubectl apply -f kubernetes/backup/velero.yaml        # BSL, CSI snapshot class, daily schedule
velero backup-location get
```

Replicate the MinIO bucket to a second physical/geographic location and run a
restore drill before relying on these backups.

### 5.3 Collaboration (Zimbra) - experimental

Zimbra is **not** part of the supported flow: there is no trusted, maintained
container image. The manifest lives in `kubernetes/experimental/zimbra.yaml`
(namespace `collaboration`) and must not be deployed until an image has been
built, pinned and tested.

---

## Part 6: Verification & Validation

### 6.1 Cluster Health Check

```bash
# Node status
kubectl get nodes -o wide

# Pod status (all namespaces)
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded

# StorageClass and PVs
kubectl get sc,pv,pvc -A

# Services and IPs
kubectl get svc -A | grep -E "^(NAMESPACE|default|core|identity|monitoring|security|backup|longhorn)"
```

### 6.2 CNI & Networking Verification

```bash
# Deploy test pod
kubectl run -it --rm test-pod --image=alpine -- sh

# Inside pod:
ping 8.8.8.8  # external connectivity
nslookup kubernetes.default  # DNS resolution
exit
```

### 6.3 Storage Verification

```bash
# Create test PVC and pod
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-storage
spec:
  containers:
  - name: test
    image: alpine
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /mnt
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: test-pvc
EOF

# Verify persistence
kubectl exec test-storage -- sh -c 'echo "test" > /mnt/test.txt && cat /mnt/test.txt'

# Cleanup
kubectl delete pod test-storage pvc test-pvc
```

### 6.4 Ingress Verification

```bash
# Check ingress controller
kubectl get pods -n kube-system | grep -E "ingress|traefik"   # RKE2 bundled ingress controller

# Test ingress (if any deployed)
kubectl get ingress -A
```

---

## Part 7: Post-Deployment Configuration

### 7.1 Configure DNS

Add DNS records pointing to MetalLB pool:

```dns
rancher.sovereign.lan     → 192.168.1.52
*.apps.sovereign.lan      → 192.168.1.52
samba.sovereign.lan       → 192.168.1.52
authentik.sovereign.lan   → 192.168.1.52
grafana.sovereign.lan     → 192.168.1.52
prometheus.sovereign.lan  → 192.168.1.52
```

### 7.2 Configure Backups

Test Velero backup:

```bash
# Create manual backup
velero backup create initial-backup --wait

# Check backup status
velero backup get
velero backup logs initial-backup

# Schedule daily backups (already done in 5.2)
kubectl get schedule -n velero
```

### 7.3 Secure Rancher UI

```bash
# Generate self-signed cert (or use your CA)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt -subj "/CN=rancher.sovereign.lan"

# Create TLS secret
kubectl create secret tls rancher-tls -n cattle-system \
  --cert=tls.crt --key=tls.key

# Update Rancher Ingress to use TLS
kubectl patch ingress -n cattle-system rancher \
  -p '{"spec":{"tls":[{"hosts":["rancher.sovereign.lan"],"secretName":"rancher-tls"}]}}'
```

---

## Part 8: Troubleshooting

### Node Not Ready

```bash
# Check kubelet service
sudo systemctl status rke2-server  # (or rke2-agent on workers)

# Check kubelet logs
sudo journalctl -u rke2-server -n 50 --no-pager

# Check CNI plugin
kubectl get daemonset -A | grep -i cni
```

### Pod Stuck in Pending

```bash
# Describe pod
kubectl describe pod <pod-name> -n <namespace>

# Check PVC binding (if storage-related)
kubectl get pvc -n <namespace>

# Check node capacity
kubectl top nodes
kubectl describe node <node-name>
```

### Storage Not Available

```bash
# Check Longhorn status
kubectl get pods -n longhorn-system
kubectl logs -n longhorn-system deployment/longhorn-manager

# Check replicas
kubectl get -n longhorn-system volumereplicasets.longhorn.io
```

### Rancher Bootstrap Failed

```bash
# Reset bootstrap password
kubectl delete secret bootstrap-secret -n cattle-system

# Restart Rancher
kubectl rollout restart deployment/rancher -n cattle-system

# Check logs
kubectl logs -f deployment/rancher -n cattle-system
```

---

## Appendix: Deployment Order Dependency Graph

```
1. RKE2 Cluster (servers first, then agents)
   ↓
2. Longhorn (storage)
   ↓
3. MetalLB
   ↓
4. cert-manager + Rancher (management UI) [Rancher optional]
   ↓
4b. Secrets (scripts/bootstrap-secrets.sh)
   ↓
5. Core Services (Samba AD + Authentik)
   ↓
6. Apps Layer
   ├→ 6a. Monitoring (Prometheus + Grafana + Wazuh)
   ├→ 6b. Backup (MinIO + Velero)
   └→ 6c. Collaboration (Zimbra) [experimental, not deployed]
```

---

## Next Steps

1. **Day 2 Operations:** See [DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md) for post-installation validation.
2. **Client Provisioning:** Follow [CLIENT_STRATEGY.md](CLIENT_STRATEGY.md) to deploy the "Flexible 10" desktops.
3. **Operational Runbooks:** Reference individual service documentation in `/docs/`.

---

**Last Updated:** 2026-10-17  
**Status:** Target architecture, lab / unverified (see [TEST_RESULTS.md](TEST_RESULTS.md))  
**Support:** See README.md for community channels
