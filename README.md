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


## Install your worker key on control-plane using an existing working login

### 1) On worker: Create and show your public key

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
```

```bash
cat /root/.ssh/id_ed25519.pub
```

Copy the full line.

### 2) Log in to control-plane as a user that works (not root)

Example:

```bash
ssh <user>@<master-node-ip>
```

### 3) On control-plane: add the key for root

```bash
sudo mkdir -p /root/.ssh
sudo chmod 700 /root/.ssh
sudo bash -c 'echo "PASTE_PUBLIC_KEY_HERE" >> /root/.ssh/authorized_keys'
sudo chmod 600 /root/.ssh/authorized_keys
```

### 4) Back on worker: try SSH again

```bash
ssh root@10.160.0.26
```

Then SCP:

```bash
mkdir -p /root/.kube
scp root@10.160.0.26:/etc/kubernetes/admin.conf /root/.kube/config
chmod 600 /root/.kube/config
kubectl get nodes
```

