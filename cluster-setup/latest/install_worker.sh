#!/bin/bash

################################################################################
# Universal Kubernetes Worker Node Installation Script
# Supports: Ubuntu 20.04/22.04/24.04, Debian 11/12, CentOS 7/8/9, RHEL 8/9, Rocky Linux 8/9
# Allows: Kubernetes version selection, Container runtime selection
################################################################################

set -e

################################################################################
# CONFIGURATION - MODIFY THESE AS NEEDED
################################################################################

# Kubernetes version (should match master node)
KUBE_VERSION="${KUBE_VERSION:-1.32.5}"

# Container runtime: containerd, crio, or docker (should match master node)
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-containerd}"

################################################################################
# COLORS AND FORMATTING
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
    echo ""
}

################################################################################
# DETECT LINUX DISTRIBUTION
################################################################################

detect_os() {
    print_header "Detecting Operating System"
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        OS_MAJOR_VERSION=$(echo $VERSION_ID | cut -d. -f1)
    else
        print_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
    
    print_info "Detected OS: $PRETTY_NAME"
    print_info "OS ID: $OS"
    print_info "Version: $OS_VERSION"
    
    case $OS in
        ubuntu)
            if [[ "$OS_VERSION" != "20.04" && "$OS_VERSION" != "22.04" && "$OS_VERSION" != "24.04" ]]; then
                print_warning "Ubuntu $OS_VERSION is not officially tested. Recommended: 20.04, 22.04, or 24.04"
                read -p "Continue anyway? (yes/no): " confirm
                [[ "$confirm" != "yes" ]] && exit 1
            fi
            OS_FAMILY="debian"
            ;;
        debian)
            if [[ "$OS_MAJOR_VERSION" != "11" && "$OS_MAJOR_VERSION" != "12" ]]; then
                print_warning "Debian $OS_VERSION is not officially tested. Recommended: 11 or 12"
                read -p "Continue anyway? (yes/no): " confirm
                [[ "$confirm" != "yes" ]] && exit 1
            fi
            OS_FAMILY="debian"
            ;;
        centos|rhel|rocky|almalinux)
            if [[ "$OS_MAJOR_VERSION" != "7" && "$OS_MAJOR_VERSION" != "8" && "$OS_MAJOR_VERSION" != "9" ]]; then
                print_warning "$PRETTY_NAME is not officially tested. Recommended: 7, 8, or 9"
                read -p "Continue anyway? (yes/no): " confirm
                [[ "$confirm" != "yes" ]] && exit 1
            fi
            OS_FAMILY="rhel"
            ;;
        fedora)
            OS_FAMILY="rhel"
            print_warning "Fedora support is experimental"
            ;;
        *)
            print_error "Unsupported OS: $OS"
            print_info "Supported: Ubuntu, Debian, CentOS, RHEL, Rocky Linux, AlmaLinux"
            exit 1
            ;;
    esac
    
    print_success "OS detection complete: $OS ($OS_FAMILY family)"
}

################################################################################
# DETECT ARCHITECTURE
################################################################################

detect_architecture() {
    print_header "Detecting System Architecture"
    
    ARCH=$(uname -m)
    
    case $ARCH in
        x86_64)
            PLATFORM="amd64"
            ;;
        aarch64|arm64)
            PLATFORM="arm64"
            ;;
        armv7l)
            PLATFORM="arm"
            ;;
        *)
            print_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac
    
    print_success "Architecture: $ARCH (Platform: $PLATFORM)"
}

################################################################################
# SET HOSTNAME
################################################################################

set_hostname() {
    print_header "Setting Hostname"
    
    short_hostname=$(hostname | cut -d. -f1)
    hostnamectl set-hostname "$short_hostname" || true
    
    print_success "Hostname set to: $short_hostname"
}

################################################################################
# SETUP TERMINAL ENVIRONMENT
################################################################################

setup_terminal() {
    print_header "Setting Up Terminal Environment"
    
    # Install common utilities
    if [ "$OS_FAMILY" = "debian" ]; then
        apt-get update -qq
        apt-get install -y vim bash-completion curl wget gnupg2 software-properties-common apt-transport-https ca-certificates
    else
        yum install -y vim bash-completion curl wget gnupg2 yum-utils
    fi
    
    # VIM configuration
    cat >> ~/.vimrc <<EOF
colorscheme ron
set tabstop=2
set shiftwidth=2
set expandtab
syntax on
EOF
    
    # Bash configuration
    cat >> ~/.bashrc <<'EOF'
# Kubernetes aliases
alias k=kubectl
alias c=clear
source <(kubectl completion bash) 2>/dev/null || true
complete -F __start_kubectl k 2>/dev/null || true

# Colorful prompt
export PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
force_color_prompt=yes
EOF
    
    print_success "Terminal environment configured"
}

################################################################################
# DISABLE SWAP
################################################################################

disable_swap() {
    print_header "Disabling Swap"
    
    swapoff -a
    sed -i '/\sswap\s/ s/^\(.*\)$/#\1/g' /etc/fstab
    
    print_success "Swap disabled"
}

################################################################################
# CONFIGURE KERNEL MODULES AND SYSCTL
################################################################################

configure_kernel() {
    print_header "Configuring Kernel Modules and sysctl"
    
    # Load kernel modules
    cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
    
    modprobe overlay
    modprobe br_netfilter
    
    # Configure sysctl
    cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
    
    sysctl --system > /dev/null 2>&1
    
    print_success "Kernel configured for Kubernetes"
}

################################################################################
# DISABLE SELINUX (RHEL-based systems)
################################################################################

disable_selinux() {
    if [ "$OS_FAMILY" = "rhel" ]; then
        print_header "Configuring SELinux"
        
        if [ -f /etc/selinux/config ]; then
            setenforce 0 || true
            sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
            print_success "SELinux set to permissive mode"
        fi
    fi
}

################################################################################
# DISABLE FIREWALL (Optional - for learning environments)
################################################################################

disable_firewall() {
    print_header "Configuring Firewall"
    
    print_warning "Disabling firewall for learning environment"
    print_warning "In production, configure firewall rules properly!"
    
    if [ "$OS_FAMILY" = "debian" ]; then
        systemctl stop ufw 2>/dev/null || true
        systemctl disable ufw 2>/dev/null || true
        
        # Disable AppArmor
        systemctl stop apparmor 2>/dev/null || true
        systemctl disable apparmor 2>/dev/null || true
    else
        systemctl stop firewalld 2>/dev/null || true
        systemctl disable firewalld 2>/dev/null || true
    fi
    
    print_success "Firewall disabled"
}

################################################################################
# INSTALL CONTAINER RUNTIME - CONTAINERD
################################################################################

install_containerd() {
    print_header "Installing containerd"
    
    if [ "$OS_FAMILY" = "debian" ]; then
        # Install containerd from Docker repository
        curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        
        echo "deb [arch=$PLATFORM signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$OS $(lsb_release -cs) stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        apt-get update -qq
        apt-get install -y containerd.io
    else
        # RHEL-based systems
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y containerd.io
    fi
    
    # Configure containerd
    mkdir -p /etc/containerd
    containerd config default | tee /etc/containerd/config.toml > /dev/null
    
    # Enable SystemdCgroup
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    
    # Configure registry mirrors
    sed -i '/\[plugins."io.containerd.grpc.v1.cri".registry.mirrors\]/a\        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]\n          endpoint = ["https://mirror.gcr.io", "https://registry-1.docker.io"]' /etc/containerd/config.toml
    
    # Configure crictl
    cat <<EOF | tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
EOF
    
    systemctl daemon-reload
    systemctl enable containerd
    systemctl restart containerd
    
    print_success "containerd installed and configured"
}

################################################################################
# INSTALL CONTAINER RUNTIME - CRI-O
################################################################################

install_crio() {
    print_header "Installing CRI-O"
    
    CRIO_VERSION=$(echo $KUBE_VERSION | cut -d. -f1,2)
    
    if [ "$OS_FAMILY" = "debian" ]; then
        curl -fsSL https://pkgs.k8s.io/addons:/cri-o:/stable:/v${CRIO_VERSION}/deb/Release.key | \
            gpg --dearmor -o /usr/share/keyrings/cri-o-apt-keyring.gpg
        
        echo "deb [signed-by=/usr/share/keyrings/cri-o-apt-keyring.gpg] https://pkgs.k8s.io/addons:/cri-o:/stable:/v${CRIO_VERSION}/deb/ /" | \
            tee /etc/apt/sources.list.d/cri-o.list
        
        apt-get update -qq
        apt-get install -y cri-o
    else
        curl -L -o /etc/yum.repos.d/cri-o.repo https://pkgs.k8s.io/addons:/cri-o:/stable:/v${CRIO_VERSION}/rpm/cri-o.repo
        yum install -y cri-o
    fi
    
    systemctl daemon-reload
    systemctl enable crio
    systemctl start crio
    
    print_success "CRI-O installed and configured"
}

################################################################################
# INSTALL CONTAINER RUNTIME - DOCKER (Legacy)
################################################################################

install_docker() {
    print_header "Installing Docker (Legacy)"
    
    print_warning "Docker as container runtime is deprecated in Kubernetes"
    print_warning "Consider using containerd or CRI-O instead"
    
    if [ "$OS_FAMILY" = "debian" ]; then
        curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        
        echo "deb [arch=$PLATFORM signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$OS $(lsb_release -cs) stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        apt-get update -qq
        apt-get install -y docker-ce docker-ce-cli
    else
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli
    fi
    
    # Configure Docker daemon
    mkdir -p /etc/docker
    cat <<EOF | tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
    
    systemctl daemon-reload
    systemctl enable docker
    systemctl restart docker
    
    # Install cri-dockerd (required for k8s 1.24+)
    install_cri_dockerd
    
    print_success "Docker installed and configured"
}

################################################################################
# INSTALL CRI-DOCKERD (for Docker runtime with k8s 1.24+)
################################################################################

install_cri_dockerd() {
    print_info "Installing cri-dockerd..."
    
    CRI_DOCKERD_VERSION="0.3.9"
    
    if [ ! -f /usr/local/bin/cri-dockerd ]; then
        cd /tmp
        wget https://github.com/Mirantis/cri-dockerd/releases/download/v${CRI_DOCKERD_VERSION}/cri-dockerd-${CRI_DOCKERD_VERSION}.${PLATFORM}.tgz
        tar -xzf cri-dockerd-${CRI_DOCKERD_VERSION}.${PLATFORM}.tgz
        mv cri-dockerd/cri-dockerd /usr/local/bin/
        
        # Install systemd units
        wget -O /etc/systemd/system/cri-docker.service https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.service
        wget -O /etc/systemd/system/cri-docker.socket https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.socket
        
        sed -i 's|/usr/bin/cri-dockerd|/usr/local/bin/cri-dockerd|g' /etc/systemd/system/cri-docker.service
        
        systemctl daemon-reload
        systemctl enable cri-docker.service
        systemctl enable cri-docker.socket
        systemctl start cri-docker.service
        systemctl start cri-docker.socket
        
        print_success "cri-dockerd installed"
    fi
}

################################################################################
# INSTALL KUBERNETES PACKAGES
################################################################################

install_kubernetes() {
    print_header "Installing Kubernetes v${KUBE_VERSION}"
    
    KUBE_MAJOR_VERSION=$(echo $KUBE_VERSION | cut -d. -f1,2)
    
    if [ "$OS_FAMILY" = "debian" ]; then
        # Add Kubernetes repository
        curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBE_MAJOR_VERSION}/deb/Release.key | \
            gpg --dearmor -o /usr/share/keyrings/kubernetes-apt-keyring.gpg
        
        echo "deb [signed-by=/usr/share/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBE_MAJOR_VERSION}/deb/ /" | \
            tee /etc/apt/sources.list.d/kubernetes.list
        
        apt-get update -qq
        
        # Install specific version or latest
        if [ -n "$KUBE_VERSION" ]; then
            apt-get install -y kubelet=${KUBE_VERSION}-* kubeadm=${KUBE_VERSION}-* kubectl=${KUBE_VERSION}-*
        else
            apt-get install -y kubelet kubeadm kubectl
        fi
        
        apt-mark hold kubelet kubeadm kubectl
    else
        # RHEL-based systems
        cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${KUBE_MAJOR_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${KUBE_MAJOR_VERSION}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
        
        if [ -n "$KUBE_VERSION" ]; then
            yum install -y kubelet-${KUBE_VERSION} kubeadm-${KUBE_VERSION} kubectl-${KUBE_VERSION} --disableexcludes=kubernetes
        else
            yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
        fi
    fi
    
    systemctl enable kubelet
    
    print_success "Kubernetes packages installed"
}

################################################################################
# CONFIGURE KUBECTL FOR WORKER (Optional but Recommended)
################################################################################

configure_kubectl() {
    print_header "Configuring kubectl on Worker Node"
    
    print_warning "Worker nodes don't have kubectl configured by default!"
    print_info "kubectl is installed but needs kubeconfig from master node"
    echo ""
    echo "You have three options:"
    echo ""
    echo "  1. Configure kubectl now (Recommended for learning/CKS prep)"
    echo "     - Copy admin.conf from master"
    echo "     - Full cluster access from worker node"
    echo ""
    echo "  2. Configure kubectl manually later"
    echo "     - Follow documentation in Worker_kubectl_Fix.md"
    echo ""
    echo "  3. Always use master node for kubectl"
    echo "     - SSH to master for all kubectl commands"
    echo ""
    
    read -p "Do you want to configure kubectl now? (yes/no): " configure_now
    
    if [ "$configure_now" = "yes" ]; then
        echo ""
        read -p "Enter master node IP address: " master_node
        
        # Validate IP format (basic check)
        if ! echo "$master_node" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
            print_warning "Invalid IP format. Will try anyway..."
        fi
        
        print_info "Testing connection to master node..."
        if ! ping -c 1 -W 2 "$master_node" &>/dev/null; then
            print_warning "Cannot ping master node. Continuing anyway..."
        else
            print_success "Master node is reachable"
        fi
        
        mkdir -p ~/.kube
        
        print_info "Attempting to copy kubeconfig from master..."
        print_info "You may be prompted for the master node's root password"
        echo ""
        
        # Try to copy with more verbose output
        if scp -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
               root@${master_node}:/etc/kubernetes/admin.conf ~/.kube/config 2>&1; then
            
            # Set proper permissions
            chmod 600 ~/.kube/config
            chown $(id -u):$(id -g) ~/.kube/config
            
            # Configure environment
            export KUBECONFIG=~/.kube/config
            if ! grep -q "export KUBECONFIG" ~/.bashrc 2>/dev/null; then
                echo "export KUBECONFIG=~/.kube/config" >> ~/.bashrc
            fi
            
            echo ""
            print_success "kubectl configured successfully!"
            print_info "Testing kubectl access..."
            
            # Test kubectl
            if kubectl get nodes &>/dev/null; then
                print_success "kubectl is working!"
                echo ""
                kubectl get nodes
            else
                print_warning "kubectl configured but cannot connect yet"
                print_info "You may need to join this node to the cluster first"
            fi
            
        else
            echo ""
            print_error "Could not copy kubeconfig automatically"
            echo ""
            print_info "Manual configuration steps:"
            echo ""
            echo "1. On master node, run:"
            echo "   cat /etc/kubernetes/admin.conf"
            echo ""
            echo "2. On this worker node, run:"
            echo "   mkdir -p ~/.kube"
            echo "   vi ~/.kube/config"
            echo "   # Paste the content from step 1, save and exit"
            echo ""
            echo "3. Set permissions:"
            echo "   chmod 600 ~/.kube/config"
            echo "   export KUBECONFIG=~/.kube/config"
            echo "   echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc"
            echo ""
            print_info "Or use the automated script:"
            echo "   curl -O https://your-repo/setup-kubectl-worker.sh"
            echo "   chmod +x setup-kubectl-worker.sh"
            echo "   ./setup-kubectl-worker.sh"
            echo ""
        fi
    else
        echo ""
        print_info "Skipping kubectl configuration"
        print_info "To configure later, see: Worker_kubectl_Fix.md"
        echo ""
        print_warning "kubectl will NOT work on this node until configured!"
        echo ""
        print_info "Quick manual setup:"
        echo "  mkdir -p ~/.kube"
        echo "  scp root@<master-ip>:/etc/kubernetes/admin.conf ~/.kube/config"
        echo "  chmod 600 ~/.kube/config"
        echo "  export KUBECONFIG=~/.kube/config"
        echo "  echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc"
        echo ""
    fi
}

################################################################################
# PRINT JOIN INSTRUCTIONS
################################################################################

print_join_instructions() {
    print_header "Worker Node Setup Complete"
    
    echo ""
    echo "=========================================="
    echo "WORKER NODE READY TO JOIN CLUSTER"
    echo "=========================================="
    echo ""
    echo "To join this worker to the cluster, follow these steps:"
    echo ""
    echo "1. On the MASTER node, run:"
    echo "   kubeadm token create --print-join-command --ttl 0"
    echo ""
    echo "2. Copy the output command and run it on THIS worker node"
    echo ""
    
    if [ "$CONTAINER_RUNTIME" = "docker" ]; then
        echo "3. Since you're using Docker runtime, append this to the join command:"
        echo "   --cri-socket unix:///var/run/cri-dockerd.sock"
        echo ""
        echo "   Example:"
        echo "   kubeadm join <master-ip>:6443 --token <token> \\"
        echo "     --discovery-token-ca-cert-hash sha256:<hash> \\"
        echo "     --cri-socket unix:///var/run/cri-dockerd.sock"
    elif [ "$CONTAINER_RUNTIME" = "crio" ]; then
        echo "3. Since you're using CRI-O runtime, append this to the join command:"
        echo "   --cri-socket unix:///var/run/crio/crio.sock"
        echo ""
        echo "   Example:"
        echo "   kubeadm join <master-ip>:6443 --token <token> \\"
        echo "     --discovery-token-ca-cert-hash sha256:<hash> \\"
        echo "     --cri-socket unix:///var/run/crio/crio.sock"
    else
        echo "3. Run the join command as-is"
        echo ""
        echo "   Example:"
        echo "   kubeadm join <master-ip>:6443 --token <token> \\"
        echo "     --discovery-token-ca-cert-hash sha256:<hash>"
    fi
    
    echo ""
    echo "4. Verify on master node:"
    echo "   kubectl get nodes"
    echo ""
}

################################################################################
# MAIN INSTALLATION FLOW
################################################################################

main() {
    print_header "Kubernetes Worker Node Installation"
    print_info "Configuration:"
    print_info "  Kubernetes Version: ${KUBE_VERSION}"
    print_info "  Container Runtime: ${CONTAINER_RUNTIME}"
    echo ""
    
    print_warning "IMPORTANT: Container runtime and Kubernetes version should match the master node!"
    echo ""
    
    read -p "Proceed with installation? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        print_error "Installation cancelled"
        exit 0
    fi
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
    
    # Installation steps
    detect_os
    detect_architecture
    set_hostname
    setup_terminal
    disable_swap
    configure_kernel
    disable_selinux
    disable_firewall
    
    # Install container runtime
    case $CONTAINER_RUNTIME in
        containerd)
            install_containerd
            ;;
        crio)
            install_crio
            ;;
        docker)
            install_docker
            ;;
        *)
            print_error "Unsupported container runtime: $CONTAINER_RUNTIME"
            exit 1
            ;;
    esac
    
    install_kubernetes
    
    # Optional kubectl configuration
    configure_kubectl
    
    print_join_instructions
    
    print_success "Worker node installation complete!"
    print_info "Re-login to apply bash configuration changes"
}

# Run main function
main "$@"
