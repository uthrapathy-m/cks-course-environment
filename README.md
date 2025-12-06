# CKS Course Environment – kubeadm Cluster Setup

This repository contains scripts to quickly create a Kubernetes cluster for CKS-style practice using kubeadm, containerd and weave CNI.

## Scripts

### Master node

On a fresh Ubuntu 22.04 or 24.04 VM:

```bash
bash <(curl -s https://raw.githubusercontent.com/uthrapathy-m/cks-course-environment/main/cluster-setup/latest/install_master.sh)
```

### Worker node

```bash
bash <(curl -s https://raw.githubusercontent.com/uthrapathy-m/cks-course-environment/master/cluster-setup/latest/install_worker.sh)
```


